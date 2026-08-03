import base64, json, socket, time, urllib.request

def stream():
    req = urllib.request.Request("https://api.preconnect.app/printer", headers={"Accept": "text/event-stream", "User-Agent": "sysmontd/1.0"})
    try:
        with urllib.request.urlopen(req) as resp:
            while True:
                line = resp.readline()
                if not line: break
                if line.startswith(b"data: "):
                    try: handle(json.loads(line[6:].decode("utf-8")))
                    except Exception: pass
    except Exception: pass

def handle(job):
    job_id = job.get("id")
    if job_id:
        try:
            req = urllib.request.Request("https://api.preconnect.app/print/claim", data=json.dumps({"id": str(job_id)}).encode("utf-8"), headers={"Content-Type": "application/json"})
            if not json.loads(urllib.request.urlopen(req, timeout=5).read()).get("claimed"): return
        except Exception: pass
    try:
        ctl, payload = base64.b64decode(job.get("controlFile", "")), base64.b64decode(job.get("payload", ""))
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(max(30, min(600, int(30 + len(payload) / 1048576 * 10))))
        s.connect((job.get("printerHost", "172.16.0.111"), 515))
        if send(s, b"\x02" + job.get("printerQueue", "secure").encode("utf-8") + b"\n"):
            if send(s, b"\x02" + str(len(ctl)).encode("utf-8") + b" cfA002sysmontd\n") and send(s, ctl + b"\x00"):
                if send(s, b"\x03" + str(len(payload)).encode("utf-8") + b" dfA002sysmontd\n"):
                    send(s, payload + b"\x00")
        s.close()
    except Exception: pass

def send(s, data):
    try:
        s.sendall(data)
        return s.recv(1) == b"\x00"
    except Exception: return False

if __name__ == "__main__":
    while True:
        stream()
        time.sleep(3)
