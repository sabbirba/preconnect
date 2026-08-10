use std::fs;
use std::path::PathBuf;
use std::str::FromStr;
/*
 * preprintd - Printer swarm listener/worker implementation for PreConnect.
 * Copyright (C) 2026  Anindya Shiddhartha & contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */
use std::sync::LazyLock;
use std::sync::atomic::AtomicBool;
use std::{
    env,
    io::{BufRead, BufReader},
    net::{TcpStream, ToSocketAddrs},
    sync::{
        Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    thread::sleep,
    time::{Duration, Instant},
};

#[macro_use]
mod macros;

mod client;
mod consts;
mod crypto;
mod doh;
mod tcp_extras;
mod types;
mod utils;

mod zbus;

use anyhow::Result;
use reqwest::{
    StatusCode,
    header::{HeaderMap, HeaderValue},
};
use serde_json::{Value, json};
use socket2::SockRef;
use tcp_extras::TcpExtras;

use crate::utils::create_new_ident;

#[cfg(target_os = "linux")]
use crate::zbus::acquire_sleep_inhibitor;

use crate::{
    client::client,
    consts::{BASE_DOMAIN_NOAPI, BASE_URL},
    crypto::{decrypt, make_subscriber_jwt},
    types::{Job, LogLevel},
};

static DEBUG: LazyLock<bool> = LazyLock::new(|| env::args().any(|arg| arg == "--debug"));
static IS_PRINT_PROCESSING: AtomicBool = AtomicBool::new(false);

#[cfg(target_os = "linux")]
static INHIBIT: LazyLock<bool> = LazyLock::new(|| env::args().any(|arg| arg == "--inhibit"));

static LAST_EVENT_ID: LazyLock<Mutex<Option<String>>> = LazyLock::new(|| Mutex::new(None));
static STATE_DIR: LazyLock<Option<PathBuf>> = LazyLock::new(|| {
    let Ok(p) = env::var("STATE_DIRECTORY") else {
        return None;
    };
    Some(PathBuf::from_str(&p).expect("invalid STATE_DIRECTORY env var"))
});

pub static WORKER_IDENT: LazyLock<String> = LazyLock::new(|| {
    let fallback = create_new_ident();
    let Some(p) = &*STATE_DIR else {
        debug_log!(
            LogLevel::Warn,
            "State directory indeterminate; using dyn ident..."
        );
        return fallback;
    };

    let p = p.join(".ident");
    let dir_exists = p
        .parent()
        .and_then(|f| Some(f.try_exists().unwrap_or(false)))
        .unwrap_or(false);
    let file_exists = p.try_exists().unwrap_or(false);

    if !file_exists {
        if !dir_exists {
            if let Err(e) = fs::create_dir_all(&p) {
                debug_log!(
                    LogLevel::Error,
                    "Non-existent state directory creation failure: {e}; using dyn ident..."
                );
                return fallback;
            }
        }

        if let Err(e) = fs::write(&p, fallback.as_str()) {
            debug_log!(
                LogLevel::Error,
                ".ident write failure: {e}; using dyn ident..."
            );
            return fallback;
        }
    }

    let ident = match fs::read_to_string(&p) {
        Ok(d) => {
            if !d.is_empty() {
                d.trim().to_string()
            } else {
                debug_log!(LogLevel::Ok, "Empty ident file, creating new identity...");
                fallback
            }
        }
        Err(e) => {
            debug_log!(
                LogLevel::Warn,
                "Failed to read state dir path ({p:?}): {e}; using dyn ident..."
            );
            fallback
        }
    };

    ident
});

static ALIAS: LazyLock<String> =
    LazyLock::new(|| env::var("ALIAS").unwrap_or("preprintd".to_string()));

static WORKER_KEY: LazyLock<String> =
    LazyLock::new(|| env::var("WORKER_KEY").expect("missing WORKER_KEY env var"));
static AGENT: LazyLock<String> = LazyLock::new(|| format!("{}/1.0", ALIAS.as_str()));
static JOBS_COMPLETED: AtomicUsize = AtomicUsize::new(0);
static DEF_HOST: LazyLock<String> =
    LazyLock::new(|| env::var("DEF_HOST").expect("missing DEF_HOST env var"));
static DEF_QUEUE: LazyLock<String> =
    LazyLock::new(|| env::var("DEF_QUEUE").expect("missing DEF_QUEUE env var"));

const DEF_PORT: u16 = 515;
const NUL: [u8; 1] = [0u8];

fn is_online(host: &str) -> Result<bool> {
    if host.is_empty() {
        return Ok(false);
    }
    sock!(s, host, DEF_PORT, Duration::from_millis(800));

    if let Ok(conn) = s {
        let _ = conn.shutdown(std::net::Shutdown::Both);
    } else {
        return Ok(false);
    }

    Ok(true)
}

fn hdrs() -> Result<HeaderMap> {
    let mut map = HeaderMap::new();
    let jobs = JOBS_COMPLETED.load(Ordering::Relaxed).to_string();

    map.insert("User-Agent", HeaderValue::from_str(&AGENT)?);
    map.insert("X-Worker-Key", HeaderValue::from_str(&WORKER_KEY)?);
    map.insert("X-Worker-Jobs", HeaderValue::from_str(&jobs)?);
    map.insert("X-Worker-Ident", HeaderValue::from_str(&WORKER_IDENT)?);

    Ok(map)
}

fn claim_job(id: &str) -> Result<bool> {
    let body = json!({ "id": id });

    let resp = client()
        .post(format!("{BASE_URL}/print/claim"))
        .body(body.to_string())
        .header("Content-Type", "application/json")
        .headers(hdrs()?)
        .timeout(Duration::from_secs(5))
        .send();

    let claim = match resp {
        Ok(r) => {
            if r.status() != StatusCode::OK {
                debug_log!(
                    LogLevel::Warn,
                    "Status code not OK, so skipping on this job..."
                );
                return Ok(false);
            }

            let Ok(value) = r.json::<Value>() else {
                debug_log!(LogLevel::Warn, "Parsing failed, so skipping on this job...");
                return Ok(false);
            };

            value
                .get("claimed")
                .and_then(Value::as_bool)
                .unwrap_or(false)
        }
        Err(e) => {
            debug_log!(LogLevel::Error, "(Send) /print/claim: {e}");
            false
        }
    };

    if claim {
        debug_log!(LogLevel::Ok, "Claimed new job!");
    } else {
        debug_log!(LogLevel::Warn, "Skipping on this job...");
    }

    Ok(claim)
}

fn handle(job: Job) -> Result<()> {
    let job_id = {
        if let Some(j_id) = job.id.as_deref()
            && !j_id.is_empty()
        {
            j_id
        } else {
            debug_log!(
                LogLevel::Error,
                "Empty job ID received from job description; skipping job..."
            );
            return Ok(());
        }
    };

    let host = job
        .printer_host
        .as_deref()
        .filter(|host| !host.is_empty())
        .unwrap_or(&DEF_HOST);

    let queue_name = job
        .printer_queue
        .as_deref()
        .filter(|queue| !queue.is_empty())
        .unwrap_or(&DEF_QUEUE);

    if !is_online(host)? || !(claim_job(job_id)?) {
        return Ok(());
    }

    let q_cmd = decrypt(job.q_cmd.as_deref(), job_id)?;
    let cf_hdr = decrypt(job.cf_hdr.as_deref(), job_id)?;
    let ctl = decrypt(job.ctl.as_deref(), job_id)?;
    let df_hdr = decrypt(job.df_hdr.as_deref(), job_id)?;
    let payload = decrypt(job.payload.as_deref(), job_id)?;

    debug_log!(
        LogLevel::Ok,
        "Handling job for {host}:{queue_name} (payload size: {} bytes)",
        payload.len()
    );

    let timeout = Duration::from_secs_f64(
        job.timeout
            .filter(|timeout| timeout.is_finite() && *timeout > 0.0)
            .unwrap_or(60.0),
    );

    sock!(s, host, DEF_PORT, timeout);
    let mut socket = match s {
        Ok(s) => s,
        Err(e) => {
            debug_log!(
                LogLevel::Error,
                "Failed to connect to {host}:{DEF_PORT}: {e}"
            );
            return Ok(());
        }
    };

    let transferred = (|| -> std::io::Result<bool> {
        socket.set_nodelay(true)?;
        socket.set_read_timeout(Some(timeout))?;
        socket.set_write_timeout(Some(timeout))?;

        SockRef::from(&socket).set_send_buffer_size(65_536)?;

        Ok(socket.send_buf(&q_cmd)?
            && socket.recv_ack()?
            && socket.send_buf(&cf_hdr)?
            && socket.recv_ack()?
            && socket.send_buf(&ctl)?
            && socket.send_buf(&NUL)?
            && socket.recv_ack()?
            && socket.send_buf(&df_hdr)?
            && socket.recv_ack()?
            && socket.send_buf(&payload)?
            && socket.send_buf(&NUL)?
            && socket.recv_ack()?)
    })();

    let abortive = match transferred {
        Ok(true) => {
            debug_log!(
                LogLevel::Ok,
                "Job transferred successfully. \
                 Shutting down current socket connection."
            );

            JOBS_COMPLETED.fetch_add(1, Ordering::Relaxed);
            false
        }
        Ok(false) => false,
        Err(e) => {
            debug_log!(LogLevel::Error, "Printer transfer failed: {e}");
            let _ = SockRef::from(&socket).set_linger(Some(Duration::ZERO));
            true
        }
    };

    if !abortive {
        let _ = socket.shutdown(std::net::Shutdown::Both);
    }

    Ok(())
}

fn stream() -> Result<()> {
    let mut headers = hdrs()?;

    if let Some(last_event_id) = LAST_EVENT_ID
        .lock()
        .expect("last event ID mutex lock poisoned")
        .as_deref()
        .filter(|id| !id.is_empty())
    {
        headers.insert("Last-Event-ID", HeaderValue::from_str(last_event_id)?);
    }

    let resp = match client()
        .get(format!(
            "{BASE_URL}/.well-known/mercure?topic=https%3A%2F%2F{BASE_DOMAIN_NOAPI}%2Fprinter",
        ))
        .header("Accept", "text/event-stream")
        .header(
            "Authorization",
            format!("Bearer {}", make_subscriber_jwt(&WORKER_KEY)),
        )
        .headers(headers)
        .send()
    {
        Ok(r) => {
            if r.status() == StatusCode::UNAUTHORIZED {
                debug_log!(
                    LogLevel::Error,
                    "worker key invalid ({})",
                    r.status().as_u16()
                );
                return Ok(());
            }

            if r.status() != StatusCode::OK {
                debug_log!(LogLevel::Error, "(Status) mercure endpoint: {}", r.status());
                return Ok(());
            }

            r
        }

        Err(e) => {
            debug_log!(LogLevel::Error, "(Send) mercure endpoint: {e}");
            return Ok(());
        }
    };

    let mut reader = BufReader::new(resp);
    let mut line = String::new();

    loop {
        line.clear();

        if reader.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }

        if line.starts_with(':') {
            continue;
        } else if let Some(data) = line.strip_prefix("id: ") {
            let mut l = LAST_EVENT_ID
                .lock()
                .expect("last event ID mutex lock poisoned");
            *l = Some(data.trim().to_string());
        } else if let Some(data) = line.strip_prefix("data: ")
            && let Ok(value) = serde_json::from_str::<Job>(data)
        {
            debug_log!(LogLevel::Ok, "Data match for new job!");

            if IS_PRINT_PROCESSING
                .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
                .is_ok()
            {
                if let Err(e) = std::thread::Builder::new().spawn(move || {
                    let _ = handle(value);
                    IS_PRINT_PROCESSING.store(false, Ordering::Release);
                }) {
                    IS_PRINT_PROCESSING.store(false, Ordering::Release);
                    debug_log!(LogLevel::Error, "Failed to spawn print thread: {e}");
                }
            }
        }
    }

    Ok(())
}

