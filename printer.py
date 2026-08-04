import base64, json, socket, sys, time, urllib.request

def log(msg):
    sys.stderr.write(f"[sysprint] {msg}\n")
    sys.stderr.flush()

def stream():
    req = urllib.request.Request(
        "https://api.preconnect.app/printer",
        headers={"Accept": "text/event-stream", "User-Agent": "sysprint/1.0"}
    )
    try:
        log("Connecting to https://api.preconnect.app/printer...")
        with urllib.request.urlopen(req, timeout=90) as resp:
            log("Connected. Waiting for print jobs...")
            while line := resp.readline():
                text = line.decode("utf-8", errors="ignore").strip()
                if text.startswith("data: "):
                    try:
                        job = json.loads(text[6:])
                        log(f"Received print job (id: {job.get('id')})")
                        handle(job)
                    except Exception as e:
                        log(f"Parse error: {e}")
    except Exception as e:
        log(f"Stream error: {e}")

def handle(job):
    try:
        control = base64.b64decode(job.get("controlFile", "") or job.get("ctl", ""))
        payload = base64.b64decode(job.get("payload", ""))
        host = job.get("printerHost") or "172.16.0.111"
        queue = job.get("printerQueue") or "secure"
        
        log(f"Connecting to printer {host}:515...")
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        s.settimeout(max(30, min(600, int(30 + len(payload) / 1048576 * 10))))
        s.connect((host, 515))
        log(f"Connected to {host}:515. Sending queue setup...")
        
        q_cmd = b"\x02" + queue.encode("utf-8") + b"\n"
        if not send_ack(s, q_cmd):
            log("Queue setup rejected")
            s.close(); return
        
        cf_hdr = b"\x02" + str(len(control)).encode("utf-8") + b" cfA002sysprint\n"
        if not send_ack(s, cf_hdr) or not send_data_and_ack(s, control):
            log("Control file transfer failed")
            s.close(); return
            
        df_hdr = b"\x03" + str(len(payload)).encode("utf-8") + b" dfA002sysprint\n"
        if send_ack(s, df_hdr) and send_data_and_ack(s, payload):
            log("Print job completed successfully!")
        else:
            log("Payload transfer failed")
        s.close()
    except Exception as e:
        log(f"Printer socket error: {e}")

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
    log("Starting daemon...")
    while True:
        stream()
        time.sleep(3)