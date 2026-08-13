import atexit, ctypes, platform, signal, struct, sys, uuid, zlib
from base64 import b64decode, urlsafe_b64encode
from gc import collect, disable
from hashlib import sha256
from hmac import new as hmac_new
from http.client import HTTPSConnection
from json import loads
from os import _exit, environ, urandom
from socket import IPPROTO_TCP, SO_KEEPALIVE, SO_LINGER, SO_SNDBUF, SOL_SOCKET, TCP_NODELAY, create_connection
from ssl import create_default_context
from threading import Lock, Thread
from time import sleep, time
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
disable()
try: sys.setswitchinterval(1.0)
except Exception: pass

def _trim_working_set():
    if sys.platform == "win32":
        try: ctypes.windll.kernel32.SetProcessWorkingSetSize(-1, -1)
        except Exception: pass

def _cleanup():
    global _k
    _k = ""
    collect()
    _trim_working_set()

atexit.register(_cleanup)

def _on_signal(sig, frame):
    _cleanup()
    _exit(0)

try:
    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)
except Exception: pass

def _load_key():
    k = (sys.argv[1].strip() if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "")
    if sys.platform == "win32" and k.startswith("DPAPI:"):
        try:
            from ctypes import wintypes
            class DATA_BLOB(ctypes.Structure):
                _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_byte))]
            raw = b64decode(k[6:])
            buf = ctypes.create_string_buffer(raw, len(raw))
            in_blob = DATA_BLOB(len(raw), ctypes.cast(buf, ctypes.POINTER(ctypes.c_byte)))
            out_blob = DATA_BLOB()
            if ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(in_blob), None, None, None, None, 0, ctypes.byref(out_blob)):
                dec_buf = ctypes.string_at(out_blob.pbData, out_blob.cbData)
                ctypes.windll.kernel32.LocalFree(out_blob.pbData)
                k = dec_buf.decode("utf-8", "ignore").strip()
        except Exception: pass
    if not k:
        if sys.__stderr__ is not None: sys.__stderr__.write("error: worker key required\n")
        _exit(1)
    if len(sys.argv) > 1: sys.argv[1] = " " * len(sys.argv[1])
    return k


_k = _load_key()
_orig_stderr = sys.__stderr__ or sys.stderr
_is_debug = "--debug" in sys.argv

def _log(msg, level="OK"):
    if not _is_debug and level == "OK": return
    try:
        tag = "ERR" if level == "ERR" else ("WARN" if level == "WARN" else "OK")
        out = _orig_stderr if _orig_stderr is not None else sys.stderr
        out.write(f"[{tag}] {msg}\n")
        out.flush()
    except Exception: pass

_doh_cache = {}

def doh_resolve(domain):
    now = time()
    if domain in _doh_cache and now - _doh_cache[domain][1] < 300: return _doh_cache[domain][0]
    for resolver in ("https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"):
        try:
            req = Request(f"{resolver}?name={domain}&type=A", headers={"Accept": "application/dns-json"})
            with urlopen(req, timeout=2.0) as r:
                if r.status == 200:
                    for ans in loads(r.read().decode()).get("Answer", []):
                        if ans.get("type") == 1:
                            ip = ans.get("data")
                            _doh_cache[domain] = (ip, now)
                            return ip
        except Exception: pass
    return domain

def _dns_prewarmer():
    while True:
        try: doh_resolve(_DOM)
        except Exception: pass
        sleep(180.0)

_DOM = b64decode("YXBpLnByZWNvbm5lY3QuYXBw").decode()
_conn_pool, _conn_lock = {}, Lock()

def _get_pooled_conn(ip, timeout=300.0):
    with _conn_lock:
        conn = _conn_pool.get(ip)
        if conn is not None:
            try:
                if not getattr(conn, "_closed", False): return conn
            except Exception: pass
        conn = HTTPSConnection(ip, 443, timeout=timeout, context=create_default_context())
        conn.host = _DOM
        _conn_pool[ip] = conn
        return conn