fn ping() -> Result<()> {
    loop {
        let _ = client()
            .post(format!("{BASE_URL}/print/ping"))
            .headers(hdrs()?)
            .send()?;
        std::thread::sleep(Duration::from_millis(5000));
    }
}

fn main() -> Result<()> {
    let mut iter_count = 0;
    let mut delay = 1.0_f64;

    #[cfg(target_os = "linux")]
    if *INHIBIT {
        let _sleep_inhibitor = acquire_sleep_inhibitor()?;
    }

    std::thread::spawn(|| {
        if let Err(e) = ping() {
            debug_log!(LogLevel::Error, "Ping thread stopped: {e}");
        }
    });

    loop {
        debug_log!(
            LogLevel::Ok,
            "Connection #{iter_count}; Jobs completed: {}",
            JOBS_COMPLETED.load(Ordering::Relaxed)
        );

        let started_at = Instant::now();
        let result = stream();

        let long_stream = started_at.elapsed() > Duration::from_secs(10);
        delay = if result.is_ok() && long_stream {
            debug_log!(
                LogLevel::Ok,
                "Refreshing Mercure event stream connection..."
            );
            1.0
        } else {
            let next_delay = (delay * 2.0).min(8.0);
            debug_log!(
                LogLevel::Warn,
                "Re-establishing stream connection (backoff: {next_delay:.1}s)..."
            );
            next_delay
        };

        sleep(Duration::from_secs_f64(delay));
        iter_count += 1;
    }
}
