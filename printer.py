import atexit, ctypes, os, platform, signal, sys, uuid, zlib
from collections import deque
from base64 import b64decode, urlsafe_b64encode
from gc import collect, disable
from hashlib import sha256
from hmac import new as hmac_new
from http.client import HTTPSConnection
from json import loads
from socket import IPPROTO_TCP, SO_KEEPALIVE, SO_SNDBUF, SOL_SOCKET, TCP_NODELAY, create_connection, socket
from ssl import create_default_context
from threading import Lock, Thread
from time import sleep, time
from typing import Any, Dict, Optional, Tuple, Union
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
disable()

def sleep_block(on: bool = True) -> None:
    if sys.platform == "win32":
        try: ctypes.windll.kernel32.SetThreadExecutionState(0x80000001 if on else 0x80000000)
        except Exception: pass

def clean_state() -> None:
    global app_key, conn_claim
    app_key = ""
    if conn_claim:
        try: conn_claim.close()
        except Exception: pass
        conn_claim = None
    sleep_block(False)
    collect()

atexit.register(clean_state)

try:
    signal.signal(signal.SIGINT, lambda s, f: ( clean_state(), sys.exit(0) ))
    signal.signal(signal.SIGTERM, lambda s, f: ( clean_state(), sys.exit(0) ))
except Exception: pass

def load_key() -> str:
    k = ""
    for name in ("PRINTER_KEY", "KEY", "WORKER_KEY"):
        k = os.environ.get(name, "").strip()
        if k: break
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
        sys.stderr.write("error: key required\n")
        sys.exit(1)
    if len(sys.argv) > 1: sys.argv[1] = " " * len(sys.argv[1])
    return k

app_key = load_key()
app_debug = "--debug" in sys.argv

def log_msg(msg: str, level: str = "OK") -> None:
    if app_debug or level in ("ERR", "WARN"):
        sys.stderr.write(f"[{level}] {msg}\n")
        sys.stderr.flush()

doh_cache: Dict[str, Tuple[str, float]] = {}

def resolve_doh(domain: str) -> str:
    now = time()
    if domain in doh_cache and now - doh_cache[domain][1] < 300: return doh_cache[domain][0]
    for server in ("1.1.1.1", "8.8.8.8"):
        try:
            req = Request(f"https://{server}/dns-query?name={domain}&type=A", headers={"Accept": "application/dns-json"})
            with urlopen(req, timeout=2.0) as resp:
                if resp.status == 200:
                    for a in loads(resp.read().decode()).get("Answer", []):
                        if a.get("type") == 1:
                            ip = str(a.get("data"))
                            doh_cache[domain] = (ip, now)
                            return ip
        except Exception: pass
    return domain

api_host = b64decode("YXBpLnByZWNvbm5lY3QuYXBw").decode()
ssl_ctx = create_default_context()
class DohConn(HTTPSConnection):
    def __init__(self, ip: str, sni: str, port: int = 443, **kw):
        super().__init__(ip, port, **kw)
        self._sni = sni
    def connect(self) -> None:
        self.sock = ssl_ctx.wrap_socket(
            create_connection((self.host, self.port), timeout=self.timeout),
            server_hostname=self._sni,
        )

conn_claim: Optional[DohConn] = None
lock_claim = Lock()

def make_conn(timeout: Optional[float] = None) -> DohConn:
    ip = resolve_doh(api_host)
    target = ip if (ip and ip != api_host) else api_host
    return DohConn(target, api_host, 443, timeout=timeout)

def claim_conn() -> DohConn:
    global conn_claim
    if conn_claim is None:
        conn_claim = make_conn(5.0)
    return conn_claim

def reset_claim() -> None:
    global conn_claim
    if conn_claim:
        try: conn_claim.close()
        except Exception: pass
        conn_claim = None

def http_req(path: str, headers: Optional[Dict[str, str]] = None, data: Optional[bytes] = None, timeout: Optional[float] = None) -> Any:
    hdrs = dict(headers or {})
    hdrs["Host"] = api_host
    conn = make_conn(timeout)
    conn.request("POST" if data is not None else "GET", path, body=data, headers=hdrs)
    return conn.getresponse()

NUL = b"\x00"
Q_MAX = 8
job_count = 0
claim_count = 0
lock_count = Lock()
lock_state = Lock()
is_busy = False
job_queue: deque = deque()

def decrypt_data(s: str, job_id: Union[str, int] = "") -> bytes:
    if not s: return b""
    raw = b64decode(s)
    if len(raw) < 16: return b""
    iv, enc = raw[:16], raw[16:]
    p = sha256(app_key.encode() + iv + str(job_id).encode()).digest()
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

host_cache: Dict[str, Tuple[bool, float]] = {}
lock_host = Lock()

def tcp_probe(host: str) -> bool:
    try:
        s = create_connection((host, 515), timeout=0.5)
        try: s.shutdown(2)
        except Exception: pass
        s.close()
        return True
    except Exception:
        return False

def is_online(host: str) -> bool:
    if not host: return False
    with lock_host:
        if host in host_cache:
            return host_cache[host][0]
    ok = tcp_probe(host)
    with lock_host: host_cache[host] = (ok, time())
    return ok

def probe_loop() -> None:
    while True:
        with lock_host:
            hosts = list(host_cache.keys())
        for h in hosts:
            ok = tcp_probe(h)
            with lock_host: host_cache[h] = (ok, time())
        sleep(1.5)

def init_id() -> str:
    path = "C:\\ProgramData\\.ident" if sys.platform == "win32" else "/tmp/.ident"
    fallback = f"{uuid.uuid4()};{platform.machine().lower()}"
    try:
        if os.path.exists(path):
            v = open(path).read().strip()
            if v: return v
        with open(path, "w") as f: f.write(fallback)
        return fallback
    except Exception:
        return fallback