def _make_doh_request(path, headers=None, data=None, timeout=None):
    ip = doh_resolve(_DOM)
    headers = dict(headers or {})
    headers["Host"] = _DOM
    sock_timeout = timeout if timeout is not None else 300.0
    if ip and ip != _DOM:
        for attempt in range(2):
            try:
                conn = _get_pooled_conn(ip, sock_timeout)
                conn.request("POST" if data is not None else "GET", path, body=data, headers=headers)
                res = conn.getresponse()
                if timeout is None:
                    try:
                        sock = getattr(getattr(res, "fp", None), "_sock", None)
                        if sock and hasattr(sock, "settimeout"): sock.settimeout(None)
                    except Exception: pass
                return res
            except Exception:
                with _conn_lock: _conn_pool.pop(ip, None)
    req = Request(f"https://{_DOM}{path}", headers=headers, data=data)
    ctx = create_default_context()
    return urlopen(req, timeout=timeout, context=ctx) if timeout is not None else urlopen(req, context=ctx)

NUL, jobs = b"\x00", 0

def _d(s, job_id=""):
    if not s: return b""
    raw = b64decode(s)
    if len(raw) < 16: return b""
    iv, enc = raw[:16], raw[16:]
    p = sha256(_k.encode() + iv + str(job_id).encode()).digest()
    out = bytearray(len(enc))
    for idx, i in enumerate(range(0, len(enc), 32)):
        chunk = enc[i : i + 32]
        ks = sha256(p + idx.to_bytes(4, "big")).digest()
        out[i : i + len(chunk)] = (int.from_bytes(chunk, "big") ^ int.from_bytes(ks[:len(chunk)], "big")).to_bytes(len(chunk), "big")
    res = bytes(out)
    if res.startswith(b"\x78\x9c") or res.startswith(b"\x78\x01") or res.startswith(b"\x78\xda"):
        try: return zlib.decompress(res)
        except Exception: pass
    return res

_online_cache = {}

def is_online(host, port=515):
    if not host: return False
    now = time()
    if host in _online_cache and now - _online_cache[host][1] < 2.0: return _online_cache[host][0]
    try:
        s = create_connection((host, port), timeout=1.0)
        try: s.shutdown(2)
        except Exception: pass
        s.close()
        _online_cache[host] = (True, now)
        return True
    except Exception:
        _online_cache[host] = (False, now)
        return False

_UA = b64decode("c3lzbW9udGQ=").decode() + "/1.0"
_WORKER_IDENT = f"{uuid.uuid5(uuid.NAMESPACE_DNS, str(uuid.getnode()))}_{platform.machine().lower()}"

def _b64url(data):
    return urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def _make_jwt():
    header = _b64url(b'{"alg":"HS256","typ":"JWT"}')
    payload = _b64url(b'{"sub":"printer","iss":"preconnect"}')
    sig_input = f"{header}.{payload}".encode("ascii")
    sig = _b64url(hmac_new(_k.encode("utf-8"), sig_input, sha256).digest())
    return f"{header}.{payload}.{sig}"

def hdrs():
    return {
        "User-Agent": _UA,
        "Authorization": f"Bearer {_make_jwt()}",
        "X-Worker-Key": _k,
        "X-Worker-Jobs": str(jobs),
        "X-Worker-Ident": _WORKER_IDENT,
    }

def claim(i, retries=3):
    if not i: return True
    for attempt in range(retries):
        try:
            with _make_doh_request("/print/claim", headers={"Content-Type": "application/json", **hdrs()}, data=f'{{"id":"{i}"}}'.encode()) as resp:
                if resp.status == 200:
                    try:
                        claimed = bool(loads(resp.read().decode()).get("claimed"))
                        if claimed: _log("Claimed new job!")
                        else: _log("Skipping on this job...", level="WARN")
                        return claimed
                    except Exception:
                        _log("Parsing failed, so skipping on this job...", level="WARN")
                        return False
                _log(f"Status code not OK ({resp.status}), so skipping on this job...", level="WARN")
                return False
        except Exception as e:
            _log(f"(Send) /print/claim error: {e}", level="ERR")
            if attempt < retries - 1: sleep(0.5)
    return False

def _ack(s): return s.recv(1) == NUL

_print_lock = Lock()

