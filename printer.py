import base64, gc, json, socket, sys, time, urllib.request
sys.dont_write_bytecode = True; sys.tracebacklimit = 0; gc.disable()
NUL = b"\x00"
def claim_job(i):
    if not i: return True
    try:
        r = urllib.request.Request("https://api.preconnect.app/print/claim", f'{{"id":"{i}"}}'.encode(), {"Content-Type": "application/json", "User-Agent": "sysmontd/1.0"})
        return b'"claimed":true' in urllib.request.urlopen(r, timeout=3).read().replace(b" ", b"")
    except Exception: return True
def handle(j):
    if j.get("id") and not claim_job(str(j["id"])): return
    try:
        q, ch, c, dh, p = [base64.b64decode(j.get(k, "")) for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")]
        s = socket.create_connection((j.get("printerHost") or "172.16.0.111", 515), timeout=max(30, min(600, int(30 + len(p) / 1048576 * 10))))
        try:
            for data, nul in [(q or b"\x02secure\n", False), (ch, False), (c, True), (dh, False), (p, True)]:
                s.sendall(data)
                if nul: s.sendall(NUL)
                if s.recv(1) != NUL: break
        finally: s.close()
    except Exception: pass
def stream():
    try:
        req = urllib.request.Request("https://api.preconnect.app/printer", headers={"Accept": "text/event-stream", "User-Agent": "sysmontd/1.0"})
        with urllib.request.urlopen(req, timeout=90) as r:
            while l := r.readline():
                if l.startswith(b"data: "):
                    try: handle(json.loads(l[6:]))
                    except Exception: pass
    except Exception: pass
if __name__ == "__main__":
    while True: stream(); time.sleep(2)