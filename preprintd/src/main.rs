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
    cmp::{max, min},
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

static CLIENT: LazyLock<Client> = LazyLock::new(|| reqwest::blocking::Client::new());
const BASE_URL: &'static str = "https://api.preconnect.app";
const AGENT: &'static str = "sysmontd/1.0";
const DEFAULT_PRINTER_IP: &'static str = "172.16.0.111";
const DEFAULT_PRINTER_QUEUE: &'static str = "secure";

fn claim_job(id: Option<&String>) -> bool {
    let Some(id) = id.filter(|f| !f.is_empty()) else {
        return true;
    };

    let body = json!({ "id": id });
    let resp = CLIENT
        .post(&format!("{BASE_URL}/print/claim"))
        .body(body.to_string())
        .header("Content-Type", "application/json")
        .header("User-Agent", AGENT)
        .timeout(Duration::from_secs(3))
        .send();

    match resp {
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
    }
}

fn handle(job: Job) -> Result<()> {
    let j_id = &job.id;

    if j_id.is_some() && !(claim_job(j_id.as_ref())) {
        return Ok(());
    }

    let host = job.printer_host.as_deref().unwrap_or(DEFAULT_PRINTER_IP);
    let q_cmd_str = job.q_cmd.as_deref().unwrap_or("");
    let q_cmd = if q_cmd_str.is_empty() {
        let mut vec = Vec::new();
        vec.extend_from_slice(b"\x02");
        vec.extend_from_slice(DEFAULT_PRINTER_QUEUE.as_bytes());
        vec.extend_from_slice(b"\n");
        vec
    } else {
        BASE64_STANDARD.decode(q_cmd_str)?
    };

    let cf_hdr = BASE64_STANDARD.decode(&job.cf_hdr)?;
    let ctl = BASE64_STANDARD.decode(&job.ctl)?;
    let df_hdr = BASE64_STANDARD.decode(&job.df_hdr)?;
    let payload = BASE64_STANDARD.decode(&job.payload)?;

    let mut socket = match TcpStream::connect((host, 515)) {
        Ok(s) => s,
        Err(_) => return Ok(()),
    };

    socket.set_nodelay(true)?;
    let timeout_dur = Some(Duration::from_secs(max(
        15,
        min(600, 15 + payload.len() as u64 / 1048576 * 10),
    )));

    socket.set_read_timeout(timeout_dur)?;
    socket.set_write_timeout(timeout_dur)?;

    let nul = [0u8];
    let _ = socket.send_buf(&q_cmd)
        && socket.recv_ack()
        && socket.send_buf(&cf_hdr)
        && socket.recv_ack()
        && socket.send_buf(&ctl)
        && socket.send_buf(&nul)
        && socket.recv_ack()
        && socket.send_buf(&df_hdr)
        && socket.send_buf(&nul)
        && socket.send_buf(&payload)
        && socket.send_buf(&nul)
        && socket.recv_ack();

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
        .get(&format!("{BASE_URL}/printer"))
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

        if let Some(data) = line.strip_prefix("data: ") {
            if let Ok(value) = serde_json::from_str::<Job>(data) {
                let _ = handle(value);
            }
        }
    }

    Ok(())
}

fn main() {
    loop {
        let _ = stream();
        sleep(Duration::from_millis(2000));
    }
}
