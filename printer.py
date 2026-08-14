import atexit, ctypes, os, platform, signal, struct, sys, uuid, zlib
from base64 import b64decode, urlsafe_b64encode
from gc import collect, disable
from hashlib import sha256
from hmac import new as hmac_new
from http.client import HTTPSConnection
from json import loads
from socket import IPPROTO_TCP, SO_KEEPALIVE, SO_LINGER, SO_SNDBUF, SOL_SOCKET, TCP_NODELAY, create_connection, socket
from ssl import create_default_context
from threading import Lock, Thread
from time import sleep, time
from typing import Any, Dict, Optional, Tuple, Union
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
disable()

def _sleep_inhibit(on: bool = True) -> None:
    if sys.platform == "win32":
        try: ctypes.windll.kernel32.SetThreadExecutionState(0x80000001 if on else 0x80000000)
        except Exception: pass

def _cleanup() -> None:
    global _k
    _k = ""
    _sleep_inhibit(False)
    collect()

atexit.register(_cleanup)

try:
    signal.signal(signal.SIGINT, lambda s, f: ( _cleanup(), sys.exit(0) ))
    signal.signal(signal.SIGTERM, lambda s, f: ( _cleanup(), sys.exit(0) ))
except Exception: pass

def _load_key() -> str:
    k = os.environ.get("WORKER_KEY", "").strip()
    if not k and len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        k = sys.argv[1].strip()
    if sys.platform == "win32" and k.startswith("DPAPI:"):
        try:
            from ctypes import wintypes
            class BLOB(ctypes.Structure):
                _fields_ = [("cb", wintypes.DWORD), ("pb", ctypes.POINTER(ctypes.c_byte))]
            raw = b64decode(k[6:])
            buf = ctypes.create_string_buffer(raw, len(raw))
            in_b, out_b = BLOB(len(raw), ctypes.cast(buf, ctypes.POINTER(ctypes.c_byte))), BLOB()
            if ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(in_b), None, None, None, None, 0, ctypes.byref(out_b)):
                dec = ctypes.string_at(out_b.pb, out_b.cb).decode("utf-8", "ignore").strip()
                ctypes.windll.kernel32.LocalFree(out_b.pb)
                k = dec
        except Exception: pass
    if not k:
        sys.stderr.write("error: worker key required\n")
        sys.exit(1)
    if len(sys.argv) > 1: sys.argv[1] = " " * len(sys.argv[1])
    return k

_k = _load_key()
_debug = "--debug" in sys.argv

def _log(msg: str, level: str = "OK") -> None:
    if _debug or level in ("ERR", "WARN"):
        sys.stderr.write(f"[{level}] {msg}\n")
        sys.stderr.flush()

_doh_cache: Dict[str, Tuple[str, float]] = {}

def doh_resolve(domain: str) -> str:
    now = time()
    if domain in _doh_cache and now - _doh_cache[domain][1] < 300: return _doh_cache[domain][0]
    try:
        req = Request(f"https://1.1.1.1/dns-query?name={domain}&type=A", headers={"Accept": "application/dns-json"})
        with urlopen(req, timeout=2.0) as resp:
            if resp.status == 200:
                for a in loads(resp.read().decode()).get("Answer", []):
                    if a.get("type") == 1:
                        ip = str(a.get("data"))
                        _doh_cache[domain] = (ip, now)
                        return ip
    except Exception: pass
    return domain

_DOM = b64decode("YXBpLnByZWNvbm5lY3QuYXBw").decode()

def _http_req(path: str, headers: Optional[Dict[str, str]] = None, data: Optional[bytes] = None, timeout: Optional[float] = None) -> Any:
    ip = doh_resolve(_DOM)
    hdrs_dict = dict(headers or {})
    hdrs_dict["Host"] = _DOM
    if ip and ip != _DOM:
        try:
            conn = HTTPSConnection(ip, 443, timeout=timeout or 300.0, context=create_default_context())
            conn.host = _DOM
            conn.request("POST" if data is not None else "GET", path, body=data, headers=hdrs_dict)
            return conn.getresponse()
        except Exception: pass
    req = Request(f"https://{_DOM}{path}", headers=hdrs_dict, data=data)
    return urlopen(req, timeout=timeout, context=create_default_context()) if timeout else urlopen(req, context=create_default_context())

NUL = b"\x00"
jobs = 0
_claims = 0
_claims_lock = Lock()
_worker_busy = Lock()

def _d(s: str, job_id: Union[str, int] = "") -> bytes:
    if not s: return b""
    raw = b64decode(s)
    if len(raw) < 16: return b""
    iv, enc = raw[:16], raw[16:]
    p = sha256(_k.encode() + iv + str(job_id).encode()).digest()
    out = bytearray(len(enc))
    for idx, i in enumerate(range(0, len(enc), 32)):
        c = enc[i : i + 32]
        ks = sha256(p + idx.to_bytes(4, "big")).digest()
        out[i : i + len(c)] = (int.from_bytes(c, "big") ^ int.from_bytes(ks[:len(c)], "big")).to_bytes(len(c), "big")
    res = bytes(out)
    if res.startswith((b"\x78\x9c", b"\x78\x01", b"\x78\xda")):
        try: return zlib.decompress(res)
        except Exception: pass
    return res

_online: Dict[str, Tuple[bool, float]] = {}
_online_lock = Lock()

def is_online(host: str) -> bool:
    if not host: return False
    now = time()
    with _online_lock:
        if host in _online and now - _online[host][1] < 3.0:
            return _online[host][0]
    try:
        s = create_connection((host, 515), timeout=0.5)
        try: s.shutdown(2)
        except Exception: pass
        s.close()
        with _online_lock: _online[host] = (True, now)
        return True
    except Exception:
        with _online_lock: _online[host] = (False, now)
        return False

