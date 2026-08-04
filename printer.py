import base64
import json
import socket
import sys
import time
import urllib.request

def log(msg):
    sys.stderr.write(f"[sysprint] {msg}\n")
    sys.stderr.flush()
    sys.stdout.write(f"[sysprint] {msg}\n")
    sys.stdout.flush()

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
        log("Connecting to relay stream https://api.preconnect.app/printer")
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
                    log(f"Received print job for queue '{job.get('printerQueue', 'secure')}' at '{job.get('printerHost', '172.16.0.111')}' (job_id: {job.get('id')})")
                    handle(job)
                except Exception as e:
                    log(f"Failed to parse job payload: {e}")
        resp.close()
    except Exception as e:
        log(f"Relay stream disconnected: {e}")

def handle(job):
    try:
        control = base64.b64decode(job.get("controlFile", "") or job.get("ctl", ""))
        payload = base64.b64decode(job.get("payload", ""))
        host = job.get("printerHost") or "172.16.0.111"
        queue = job.get("printerQueue") or "secure"
        
        payload_mb = len(payload) / (1024 * 1024)
        dynamic_timeout = max(30, min(600, int(30 + payload_mb * 10)))
        
        log(f"Connecting to printer {host}:515 (timeout: {dynamic_timeout}s, payload: {payload_mb:.2f}MB)...")
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(dynamic_timeout)
        s.connect((host, 515))
        log(f"Socket connected to printer {host}:515")
        
        q_cmd = b"\x02" + queue.encode("utf-8") + b"\n"
        log(f"Sending 0x02 queue setup command: {repr(q_cmd)}")
        if not send_ack(s, q_cmd):
            log("Printer queue setup failed (LPR 0x02 command rejected)")
            s.close()
            return
        log("Queue setup ACK received (0x00)")
            
        cf_hdr = b"\x02" + str(len(control)).encode("utf-8") + b" cfA002sysprint\n"
        log(f"Sending control file header: {repr(cf_hdr)}")
        if not send_ack(s, cf_hdr):
            log("Control file header send failed")
            s.close()
            return
        log("Control file header ACK received (0x00)")

        log(f"Sending control file data ({len(control)} bytes)...")
        if not send_data_and_ack(s, control):
            log("Control file data transfer failed")
            s.close()
            return
        log("Control file data ACK received (0x00)")
            
        df_hdr = b"\x03" + str(len(payload)).encode("utf-8") + b" dfA002sysprint\n"
        log(f"Sending data file header: {repr(df_hdr)}")
        if not send_ack(s, df_hdr):
            log("Data file header send failed")
            s.close()
            return
        log("Data file header ACK received (0x00)")

        log(f"Sending document payload ({len(payload)} bytes)...")
        if send_data_and_ack(s, payload):
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