app_ident = init_id()
app_ua = b64decode("c3lzbW9udGQ=").decode() + "/1.0"

def make_jwt() -> str:
    def b64u(b: bytes) -> str: return urlsafe_b64encode(b).rstrip(b"=").decode()
    h, p = b64u(b'{"alg":"HS256","typ":"JWT"}'), b64u(b'{"sub":"printer","iss":"preconnect"}')
    sig = b64u(hmac_new(app_key.encode(), f"{h}.{p}".encode(), sha256).digest())
    return f"{h}.{p}.{sig}"

cached_jwt = make_jwt()

def get_hdrs() -> Dict[str, str]:
    return {
        "User-Agent": app_ua,
        "Authorization": f"Bearer {cached_jwt}",
        "X-Worker-Key": app_key,
        "X-Worker-Jobs": str(job_count),
        "X-Worker-Ident": app_ident,
    }

def claim_job(i: Union[str, int]) -> bool:
    global claim_count
    if not i: return True
    with lock_count:
        if claim_count >= 3:
            sleep(1.0)
            claim_count = 0
    body = f'{{"id":"{i}"}}'.encode()
    hdrs = {"Content-Type": "application/json", **get_hdrs()}
    for attempt in range(3):
        with lock_claim:
            try:
                conn = claim_conn()
                conn.request("POST", "/print/claim", body=body, headers=hdrs)
                resp = conn.getresponse()
                if resp.status == 200:
                    ok = bool(loads(resp.read().decode()).get("claimed"))
                    if ok:
                        with lock_count: claim_count += 1
                    return ok
                reset_claim()
            except Exception:
                reset_claim()
        if attempt < 2:
            sleep(0.15)
    return False

def send_job(j: Dict[str, Any]) -> None:
    global job_count
    host = j.get("printerHost") or "172.16.0.111"
    job_id = str(j.get("id", ""))
    if not host or not is_online(host) or (job_id and not claim_job(job_id)):
        return
    s: Optional[socket] = None
    try:
        q, ch, c, dh, p = [decrypt_data(j.get(k, ""), job_id) for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")]
        if not p: return
        log_msg(f"Handling job for {host} ({len(p)} bytes)")
        s = create_connection((host, 515), timeout=float(j.get("timeout", 60) or 60))
        s.setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
        s.setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1)
        s.setsockopt(SOL_SOCKET, SO_SNDBUF, 65536)
        for data, add_nul in [(q, False), (ch, False), (c, True), (dh, False)]:
            s.sendall(data + (NUL if add_nul else b""))
            if s.recv(1) != NUL: return
        mv = memoryview(p)
        for i in range(0, len(p), 65536): s.sendall(mv[i : i + 65536])
        s.sendall(NUL)
        if s.recv(1) != NUL: return
        job_count += 1
        log_msg("Job transferred successfully")
    except Exception as e:
        log_msg(f"Transfer error: {e}", "ERR")
    finally:
        if s:
            try: s.shutdown(2)
            except Exception: pass
            try: s.close()
            except Exception: pass

def job_loop(initial_job: Dict[str, Any]) -> None:
    global is_busy
    try:
        sleep_block(True)
        curr: Optional[Dict[str, Any]] = initial_job
        while curr:
            send_job(curr)
            with lock_state:
                if job_queue:
                    curr = job_queue.popleft()
                else:
                    is_busy = False
                    curr = None
    finally:
        sleep_block(False)

def queue_job(j: Dict[str, Any]) -> None:
    global is_busy
    jid = str(j.get("id", ""))
    with lock_state:
        if jid and any(str(e.get("id", "")) == jid for e in job_queue):
            return
        if not is_busy:
            is_busy = True
            Thread(target=job_loop, args=(j,), daemon=True).start()
        elif len(job_queue) < Q_MAX:
            job_queue.append(j)

last_id = ""

def sse_loop() -> None:
    global last_id
    try:
        h = {"Accept": "text/event-stream", **get_hdrs()}
        if last_id: h["Last-Event-ID"] = last_id
        with http_req("/printer", headers=h, timeout=None) as r:
            if r.status == 401:
                sys.stderr.write("error: key invalid (401)\n")
                clean_state()
                sys.exit(1)
            if r.status != 200: return
            ev_id, ev_data = "", []
            while line := r.readline():
                s = line.decode("utf-8", "replace").rstrip("\r\n")
                if not s:
                    if ev_data:
                        try: queue_job(loads("\n".join(ev_data)))
                        except Exception: pass
                        if ev_id: last_id = ev_id
                    ev_id, ev_data = "", []
                elif s.startswith(":"):
                    pass
                elif s.startswith("id: "):
                    ev_id = s[4:]
                elif s.startswith("data: "):
                    ev_data.append(s[6:])
    except Exception: pass

def ping_loop() -> None:
    while True:
        try:
            r = http_req("/print/ping", headers={"Content-Type": "application/json", **get_hdrs()}, data=b"{}", timeout=5.0)
            try: r.read()
            finally: r.close()
        except Exception: pass
        sleep(15.0)

if __name__ == "__main__":
    is_online("172.16.0.111")
    sleep(0.2)
    Thread(target=probe_loop, daemon=True).start()
    Thread(target=ping_loop, daemon=True).start()
    delay = 1.0
    while True:
        log_msg(f"Stream connect; Jobs: {job_count}")
        t0 = time()
        sse_loop()
        delay = 1.0 if (time() - t0) > 10.0 else min(delay * 2.0, 8.0)
        sleep(delay)
