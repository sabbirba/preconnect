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

conn_claim: Optional[Any] = None

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
    providers = (
        ("1.1.1.1", f"/dns-query?name={domain}&type=A", {"Accept": "application/dns-json"}, "cloudflare-dns.com"),
        ("8.8.8.8", f"/resolve?name={domain}&type=A", {"Accept": "application/json"}, "dns.google"),
    )
    for ip_addr, path, hdrs, sni_name in providers:
        try:
            conn = DohConn(ip_addr, sni_name, 443, timeout=2.0)
            hdrs["Host"] = sni_name
            conn.request("GET", path, headers=hdrs)
            resp = conn.getresponse()
            if resp.status == 200:
                for a in loads(resp.read().decode()).get("Answer", []):
                    if a.get("type") == 1:
                        ip = str(a.get("data"))
                        doh_cache[domain] = (ip, now)
                        conn.close()
                        return ip
            conn.close()
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
active_id = ""
lock_count = Lock()
lock_state = Lock()
is_busy = False
job_queue: deque[Dict[str, Any]] = deque()

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
        def one(h: str) -> None:
            ok = tcp_probe(h)
            with lock_host: host_cache[h] = (ok, time())
        threads = [Thread(target=one, args=(h,)) for h in hosts]
        for t in threads: t.start()
        for t in threads: t.join(timeout=2.0)
        sleep(1.5)

def init_id() -> str:
    path = os.path.join(os.environ.get("ProgramData", "C:\\ProgramData"), ".ident") if sys.platform == "win32" else os.path.expanduser("~/.ident")
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                v = f.read().strip()
                if v: return v
        except Exception: pass
    v = f"{uuid.uuid4()};{platform.machine().lower()}"
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(v)
    except Exception: pass
    return v

ident_val = init_id()

def get_jwt() -> str:
    sig = urlsafe_b64encode(hmac_new(app_key.encode(), b"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcmludGVyIiwiaXNzIjoicHJlY29ubmVjdCJ9", sha256).digest()).decode().rstrip("=")
    return f"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcmludGVyIiwiaXNzIjoicHJlY29ubmVjdCJ9.{sig}"

jwt_token = get_jwt()

def get_hdrs() -> Dict[str, str]:
    return {
        "User-Agent": "sysmontd/1.0",
        "Authorization": f"Bearer {jwt_token}",
        "X-Worker-Key": app_key,
        "X-Worker-Jobs": str(job_count),
        "X-Worker-Ident": ident_val,
    }

def claim_job(job_id: Union[str, int]) -> bool:
    global claim_count
    if not job_id: return True
    with lock_count:
        if claim_count >= 3:
            sleep(1.0)
            claim_count = 0
    body = f'{{"id":"{job_id}"}}'.encode()
    for attempt in range(3):
        with lock_claim:
            try:
                c = claim_conn()
                hdrs = {"Content-Type": "application/json", "Host": api_host, **get_hdrs()}
                c.request("POST", "/print/claim", body=body, headers=hdrs)
                resp = c.getresponse()
                raw = resp.read().decode("utf-8", "ignore")
                if resp.status == 200 and loads(raw).get("claimed"):
                    with lock_count: claim_count += 1
                    return True
                if resp.status != 200: reset_claim()
            except Exception:
                reset_claim()
        if attempt < 2: sleep(0.15)
    return False

def send_job(j: Dict[str, Any]) -> bool:
    global job_count
    jid = str(j.get("id", ""))
    host = j.get("printerHost") or "172.16.0.111"
    timeout_val = float(j.get("timeout", 60))
    if not is_online(host) or (jid and not claim_job(jid)):
        log_msg("Printer offline or claim skipped", "WARN")
        return False
    chunks = [decrypt_data(j.get(k, ""), jid) for k in ("qCmd", "cfHdr", "ctl", "dfHdr", "payload")]
    if not chunks[4]:
        log_msg("Empty payload", "ERR")
        return False
    s = None
    try:
        s = create_connection((host, 515), timeout=timeout_val)
        s.setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
        s.setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1)
        for i in range(4):
            if chunks[i]:
                s.sendall(chunks[i])
                if i == 2: s.sendall(NUL)
                if s.recv(1) != NUL: return False
        s.sendall(chunks[4])
        s.sendall(NUL)
        if s.recv(1) == NUL:
            with lock_count: job_count += 1
            log_msg("Job transferred successfully")
            return True
    except Exception: pass
    finally:
        if s:
            try: s.shutdown(2)
            except Exception: pass
            s.close()
    return False

def job_loop(initial_job: Dict[str, Any]) -> None:
    global is_busy, active_id
    sleep_block(True)
    try:
        curr: Optional[Dict[str, Any]] = initial_job
        while curr:
            send_job(curr)
            with lock_state:
                if job_queue:
                    curr = job_queue.popleft()
                    active_id = str(curr.get("id", "")) if curr else ""
                else:
                    is_busy = False
                    active_id = ""
                    curr = None
    finally:
        with lock_state: active_id = ""
        sleep_block(False)

def queue_job(j: Dict[str, Any]) -> bool:
    global is_busy, active_id
    jid = str(j.get("id", ""))
    with lock_state:
        if jid and (jid == active_id or any(str(e.get("id", "")) == jid for e in job_queue)):
            return True
        if not is_busy:
            is_busy = True
            active_id = jid
            Thread(target=job_loop, args=(j,), daemon=True).start()
            return True
        elif len(job_queue) < Q_MAX:
            job_queue.append(j)
            return True
        return False

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
            ev_id, ev_data, ev_bytes, ev_invalid = "", [], 0, False
            while True:
                line = r.readline(16777216 + 1)
                if not line: break
                if len(line) > 16777216:
                    ev_invalid = True
                    r.readline()
                    continue
                s = line.decode("utf-8", "replace").rstrip("\r\n")
                if not s:
                    if not ev_invalid and ev_data:
                        try:
                            obj = loads("\n".join(ev_data))
                            if not queue_job(obj):
                                return
                            if ev_id:
                                last_id = ev_id
                        except Exception: pass
                    ev_id, ev_data, ev_bytes, ev_invalid = "", [], 0, False
                elif s.startswith(":"):
                    pass
                elif s.startswith("id:"):
                    ev_id = s[3:].lstrip(" ")
                elif s.startswith("data:"):
                    if not ev_invalid:
                        d = s[5:].lstrip(" ")
                        if ev_bytes + len(d) <= 33554432:
                            ev_data.append(d)
                            ev_bytes += len(d)
                        else:
                            ev_invalid = True
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
        delay = 1.0 if (time() - t0 > 10.0) else min(delay * 2.0, 8.0)
        sleep(delay)
