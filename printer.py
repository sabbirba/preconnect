import sys
from base64 import b64decode
from gc import collect, disable
from hashlib import sha256
from json import loads
from os import _exit, devnull, environ
from socket import (
    IPPROTO_TCP,
    SO_LINGER,
    SO_SNDBUF,
    SOL_SOCKET,
    TCP_NODELAY,
    create_connection,
    getaddrinfo,
)
from struct import pack
from time import sleep, time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
disable()


def _load_key():
    k = (sys.argv[1].strip() if len(sys.argv) > 1 else "") or environ.get(
        "WORKER_KEY", ""
    ).strip()
    if not k:
        if sys.__stderr__ is not None:
            sys.__stderr__.write("error: worker key required\n")
        _exit(1)
    if len(sys.argv) > 1:
        sys.argv[1] = " " * len(k)
    return k


_k = _load_key()
sys.stdout = sys.stderr = open(devnull, "w")

_doh_cache = {}


def doh_resolve(domain):
    now = time()
    if domain in _doh_cache and now - _doh_cache[domain][1] < 300:
        return _doh_cache[domain][0]
    for resolver in ("https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"):
        try:
            req = Request(
                f"{resolver}?name={domain}&type=A",
                headers={"Accept": "application/dns-json"},
            )
            with urlopen(req, timeout=1.5) as r:
                if r.status == 200:
                    data = loads(r.read().decode())
                    for ans in data.get("Answer", []):
                        if ans.get("type") == 1:
                            ip = ans.get("data")
                            _doh_cache[domain] = (ip, now)
                            return ip
        except Exception:
            pass
    return domain


_orig_getaddrinfo = getaddrinfo


def _doh_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    if host == "api.preconnect.app":
        ip = doh_resolve(host)
        if ip and ip != host:
            return _orig_getaddrinfo(ip, port, family, type, proto, flags)
    return _orig_getaddrinfo(host, port, family, type, proto, flags)


getaddrinfo = _doh_getaddrinfo

NUL = b"\x00"
jobs = 0


def _d(s, job_id=""):
    if not s:
        return b""
    raw = b64decode(s)
    if len(raw) < 16:
        return b""
    iv, enc = raw[:16], raw[16:]
    p = sha256(_k.encode() + iv + str(job_id).encode()).digest()
    out = bytearray(len(enc))
    for idx, i in enumerate(range(0, len(enc), 32)):
        chunk = enc[i : i + 32]
        ks = sha256(p + idx.to_bytes(4, "big")).digest()
        for j, b in enumerate(chunk):
            out[i + j] = b ^ ks[j]
    return bytes(out)


def is_online(host, port=515):
    if not host:
        return False
    try:
        s = create_connection((host, port), timeout=0.8)
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
        r = Request(
            "https://api.preconnect.app/print/claim", data=data, headers=headers
        )
        with urlopen(r, timeout=2) as resp:
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
            _d(j.get(k, ""), job_id)
            for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")
        ]
        s = create_connection((host, 515), timeout=j.get("timeout", 60))
        s.setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
        s.setsockopt(SOL_SOCKET, SO_SNDBUF, 65536)
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
                s.setsockopt(SOL_SOCKET, SO_LINGER, pack("HH", 1, 0))
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
        collect()


def stream():
    try:
        req = Request(
            "https://api.preconnect.app/printer",
            headers={
                "Accept": "text/event-stream",
                "Connection": "keep-alive",
                **hdrs(),
            },
        )
        with urlopen(req, timeout=90) as r:
            if r.status != 200:
                return
            while l := r.readline():
                if l.startswith(b"data: "):
                    try:
                        handle(loads(l[6:]))
                    except Exception:
                        pass
    except HTTPError as e:
        if e.code == 401 and sys.__stderr__ is not None:
            sys.__stderr__.write(f"error: worker key invalid ({e.code})\n")
    except Exception:
        pass


if __name__ == "__main__":
    delay = 1.0
    while True:
        t0 = time()
        try:
            stream()
            delay = 1.0 if (time() - t0 > 10) else min(delay * 2, 8)
        except Exception:
            delay = min(delay * 2, 8)
        sleep(delay)
