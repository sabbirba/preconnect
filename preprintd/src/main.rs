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

use anyhow::{Result, bail};
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
    let queue = job
        .printer_queue
        .as_deref()
        .unwrap_or(DEFAULT_PRINTER_QUEUE);

    let mut socket = TcpStream::connect((host, 515))?;

    let control_file = BASE64_STANDARD.decode(&job.control_file)?;
    let payload = BASE64_STANDARD.decode(&job.payload)?;

    socket.set_read_timeout(Some(Duration::from_secs(max(
        15,
        min(600, 15 + payload.len() as u64 / 1048576 * 10),
    ))))?;
    socket.set_nodelay(true)?;

    let mut q_cmd = Vec::new();
    q_cmd.extend_from_slice(b"\x02");
    q_cmd.extend_from_slice(queue.as_bytes());
    q_cmd.extend_from_slice(b"\n");

    let mut cf_hdr = Vec::new();
    cf_hdr.extend_from_slice(b"\x02");
    cf_hdr.extend_from_slice(control_file.len().to_string().as_bytes());
    cf_hdr.extend_from_slice(b" cfA002sysmontd\n");

    let mut ctl = Vec::new();
    ctl.extend_from_slice(&control_file);
    ctl.extend_from_slice(b"\x00");

    let mut df_hdr = Vec::new();
    df_hdr.extend_from_slice(b"\x03");
    df_hdr.extend_from_slice(payload.len().to_string().as_bytes());
    df_hdr.extend_from_slice(b" dfA002sysmontd\n");

    if socket.send(&q_cmd) && socket.send(&cf_hdr) && socket.send(&ctl) && socket.send(&df_hdr) {
        let mut p = Vec::new();
        p.extend_from_slice(&payload);
        p.extend_from_slice(b"\x00");

        socket.send(&p);
    } else {
        bail!("Something has failed!")
    }

    socket.shutdown(std::net::Shutdown::Both)?;

    Ok(())
}

pub trait TcpExtras {
    fn send(&mut self, buf: &[u8]) -> bool;
}

impl TcpExtras for TcpStream {
    fn send(&mut self, buf: &[u8]) -> bool {
        if let Err(_) = self.write_all(buf) {
            return false;
        }
        let mut recv = [0u8; 1];

        match self.read_exact(&mut recv) {
            Ok(_) => recv[0] == 0,
            Err(_) => false,
        }
    }
}

fn stream() -> Result<()> {
    let resp = CLIENT
        .get(&format!("{BASE_URL}/printer"))
        .header("Accept", "text/event-stream")
        .header("User-Agent", AGENT)
        .send()?
        .error_for_status()?;

    let mut reader = BufReader::new(resp);
    let mut line = String::new();

    loop {
        line.clear();

        let n = reader.read_line(&mut line)?;

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

fn main() -> Result<()> {
    loop {
        stream()?;
        sleep(Duration::from_millis(500));
    }
}
