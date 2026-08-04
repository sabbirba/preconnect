import base64, gc, json, logging, signal, socket, sys, time, urllib.request

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] [sysmontd] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
sys.dont_write_bytecode = True; sys.tracebacklimit = 0; gc.disable()

try:
    signal.signal(signal.SIGINT, lambda *_: (logging.info("Daemon stopping..."), sys.exit(0)))
    signal.signal(signal.SIGTERM, lambda *_: (logging.info("Daemon stopping..."), sys.exit(0)))
except Exception: pass

NUL = b"\x00"

def req(url, data=None, accept=None):
    h = {"User-Agent": "sysmontd/1.0", "Connection": "keep-alive"}
    if accept: h["Accept"] = accept
    if data: h["Content-Type"] = "application/json"
    return urllib.request.Request(url, data=data, headers=h)

def claim_job(i):
    if not i: return True
    try:
        r = urllib.request.urlopen(req("https://api.preconnect.app/print/claim", f'{{"id":"{i}"}}'.encode()), timeout=3).read().replace(b" ", b"")
        claimed = b'"claimed":true' in r
        if claimed: logging.info(f"Claimed print job {i}")
        return claimed
    except Exception as e:
        logging.warning(f"Failed to claim job {i}: {e}")
        return True

def send(s, d):
    try: s.sendall(memoryview(d)); return True
    except Exception: return False

def handle(j):
    i = j.get("id", "unknown")
    logging.info(f"Received job {i} from server stream")
    if i != "unknown" and not claim_job(str(i)):
        logging.info(f"Job {i} already claimed by another worker. Skipping.")
        return
    try:
        q = base64.b64decode(j["qCmd"]) if j.get("qCmd") else b"\x02secure\n"
        ch, c, dh, p = [base64.b64decode(j.get(k, "")) for k in ("cfHdr", "ctl", "dfHdr", "payload")]
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.settimeout(max(15, min(600, int(15 + len(p) / 1048576 * 10))))
        host = j.get("printerHost") or "172.16.0.111"
        logging.info(f"Connecting to printer at {host}:515 for job {i} ({len(p)} bytes)...")
        try:
            s.connect((host, 515))
            ok = (send(s, q) and s.recv(1) == NUL and
                  send(s, ch) and s.recv(1) == NUL and
                  send(s, c) and send(s, NUL) and s.recv(1) == NUL and
                  send(s, dh) and s.recv(1) == NUL and
                  send(s, p) and send(s, NUL) and s.recv(1) == NUL)
            if ok:
                logging.info(f"Job {i} successfully printed on {host}:515")
            else:
                logging.error(f"Printer socket ACK failed for job {i}")
        finally: s.close()
    except Exception as e:
        logging.error(f"Error executing print job {i}: {e}")

def stream():
    logging.info("Connecting to SSE event stream at https://api.preconnect.app/printer...")
    try:
        with urllib.request.urlopen(req("https://api.preconnect.app/printer", accept="text/event-stream")) as r:
            logging.info("SSE event stream connected. Listening for print jobs...")
            while l := r.readline():
                if l.startswith(b"data: "):
                    try: handle(json.loads(l[6:]))
                    except Exception as e:
                        logging.error(f"Failed to parse job JSON: {e}")
    except Exception as e:
        logging.warning(f"SSE stream disconnected ({e}). Retrying in 2s...")

if __name__ == "__main__":
    logging.info("Starting sysmontd printer daemon v1.0...")
    while True:
        stream()
        time.sleep(2)