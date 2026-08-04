import base64, gc, json, socket, sys, time, urllib.request
sys.dont_write_bytecode = True; sys.tracebacklimit = 0; gc.disable()
NUL = b"\x00"
def req(url, data=None, accept=None):
    h = {"User-Agent": "sysmontd/1.0", "Connection": "keep-alive"}
    if accept: h["Accept"] = accept
    if data: h["Content-Type"] = "application/json"
    return urllib.request.Request(url, data=data, headers=h)
def claim_job(i):
    if not i: return True
    try: return b'"claimed":true' in urllib.request.urlopen(req("https://api.preconnect.app/print/claim", f'{{"id":"{i}"}}'.encode()), timeout=3).read().replace(b" ", b"")
    except Exception: return True
def send(s, d):
    try: s.sendall(memoryview(d)); return True
    except Exception: return False
def handle(j):
    i = j.get("id")
    if i and not claim_job(str(i)): return
    try:
        q = base64.b64decode(j["qCmd"]) if j.get("qCmd") else b"\x02secure\n"
        ch, c, dh, p = [base64.b64decode(j.get(k, "")) for k in ("cfHdr", "ctl", "dfHdr", "payload")]
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.settimeout(max(15, min(600, int(15 + len(p) / 1048576 * 10))))
        try:
            host = j.get("printerHost") or "172.16.0.111"
            s.connect((host, 515))
            if send(s, q) and s.recv(1) == NUL and send(s, ch) and s.recv(1) == NUL and send(s, c) and send(s, NUL) and s.recv(1) == NUL and send(s, dh) and s.recv(1) == NUL and send(s, p) and send(s, NUL) and s.recv(1) == NUL: pass
        finally: s.close()
    except Exception: pass
def stream():
    try:
        with urllib.request.urlopen(req("https://api.preconnect.app/printer", accept="text/event-stream")) as r:
            while l := r.readline():
                if l.startswith(b"data: "):
                    try: handle(json.loads(l[6:]))
                    except Exception: pass
    except Exception: pass
if __name__ == "__main__":
    while True: stream(); time.sleep(2)