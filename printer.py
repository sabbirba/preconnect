import base64
import json
import socket
import time
import urllib.request

def claim_job(job_id):
    if not job_id:
        return True
    try:
        req = urllib.request.Request(
            "https://api.preconnect.app/print/claim",
            data=json.dumps({"id": str(job_id)}).encode("utf-8"),
            headers={"Content-Type": "application/json", "User-Agent": "sysprint/1.0"}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            return res.get("claimed", False)
    except Exception:
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
        while True:
            line = resp.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="ignore").strip()
            if text.startswith("data: "):
                try:
                    job = json.loads(text[6:])
                    handle(job)
                except Exception:
                    pass
        resp.close()
    except Exception:
        pass

def handle(job):
    job_id = job.get("id")
    if job_id and not claim_job(job_id):
        return
    try:
        control = base64.b64decode(job.get("controlFile", ""))
        payload = base64.b64decode(job.get("payload", ""))
        host = job.get("printerHost", "172.16.0.111")
        queue = job.get("printerQueue", "secure")
        
        payload_mb = len(payload) / (1024 * 1024)
        dynamic_timeout = max(30, min(600, int(30 + payload_mb * 10)))
        
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(dynamic_timeout)
        s.connect((host, 515))
        
        if not send_ack(s, b"\x02" + queue.encode("utf-8") + b"\n"):
            s.close()
            return
            
        cf_hdr = b"\x02" + str(len(control)).encode("utf-8") + b" cfA002sysprint\n"
        if not send_ack(s, cf_hdr) or not send_data_and_ack(s, control):
            s.close()
            return
            
        df_hdr = b"\x03" + str(len(payload)).encode("utf-8") + b" dfA002sysprint\n"
        if send_ack(s, df_hdr):
            send_data_and_ack(s, payload)
            
        s.close()
    except Exception:
        pass

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
    while True:
        stream()
        time.sleep(3)
