import base64
import json
import socket
import sys
import time
import urllib.request

def log(msg, level="INFO"):
    sys.stderr.write(f"[sysprint] [{level}] {msg}\n")
    sys.stderr.flush()

def claim_job(job_id):
    if not job_id:
        return True
    try:
        log(f"Attempting to claim print job id '{job_id}'...", level="DEBUG")
        req = urllib.request.Request(
            "https://api.preconnect.app/print/claim",
            data=f'{{"id":"{job_id}"}}'.encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "User-Agent": "sysprint/1.0"
            }
        )
        resp = urllib.request.urlopen(req, timeout=3)
        body = resp.read().replace(b" ", b"")
        claimed = b'"claimed":true' in body
        if claimed:
            log(f"Successfully claimed print job '{job_id}'", level="INFO")
        else:
            log(f"Print job '{job_id}' claim rejected (already claimed)", level="DEBUG")
        return claimed
    except Exception as e:
        log(f"Failed to claim job {job_id}: {e}", level="WARNING")
        return True

def stream():
    req = urllib.request.Request(
        "https://api.preconnect.app/printer",
        headers={
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache",
            "User-Agent": "sysprint/1.0"
        }
    )
    try:
        log("Connecting to relay stream https://api.preconnect.app/printer...", level="DEBUG")
        resp = urllib.request.urlopen(req)
        log("Connected to relay stream https://api.preconnect.app/printer", level="INFO")
        while True:
            line = resp.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="ignore").strip()
            if text.startswith("data: "):
                try:
                    job = json.loads(text[6:])
                    job_id = job.get("id")
                    log(f"Received event payload for job_id '{job_id}'", level="DEBUG")
                    if job_id and not claim_job(str(job_id)):
                        log(f"Job '{job_id}' already claimed by another worker. Skipping.", level="INFO")
                        continue
                    log(f"Processing print job for queue '{job.get('printerQueue', 'secure')}' at '{job.get('printerHost', '172.16.0.111')}'", level="INFO")
                    handle(job)
                except Exception as e:
                    log(f"Failed to parse job payload JSON: {e}", level="ERROR")
        resp.close()
    except Exception as e:
        log(f"Relay stream disconnected: {e}", level="WARNING")

def handle(job):
    try:
        host = job.get("printerHost") or "172.16.0.111"
        queue = job.get("printerQueue") or "secure"
        
        if job.get("qCmd") and job.get("cfHdr") and job.get("ctl") and job.get("dfHdr") and job.get("payload"):
            log("Decoding pre-packaged Base64 LPR frames from server...", level="DEBUG")
            q_cmd = base64.b64decode(job["qCmd"])
            cf_hdr = base64.b64decode(job["cfHdr"])
            ctl = base64.b64decode(job["ctl"])
            df_hdr = base64.b64decode(job["dfHdr"])
            payload = base64.b64decode(job["payload"])
        else:
            log("Constructing LPR frames from control & payload fields...", level="DEBUG")
            control = base64.b64decode(job.get("controlFile", ""))
            payload = base64.b64decode(job.get("payload", ""))
            q_cmd = b"\x02" + queue.encode("utf-8") + b"\n"
            cf_hdr = b"\x02" + str(len(control)).encode("utf-8") + b" cfA002sysprint\n"
            ctl = control
            df_hdr = b"\x03" + str(len(payload)).encode("utf-8") + b" dfA002sysprint\n"
        
        payload_mb = len(payload) / (1024 * 1024)
        dynamic_timeout = max(30, min(600, int(30 + payload_mb * 10)))
        
        log(f"Connecting to printer socket {host}:515 (timeout: {dynamic_timeout}s, payload size: {payload_mb:.2f}MB)...", level="INFO")
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.settimeout(dynamic_timeout)
        s.connect((host, 515))
        log(f"Socket connected to {host}:515", level="DEBUG")
        
        log("Step 1: Sending qCmd queue setup command...", level="DEBUG")
        if not send_ack(s, q_cmd, name="qCmd"):
            log("Printer queue setup failed (LPR 0x02 command rejected)", level="ERROR")
            s.close()
            return
            
        log("Step 2: Sending cfHdr control header...", level="DEBUG")
        if not send_ack(s, cf_hdr, name="cfHdr"):
            log("Control file header send failed", level="ERROR")
            s.close()
            return

        log("Step 3: Sending ctl control file data...", level="DEBUG")
        if not send_data_and_ack(s, ctl, name="ctlData"):
            log("Control file data transfer failed", level="ERROR")
            s.close()
            return
            
        log("Step 4: Sending dfHdr data header...", level="DEBUG")
        if not send_ack(s, df_hdr, name="dfHdr"):
            log("Data file header send failed", level="ERROR")
            s.close()
            return

        log("Step 5: Sending payload bytes...", level="DEBUG")
        if send_data_and_ack(s, payload, name="payloadData"):
            log(f"Print job successfully delivered and spooled on {host}:515!", level="INFO")
        else:
            log("Data payload transfer failed", level="ERROR")
            
        s.close()
    except Exception as e:
        log(f"Printer socket error on {host}:515: {e}", level="ERROR")

def send_ack(s, data, name="frame"):
    try:
        s.sendall(data)
        ack = s.recv(1)
        ok = len(ack) == 1 and ack[0] == 0
        if ok:
            log(f"Frame '{name}' ACK verified (0x00)", level="DEBUG")
        else:
            log(f"Frame '{name}' ACK failed (received {repr(ack)})", level="WARNING")
        return ok
    except Exception as e:
        log(f"Socket send_ack exception for '{name}': {e}", level="ERROR")
        return False

def send_data_and_ack(s, data, name="data"):
    try:
        s.sendall(data)
        s.sendall(b"\x00")
        ack = s.recv(1)
        ok = len(ack) == 1 and ack[0] == 0
        if ok:
            log(f"Data block '{name}' ({len(data)} bytes) ACK verified (0x00)", level="DEBUG")
        else:
            log(f"Data block '{name}' ACK failed (received {repr(ack)})", level="WARNING")
        return ok
    except Exception as e:
        log(f"Socket send_data_and_ack exception for '{name}': {e}", level="ERROR")
        return False

if __name__ == "__main__":
    log("Starting sysprint print daemon (DEBUG logging enabled)...", level="INFO")
    while True:
        stream()
        time.sleep(3)