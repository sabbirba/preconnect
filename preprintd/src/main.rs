/*
 * preprintd - Printer swarm listener/worker implementation for PreConnect.
 * Copyright (C) 2026  Anindya Shiddhartha
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
    io::{BufRead, BufReader, Read, Write},
    net::TcpStream,
    sync::LazyLock,
    thread::sleep,
    time::Duration,
};

mod types;

use anyhow::Result;
use base64::prelude::*;
use reqwest::blocking::Client;
use serde_json::{Value, json};

use crate::types::Job;

static CLIENT: LazyLock<Client> = LazyLock::new(reqwest::blocking::Client::new);
static DEBUG: LazyLock<bool> = LazyLock::new(|| env::args().any(|arg| arg == "--debug"));
const BASE_URL: &str = "https://api.preconnect.app";
const AGENT: &str = "sysmontd/1.0";
const DEFAULT_PRINTER_IP: &str = "172.16.0.111";
const DEFAULT_PRINTER_QUEUE: &str = "secure";

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
        .post(format!("{BASE_URL}/print/claim"))
        .body(body.to_string())
        .header("Content-Type", "application/json")
        .header("User-Agent", AGENT)
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
        Err(_) => true,
    };

    debug_log!("Claim status for job: {claim}");
    claim
}

fn handle(job: Job) -> Result<()> {
    let j_id = &job.id;

    if j_id.is_some() && !(claim_job(j_id.as_ref())) {
        return Ok(());
    }

    let host = job.printer_host.as_deref().unwrap_or(DEFAULT_PRINTER_IP);
    let queue_name = job
        .printer_queue
        .as_deref()
        .unwrap_or(DEFAULT_PRINTER_QUEUE);

    let payload = match job.payload.as_deref() {
        Some(p) if !p.trim().is_empty() => BASE64_STANDARD.decode(p.trim())?,
        _ => return Ok(()),
    };

    let q_cmd = match job.q_cmd.as_deref() {
        Some(q) if !q.trim().is_empty() => BASE64_STANDARD.decode(q.trim())?,
        _ => format!("\x02{}\n", queue_name).into_bytes(),
    };

    let ctl = match (job.ctl.as_deref(), job.control_file.as_deref()) {
        (Some(c), _) if !c.trim().is_empty() => BASE64_STANDARD.decode(c.trim())?,
        (_, Some(cf)) if !cf.trim().is_empty() => BASE64_STANDARD.decode(cf.trim())?,
        _ => Vec::new(),
    };

    let cf_hdr = match job.cf_hdr.as_deref() {
        Some(ch) if !ch.trim().is_empty() => BASE64_STANDARD.decode(ch.trim())?,
        _ => format!("\x02{} cfA002sysmontd\n", ctl.len()).into_bytes(),
    };

    let df_hdr = match job.df_hdr.as_deref() {
        Some(dh) if !dh.trim().is_empty() => BASE64_STANDARD.decode(dh.trim())?,
        _ => format!("\x03{} dfA002sysmontd\n", payload.len()).into_bytes(),
    };

    debug_log!(
        "Handling job for {host}:{queue_name} (payload size: {} bytes)",
        payload.len()
    );

    let addr = (host, 515);
    let mut socket = match TcpStream::connect(addr) {
        Ok(s) => s,
        Err(_) => {
            debug_log!("Failed to connect using TcpStraem::connect to address: {addr:?}");
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
        debug_log!("Job transferred successfully. Shutting down socket connection.");
    }

    let _ = socket.shutdown(std::net::Shutdown::Both);
    Ok(())
}

pub trait TcpExtras {
    fn send_buf(&mut self, buf: &[u8]) -> bool;
    fn recv_ack(&mut self) -> bool;
}

impl TcpExtras for TcpStream {
    fn send_buf(&mut self, buf: &[u8]) -> bool {
        self.write_all(buf).is_ok()
    }

    fn recv_ack(&mut self) -> bool {
        let mut recv = [0u8; 1];
        match self.read_exact(&mut recv) {
            Ok(_) => recv[0] == 0,
            Err(_) => false,
        }
    }
}

fn stream() -> Result<()> {
    let resp = match CLIENT
        .get(format!("{BASE_URL}/printer"))
        .header("Accept", "text/event-stream")
        .header("User-Agent", AGENT)
        .send()
    {
        Ok(r) => match r.error_for_status() {
            Ok(res) => res,
            Err(_) => return Ok(()),
        },
        Err(_) => return Ok(()),
    };

    let mut reader = BufReader::new(resp);
    let mut line = String::new();

    loop {
        line.clear();

        let n = match reader.read_line(&mut line) {
            Ok(bytes) => bytes,
            Err(_) => break,
        };

        if n == 0 {
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
        debug_log!("Connection #{iter_count}");
        let _ = stream();
        sleep(Duration::from_millis(2000));
        iter_count += 1;
    }
}
