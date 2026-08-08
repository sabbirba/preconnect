import signal
import sys
from base64 import b64decode
from gc import collect, disable
from hashlib import sha256
from json import loads
from os import _exit, devnull, environ
from socket import (
    IPPROTO_TCP,
    SO_SNDBUF,
    SOL_SOCKET,
    TCP_NODELAY,
    create_connection,
)
from ssl import _create_unverified_context, create_default_context
from threading import Thread
from time import sleep, time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
disable()


def _on_signal(sig, frame):
    _exit(0)


try:
    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)
except Exception:  # noqa: BLE001, S110
    pass


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
sys.stdout = sys.stderr = open(devnull, "w")  # noqa: SIM115

_doh_cache = {}


def doh_resolve(domain):
    now = time()
    if domain in _doh_cache and now - _doh_cache[domain][1] < 30:
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
        except Exception:  # noqa: BLE001, S110
            pass
    return domain


_DOM = b64decode("YXBpLnByZWNvbm5lY3QuYXBw").decode()


def _make_doh_request(path, headers=None, data=None, timeout=None):
    ip = doh_resolve(_DOM)
    target = ip if (ip and ip != _DOM) else _DOM
    url = f"https://{target}{path}"
    req = Request(url, headers=headers or {}, data=data)
    req.add_header("Host", _DOM)
    ctx = _create_unverified_context() if target == ip else create_default_context()
    return urlopen(req, timeout=timeout, context=ctx)


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


_online_cache = {}


def is_online(host, port=515):
    if not host:
        return False
    now = time()
    if host in _online_cache and now - _online_cache[host][1] < 2.0:
        return _online_cache[host][0]
    try:
        s = create_connection((host, port), timeout=1.0)
        try:
            s.shutdown(2)
        except Exception:  # noqa: BLE001, S110
            pass
        s.close()
        _online_cache[host] = (True, now)
        return True
    except Exception:  # noqa: BLE001
        _online_cache[host] = (False, now)
        return False


_UA = b64decode("c3lzbW9udGQ=").decode() + "/1.0"


def hdrs(printer_host=None):
    sp = "1" if (printer_host and is_online(printer_host)) else "0"
    return {
        "User-Agent": _UA,
        "X-Worker-Key": _k,
        "X-Worker-Spooler": sp,
        "X-Worker-Jobs": str(jobs),
    }


def claim(i, printer_host=None, retries=3):
    if not i:
        return True
    for attempt in range(retries):
        try:
            data = f'{{"id":"{i}"}}'.encode()
            headers = {"Content-Type": "application/json", **hdrs(printer_host)}
            with _make_doh_request("/print/claim", headers=headers, data=data, timeout=None) as resp:
                if resp.status == 200:
                    return b'"claimed":true' in resp.read()
                return False
        except Exception:  # noqa: BLE001
            if attempt < retries - 1:
                sleep(0.5)
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
                s.sendall(c + NUL)
                ok = _ack(s)
                if ok:
                    s.sendall(dh)
                    ok = _ack(s)
                    if ok:
                        mv = memoryview(p)
                        for i in range(0, len(p), 65536):
                            s.sendall(mv[i : i + 65536])
                        s.sendall(NUL)
                        ok = _ack(s)
                        if ok:
                            jobs += 1
    except Exception:  # noqa: BLE001, S110
        pass
    finally:
        if s:
            try:
                s.shutdown(2)
            except Exception:  # noqa: BLE001, S110
                pass
            try:
                s.close()
            except Exception:  # noqa: BLE001, S110
                pass
        try:
            del q, ch, c, dh, p
        except Exception:  # noqa: BLE001, S110
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

        with _make_doh_request(path, headers=headers, timeout=None) as r:
            if r.status != 200:
                return
            while l := r.readline():
                if l.startswith(b"id: "):
                    last_event_id = l[4:].strip().decode("utf-8", "ignore")
                elif l.startswith(b"data: "):
                    try:
                        payload = loads(l[6:].decode("utf-8", "replace"))
                        Thread(target=handle, args=(payload,), daemon=True).start()
                    except Exception:  # noqa: BLE001, S110
                        pass
    except HTTPError as e:
        if e.code == 401 and sys.__stderr__ is not None:
            sys.__stderr__.write(f"error: worker key invalid ({e.code})\n")
    except Exception:  # noqa: BLE001, S110
        pass


if __name__ == "__main__":
    delay = 1.0
    while True:
        t0 = time()
        try:
            stream()
            delay = 1.0 if (time() - t0 > 10) else min(delay * 2, 8)
        except Exception:  # noqa: BLE001
            delay = min(delay * 2, 8)
        sleep(delay)