def _probe_loop() -> None:
    while True:
        with _online_lock:
            hosts = list(_online.keys())
        for h in hosts:
            is_online(h)
        sleep(1.5)

def _ident() -> str:
    path = "C:\\ProgramData\\.ident" if sys.platform == "win32" else "/tmp/.ident"
    try:
        if os.path.exists(path):
            with open(path, "r") as f:
                v = f.read().strip()
                if v: return v
        val = f"{uuid.uuid4()};{platform.machine().lower()}"
        with open(path, "w") as f: f.write(val)
        return val
    except Exception:
        return f"{uuid.uuid4()};{platform.machine().lower()}"

_WORKER_IDENT = _ident()
_UA = b64decode("c3lzbW9udGQ=").decode() + "/1.0"

def _make_jwt() -> str:
    def b64u(b: bytes) -> str: return urlsafe_b64encode(b).rstrip(b"=").decode()
    h, p = b64u(b'{"alg":"HS256","typ":"JWT"}'), b64u(b'{"sub":"printer","iss":"preconnect"}')
    sig = b64u(hmac_new(_k.encode(), f"{h}.{p}".encode(), sha256).digest())
    return f"{h}.{p}.{sig}"

_cached_jwt = _make_jwt()

def hdrs() -> Dict[str, str]:
    return {
        "User-Agent": _UA,
        "Authorization": f"Bearer {_cached_jwt}",
        "X-Worker-Key": _k,
        "X-Worker-Jobs": str(jobs),
        "X-Worker-Ident": _WORKER_IDENT,
    }

def claim(i: Union[str, int]) -> bool:
    global _claims
    if not i: return True
    with _claims_lock:
        if _claims >= 3:
            sleep(1.0)
            _claims = 0
    for _ in range(3):
        try:
            with _http_req("/print/claim", headers={"Content-Type": "application/json", **hdrs()}, data=f'{{"id":"{i}"}}'.encode(), timeout=5.0) as resp:
                if resp.status == 200:
                    ok = bool(loads(resp.read().decode()).get("claimed"))
                    if ok:
                        with _claims_lock: _claims += 1
                    return ok
                return False
        except Exception: sleep(0.15)
    return False

def handle(j: Dict[str, Any]) -> None:
    global jobs
    if not _worker_busy.acquire(blocking=False): return
    _sleep_inhibit(True)
    host = j.get("printerHost") or "172.16.0.111"
    queue = j.get("printerQueue") or "secure"
    job_id = str(j.get("id", ""))
    if not host or not is_online(host) or (job_id and not claim(job_id)):
        _sleep_inhibit(False)
        _worker_busy.release()
        return
    s: Optional[socket] = None
    try:
        q, ch, c, dh, p = [_d(j.get(k, ""), job_id) for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")]
        if not p:
            _sleep_inhibit(False)
            _worker_busy.release()
            return
        _log(f"Handling job for {host}:{queue} ({len(p)} bytes)")
        s = create_connection((host, 515), timeout=float(j.get("timeout", 60) or 60))
        s.setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
        s.setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1)
        s.setsockopt(SOL_SOCKET, SO_SNDBUF, 65536)
        for data, add_nul in [(q, False), (ch, False), (c, True), (dh, False)]:
            s.sendall(data + (NUL if add_nul else b""))
            if s.recv(1) != NUL:
                _sleep_inhibit(False)
                _worker_busy.release()
                return
        mv = memoryview(p)
        for i in range(0, len(p), 65536): s.sendall(mv[i : i + 65536])
        s.sendall(NUL)
        if s.recv(1) != NUL:
            _sleep_inhibit(False)
            _worker_busy.release()
            return
        jobs += 1
        _log("Job transferred successfully")
    except Exception as e:
        _log(f"Transfer error: {e}", "ERR")
        if s:
            try: s.setsockopt(SOL_SOCKET, SO_LINGER, struct.pack("ii", 1, 0))
            except Exception: pass
    finally:
        if s:
            try: s.shutdown(2)
            except Exception: pass
            try: s.close()
            except Exception: pass
        _sleep_inhibit(False)
        _worker_busy.release()

_last_id = ""

def stream() -> None:
    global _last_id
    try:
        h = {"Accept": "text/event-stream", **hdrs()}
        if _last_id: h["Last-Event-ID"] = _last_id
        with _http_req("/printer", headers=h, timeout=None) as r:
            if r.status == 401:
                sys.stderr.write("error: worker key invalid (401)\n")
                _cleanup()
                sys.exit(1)
            if r.status != 200: return
            while line := r.readline():
                if line.startswith(b":") or not line.strip(): continue
                if line.startswith(b"id: "): _last_id = line[4:].strip().decode("utf-8", "ignore")
                elif line.startswith(b"data: "):
                    try: Thread(target=handle, args=(loads(line[6:].decode("utf-8", "replace")),), daemon=True).start()
                    except Exception: pass
    except Exception: pass

def _ping() -> None:
    while True:
        try: _http_req("/print/ping", headers={"Content-Type": "application/json", **hdrs()}, data=b"{}", timeout=5.0)
        except Exception: pass
        sleep(5.0)

if __name__ == "__main__":
    is_online("172.16.0.111")
    sleep(0.2)
    Thread(target=_probe_loop, daemon=True).start()
    Thread(target=_ping, daemon=True).start()
    delay = 1.0
    while True:
        _log(f"Stream connect; Jobs: {jobs}")
        t0 = time()
        stream()
        delay = 1.0 if (time() - t0) > 10.0 else min(delay * 2.0, 8.0)
        sleep(delay)