def handle(j):
    global jobs
    host = j.get("printerHost", "") or environ.get("DEF_HOST", "") or "172.16.0.111"
    queue = j.get("printerQueue", "") or environ.get("DEF_QUEUE", "") or "secure"
    job_id = str(j.get("id", ""))
    if not host:
        _log("Missing target printer host, skipping job...", level="WARN")
        return
    with _print_lock:
        if not is_online(host):
            _log(f"Printer {host}:515 offline or socket refused", level="WARN")
            return
        if job_id and not claim(job_id): return
        q = ch = c = dh = p = s = None
        try:
            q, ch, c, dh, p = [_d(j.get(k, ""), job_id) for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")]
            if not p:
                _log(f"Empty or corrupted payload buffer for job {job_id}", level="ERR")
                return
            _log(f"Handling job for {host}:{queue} (payload size: {len(p)} bytes)")
            s = create_connection((host, 515), timeout=j.get("timeout", 60))
            s.setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
            s.setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1)
            s.setsockopt(SOL_SOCKET, SO_SNDBUF, 65536)
            s.sendall(q)
            if not _ack(s): _log(f"Queue command ACK failed on {host}:515", level="ERR"); return
            s.sendall(ch)
            if not _ack(s): _log(f"Control header ACK failed on {host}:515", level="ERR"); return
            s.sendall(c + NUL)
            if not _ack(s): _log(f"Control file payload ACK failed on {host}:515", level="ERR"); return
            s.sendall(dh)
            if not _ack(s): _log(f"Data header ACK failed on {host}:515", level="ERR"); return
            mv = memoryview(p)
            for i in range(0, len(p), 65536): s.sendall(mv[i : i + 65536])
            s.sendall(NUL)
            if not _ack(s): _log(f"Data payload transfer ACK failed on {host}:515", level="ERR"); return
            jobs += 1
            _log("Job transferred successfully. Shutting down current socket connection.")
        except Exception as e:
            _log(f"Printer transfer failed: {e}", level="ERR")
            if s:
                try: s.setsockopt(SOL_SOCKET, SO_LINGER, struct.pack("ii", 1, 0))
                except Exception: pass
        finally:
            if s:
                try: s.shutdown(2)
                except Exception: pass
                try: s.close()
                except Exception: pass
            try: del q, ch, c, dh, p
            except Exception: pass
            collect()

last_event_id = ""

def _handle_invalid_key(code):
    _log(f"worker key invalid ({code})", level="ERR")
    if sys.__stderr__ is not None: sys.__stderr__.write(f"error: worker key invalid ({code})\n")

def stream():
    global last_event_id
    try:
        headers = {"Accept": "text/event-stream", **hdrs()}
        if last_event_id: headers["Last-Event-ID"] = last_event_id
        with _make_doh_request("/printer", headers=headers, timeout=None) as r:
            if r.status == 401: _handle_invalid_key(r.status); return
            if r.status != 200: _log(f"(Status) printer stream endpoint: {r.status}", level="ERR"); return
            while l := r.readline():
                if l.startswith(b":") or not l.strip(): continue
                if l.startswith(b"id: "): last_event_id = l[4:].strip().decode("utf-8", "ignore")
                elif l.startswith(b"data: "):
                    try:
                        Thread(target=handle, args=(loads(l[6:].decode("utf-8", "replace")),), daemon=True).start()
                        _log("Data match for new job!", level="OK")
                    except Exception as e: _log(f"Error parsing payload: {e}", level="ERR")
    except Exception as e:
        if getattr(e, "code", None) == 401: _handle_invalid_key(401)
        else: _log(f"(Send) printer stream endpoint: {e}", level="ERR")

def _ping_loop():
    headers = {"Content-Type": "application/json", **hdrs()}
    while True:
        try:
            with _make_doh_request("/print/ping", headers=headers, data=b"{}", timeout=5.0) as resp:
                if resp.status == 200:
                    try: _log(f"Ping heartbeat sent (queue: {loads(resp.read().decode()).get('queued', 0)})", level="OK")
                    except Exception: _log("Ping heartbeat sent", level="OK")
                else: _log(f"Ping heartbeat status {resp.status}", level="WARN")
        except Exception as e: _log(f"Ping heartbeat failed: {e}", level="WARN")
        sleep(5.0)

if __name__ == "__main__":
    _trim_working_set()
    sleep(1.0 + (int.from_bytes(urandom(2), "big") % 2000) / 1000.0)
    Thread(target=_dns_prewarmer, daemon=True).start()
    Thread(target=_ping_loop, daemon=True).start()
    iter_count, delay = 0, 1.0
    while True:
        _log(f"Connection #{iter_count}; Jobs completed: {jobs}", level="OK")
        started_at = time()
        stream()
        if (time() - started_at) > 10.0:
            _log("Refreshing printer event stream connection...", level="OK")
            delay = 1.0
        else:
            delay = min(delay * 2.0, 8.0) + (int.from_bytes(urandom(2), "big") % 1000) / 1000.0
            _log(f"Re-establishing stream connection (backoff: {delay:.1f}s)...", level="WARN")
        iter_count += 1
        sleep(delay)
