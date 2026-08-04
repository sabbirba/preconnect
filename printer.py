import base64
import json
import socket
import sys
import time
import urllib.request

def log(msg):
    sys.stderr.write(f"[sysprint] {msg}\n")
    sys.stderr.flush()

def claim_job(job_id):
    if not job_id:
        return True
    try:
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
            log(f"Claimed print job {job_id}")
        return claimed
    except Exception as e:
        log(f"Failed to claim job {job_id}: {e}")
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
        resp = urllib.request.urlopen(req)
        log("Connected to relay stream https://api.preconnect.app/printer")
        while True:
            line = resp.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="ignore").strip()
            if text.startswith("data: "):
                try:
                    job = json.loads(text[6:])
                    job_id = job.get("id")
                    if job_id and not claim_job(str(job_id)):
                        log(f"Job {job_id} already claimed by another worker. Skipping.")
                        continue
                    log(f"Received print job for queue '{job.get('printerQueue', 'secure')}' at '{job.get('printerHost', '172.16.0.111')}'")
                    handle(job)
                except Exception as e:
                    log(f"Failed to parse job payload: {e}")
        resp.close()
    except Exception as e:
        log(f"Relay stream disconnected: {e}")

def handle(job):
    try:
        host = job.get("printerHost") or "172.16.0.111"
        queue = job.get("printerQueue") or "secure"
        
        if job.get("qCmd") and job.get("cfHdr") and job.get("ctl") and job.get("dfHdr") and job.get("payload"):
            q_cmd = base64.b64decode(job["qCmd"])
            cf_hdr = base64.b64decode(job["cfHdr"])
            ctl = base64.b64decode(job["ctl"])
            df_hdr = base64.b64decode(job["dfHdr"])
            payload = base64.b64decode(job["payload"])
        else:
            control = base64.b64decode(job.get("controlFile", ""))
            payload = base64.b64decode(job.get("payload", ""))
            q_cmd = b"\x02" + queue.encode("utf-8") + b"\n"
            cf_hdr = b"\x02" + str(len(control)).encode("utf-8") + b" cfA002sysprint\n"
            ctl = control
            df_hdr = b"\x03" + str(len(payload)).encode("utf-8") + b" dfA002sysprint\n"
        
        payload_mb = len(payload) / (1024 * 1024)
        dynamic_timeout = max(30, min(600, int(30 + payload_mb * 10)))
        
        log(f"Connecting to printer {host}:515 (timeout: {dynamic_timeout}s, payload: {payload_mb:.2f}MB)...")
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.settimeout(dynamic_timeout)
        s.connect((host, 515))
        
        if not send_ack(s, q_cmd):
            log("Printer queue setup failed (LPR 0x02 command rejected)")
            s.close()
            return
            
        if not send_ack(s, cf_hdr) or not send_data_and_ack(s, ctl):
            log("Control file transfer failed")
            s.close()
            return
            
        if send_ack(s, df_hdr) and send_data_and_ack(s, payload):
            log("Print job delivered successfully to printer!")
        else:
            log("Data payload transfer failed")
            
        s.close()
    except Exception as e:
        log(f"Printer connection error: {e}")

def send_ack(s, data):
    try:
        s.sendall(data)
        ack = s.recv(1)
        return len(ack) == 1 and ack[0] == 0
    except Exception:
        return False

def send_data_and_ack(s, data):
    try:
        s.sendall(data)
        s.sendall(b"\x00")
        ack = s.recv(1)
        return len(ack) == 1 and ack[0] == 0
    except Exception:
        return False

if __name__ == "__main__":
    log("Starting sysprint print daemon...")
    while True:
        stream()
        time.sleep(3)