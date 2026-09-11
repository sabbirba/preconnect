import atexit, ctypes, os, platform, signal, sys, uuid, zlib
from base64 import b64decode, urlsafe_b64encode
from gc import collect, disable
from hashlib import sha256
from hmac import new as hmac_new
from http.client import HTTPConnection, HTTPSConnection
from json import dumps, loads
from socket import IPPROTO_TCP, SO_KEEPALIVE, SO_SNDBUF, SOL_SOCKET, TCP_NODELAY, create_connection
from ssl import create_default_context
from threading import Lock, Thread
from time import sleep, time
from typing import Any, Dict, Optional, Tuple, Union
from urllib.parse import urlparse

sys.dont_write_bytecode = True
sys.tracebacklimit = 0
disable()

def _d(s: str) -> str:
    return b64decode(s).decode(_d_u)

_d_u = b64decode("dXRmLTg=").decode()

def sleep_block(on: bool = True) -> None:
    if sys.platform == _d("d2luMzI="):
        try: getattr(getattr(ctypes.windll, _d("a2VybmVsMzI=")), _d("U2V0VGhyZWFkRXhlY3V0aW9uU3RhdGU="))(0x80000001 if on else 0x80000000)
        except Exception: pass

linux_fd: Optional[Any] = None

def init_linux_inhibit() -> None:
    global linux_fd
    if sys.platform.startswith(_d("bGludXg=")):
        try:
            import dbus
            bus = dbus.SystemBus()
            mgr = bus.get_object(_d("b3JnLmZyZWVkZXNrdG9wLmxvZ2luMQ=="), _d("L29yZy9mcmVlZGVza3RvcC9sb2dpbjE="))
            iface = dbus.Interface(mgr, _d("b3JnLmZyZWVkZXNrdG9wLmxvZ2luMS5NYW5hZ2Vy"))
            linux_fd = iface.Inhibit(_d("c2xlZXA="), worker_alias, _d("UmVxdWlyZWQgZm9yIHN1c3RhaW5lZCBzdHJlYW1pbmcgb3BlcmF0aW9uLg=="), _d("YmxvY2s="))
        except Exception: pass

conn_claim: Optional[Any] = None

def clean_state() -> None:
    global app_key, conn_claim, linux_fd
    app_key = ""
    if conn_claim:
        try: conn_claim.close()
        except Exception: pass
        conn_claim = None
    if linux_fd:
        try: os.close(linux_fd.take())
        except Exception: pass
        linux_fd = None
    sleep_block(False)
    collect()

atexit.register(clean_state)

try:
    signal.signal(signal.SIGINT, lambda s, f: ( clean_state(), sys.exit(0) ))
    signal.signal(signal.SIGTERM, lambda s, f: ( clean_state(), sys.exit(0) ))
except Exception: pass

def load_key() -> str:
    k = ""
    for name in (_d("V09SS0VSX0tFWQ=="), _d("UFJJTlRFUl9LRVk="), _d("S0VZ")):
        k = os.environ.get(name, "").strip()
        if k: break
    if not k and len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        k = sys.argv[1].strip()
    if sys.platform == _d("d2luMzI=") and k.startswith(_d("RFBBUEk6")):
        try:
            from ctypes import wintypes
            class BLOB(ctypes.Structure):
                _fields_ = [("cb", wintypes.DWORD), ("pb", ctypes.POINTER(ctypes.c_byte))]
            raw = b64decode(k[6:])
            buf = ctypes.create_string_buffer(raw, len(raw))
            in_b, out_b = BLOB(len(raw), ctypes.cast(buf, ctypes.POINTER(ctypes.c_byte))), BLOB()
            crypt32 = getattr(ctypes.windll, _d("Y3J5cHQzMg=="))
            kernel32 = getattr(ctypes.windll, _d("a2VybmVsMzI="))
            if getattr(crypt32, _d("Q3J5cHRVbnByb3RlY3REYXRh"))(ctypes.byref(in_b), None, None, None, None, 0, ctypes.byref(out_b)):
                dec = ctypes.string_at(out_b.pb, out_b.cb).decode(_d("dXRmLTg="), _d("aWdub3Jl")).strip()
                getattr(kernel32, _d("TG9jYWxGcmVl"))(out_b.pb)
                k = dec
        except Exception: pass
    if not k:
        sys.stderr.write(_d("ZXJyb3I6IGtleSByZXF1aXJlZAo="))
        sys.exit(1)
    if len(sys.argv) > 1: sys.argv[1] = " " * len(sys.argv[1])
    return k

app_key = load_key()

doh_cache: Dict[str, Tuple[str, float]] = {}

def resolve_doh(domain: str) -> str:
    now = time()
    if domain in doh_cache and now - doh_cache[domain][1] < 300: return doh_cache[domain][0]
    try:
        conn = DohConn(_d("MS4xLjEuMQ=="), _d("Y2xvdWRmbGFyZS1kbnMuY29t"), 443, timeout=2.0)
        hdrs = {_d("QWNjZXB0"): _d("YXBwbGljYXRpb24vZG5zLWpzb24="), _d("SG9zdA=="): _d("Y2xvdWRmbGFyZS1kbnMuY29t")}
        conn.request(_d("R0VU"), _d("L2Rucy1xdWVyeT9uYW1lPXt9JnR5cGU9SFRUUFM=").format(domain), headers=hdrs)
        resp = conn.getresponse()
        if resp.status == 200:
            for a in loads(resp.read().decode(_d_u)).get(_d("QW5zd2Vy"), []):
                val = str(a.get(_d("ZGF0YQ=="), ""))
                if _d("aXB2NGhpbnQ=") in val:
                    ip = val.split(_d("aXB2NGhpbnQ="))[1].split()[0].split(",")[0]
                    doh_cache[domain] = (ip, now)
                    conn.close()
                    return ip
        conn.close()
    except Exception: pass
    return domain

base_parsed = urlparse(os.environ.get(_d("QkFTRV9VUkw="), _d("aHR0cHM6Ly9hcGkucHJlY29ubmVjdC5hcHAv")))
api_scheme = base_parsed.scheme or "https"
api_host = base_parsed.hostname or _d("YXBpLnByZWNvbm5lY3QuYXBw")
api_port = base_parsed.port or (443 if api_scheme == "https" else 80)
api_base_path = base_parsed.path.rstrip("/")
def_host = os.environ.get(_d("REVGX0hPU1Q="), _d("MTcyLjE2LjAuMTEx"))
def_queue = os.environ.get(_d("REVGX1FVRVVF"), _d("bHA="))
worker_alias = os.environ.get(_d("QUxJQVM="), _d("c3lzbW9udGQ="))
worker_agent = f"{worker_alias}/{_d('MS4w')}"
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

def make_conn(timeout: Optional[float] = None) -> Union[HTTPConnection, HTTPSConnection]:
    if api_scheme == "http":
        return HTTPConnection(api_host, api_port, timeout=timeout)
    ip = resolve_doh(api_host)
    target = ip if (ip and ip != api_host) else api_host
    return DohConn(target, api_host, api_port, timeout=timeout)

def claim_conn() -> Union[HTTPConnection, HTTPSConnection]:
    global conn_claim
    if conn_claim is None:
        conn_claim = make_conn(10.0)
    return conn_claim

def reset_claim() -> None:
    global conn_claim
    if conn_claim:
        try: conn_claim.close()
        except Exception: pass
        conn_claim = None

def http_req(path: str, headers: Optional[Dict[str, str]] = None, data: Optional[bytes] = None, timeout: Optional[float] = None) -> Any:
    full_path = f"{api_base_path}{path}"
    hdrs = dict(headers or {})
    hdrs[_d("SG9zdA==")] = api_host
    conn = make_conn(timeout)
    conn.request(_d("UE9TVA==") if data is not None else _d("R0VU"), full_path, body=data, headers=hdrs)
    return conn.getresponse()

NUL = b"\x00"
job_count = 0
lock_count = Lock()
print_lock = Lock()

def decrypt_data(s: str, job_id: Union[str, int] = "") -> bytes:
    if not s: return b""
    raw = b64decode(s.strip())
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

def is_online(host: str) -> bool:
    if not host: return False
    s = None
    try:
        s = create_connection((host, 515), timeout=1.0)
        try: s.shutdown(2)
        except Exception: pass
        return True
    except Exception:
        return False
    finally:
        if s:
            try: s.close()
            except Exception: pass

def init_id() -> str:
    fallback = f"{uuid.uuid4()};{platform.machine()}"
    s_dir = os.environ.get(_d("U1RBVEVfRElSRUNUT1JZ"))
    if not s_dir:
        return fallback
    try:
        if not os.path.exists(s_dir): os.makedirs(s_dir, exist_ok=True)
        path = os.path.join(s_dir, _d("LmlkZW50"))
        if os.path.exists(path):
            with open(path, "r", encoding=_d("dXRmLTg=")) as f:
                v = f.read().strip()
                if v: return v
        with open(path, "w", encoding=_d("dXRmLTg=")) as f:
            f.write(fallback)
    except Exception: pass
    return fallback

ident_val = init_id()

def get_jwt() -> str:
    sig = urlsafe_b64encode(hmac_new(app_key.encode(), b"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcmludGVyIiwiaXNzIjoicHJlY29ubmVjdCJ9", sha256).digest()).decode().rstrip("=")
    return f"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcmludGVyIiwiaXNzIjoicHJlY29ubmVjdCJ9.{sig}"

jwt_token = get_jwt()

def get_hdrs() -> Dict[str, str]:
    with lock_count:
        curr_jobs = str(job_count)
    return {
        _d("VXNlci1BZ2VudA=="): worker_agent,
        _d("QXV0aG9yaXphdGlvbg=="): f"{_d('QmVhcmVyIA==')}{jwt_token}",
        _d("WC1Xb3JrZXItS2V5"): app_key,
        _d("WC1Xb3JrZXItSm9icw=="): curr_jobs,
        _d("WC1Xb3JrZXItSW50ZWdyaXR5"): _d("dW5pbXBsZW1lbnRlZA=="),
        _d("WC1Xb3JrZXItSWRlbnQ="): ident_val,
    }

def post_claim(endpoint: str, payload_bytes: bytes) -> Optional[Tuple[int, bytes]]:
    full_path = f"{api_base_path}{endpoint}"
    for attempt in range(3):
        with lock_claim:
            try:
                c = claim_conn()
                hdrs = {
                    _d("Q29udGVudC1UeXBl"): _d("YXBwbGljYXRpb24vanNvbg=="),
                    _d("SG9zdA=="): api_host,
                    **get_hdrs()
                }
                c.request(_d("UE9TVA=="), full_path, body=payload_bytes, headers=hdrs)
                resp = c.getresponse()
                body = resp.read()
                return resp.status, body
            except Exception:
                reset_claim()
        if attempt < 2: sleep(0.15)
    return None

def claim_job(job_id: Union[str, int]) -> bool:
    if not job_id: return False
    res = post_claim(_d("L3ByaW50L2NsYWlt"), dumps({_d("aWQ="): str(job_id)}).encode())
    if res and res[0] == 200:
        try:
            val = loads(res[1].decode(_d("dXRmLTg="), _d("aWdub3Jl")))
            return bool(val.get(_d("Y2xhaW1lZA==")))
        except Exception: pass
    return False

def complete_job(job_id: Union[str, int], success: bool, error: Optional[str] = None) -> bool:
    if not job_id: return False
    payload: Dict[str, Any] = {_d("aWQ="): str(job_id), _d("c3VjY2Vzcw=="): success}
    if error is not None: payload[_d("ZXJyb3I=")] = str(error)
    res = post_claim(_d("L3ByaW50L2NvbXBsZXRl"), dumps(payload).encode())
    return bool(res and res[0] in (200, 204))

def send_job(j: Dict[str, Any]) -> bool:
    global job_count
    jid = str(j.get(_d("aWQ=")) or "")
    if not jid: return False
    host = str(j.get(_d("cHJpbnRlckhvc3Q=")) or def_host)
    _ = str(j.get(_d("cHJpbnRlclF1ZXVl")) or def_queue)
    raw_t = j.get(_d("dGltZW91dA=="))
    try:
        t_val = float(raw_t) if raw_t is not None else 60.0
        timeout_val = t_val if (t_val > 0.0 and t_val == t_val and t_val != float("inf")) else 60.0
    except Exception:
        timeout_val = 60.0
    if not is_online(host) or not claim_job(jid):
        return False
    chunks = [decrypt_data(str(j.get(k) or ""), jid) for k in (_d("cUNtZA=="), _d("Y2ZIZHI="), _d("Y3Rs"), _d("ZGZIZHI="), _d("cGF5bG9hZA=="))]
    s = None
    try:
        s = create_connection((host, 515), timeout=timeout_val)
        s.setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
        s.setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1)
        s.setsockopt(SOL_SOCKET, SO_SNDBUF, 65536)
        s.settimeout(timeout_val)
        for i in range(4):
            if chunks[i]:
                s.sendall(chunks[i])
                if i == 2: s.sendall(NUL)
                if s.recv(1) != NUL:
                    complete_job(jid, False, _d("UHJvdG9jb2wgZXJyb3I="))
                    return False
        s.sendall(chunks[4])
        s.sendall(NUL)
        if s.recv(1) == NUL:
            with lock_count: job_count += 1
            complete_job(jid, True)
            return True
        else:
            complete_job(jid, False, _d("VW5rbm93biBmYWlsdXJlIHNlbmRpbmcgdG8gcHJpbnRlcg=="))
    except Exception as e:
        complete_job(jid, False, str(e))
    finally:
        if s:
            try: s.shutdown(2)
            except Exception: pass
            s.close()
    return False

def on_job(j: Dict[str, Any]) -> None:
    def runner() -> None:
        with print_lock:
            sleep_block(True)
            try: send_job(j)
            except Exception: pass
            finally: sleep_block(False)
    Thread(target=runner, daemon=True).start()

def sse_loop() -> None:
    try:
        with http_req(_d("L3ByaW50ZXI="), headers={_d("QWNjZXB0"): _d("dGV4dC9ldmVudC1zdHJlYW0="), **get_hdrs()}, timeout=None) as r:
            if r.status == 401:
                sys.stderr.write(_d("ZXJyb3I6IGtleSBpbnZhbGlkICg0MDEpCg=="))
                clean_state()
                sys.exit(1)
            if r.status != 200: return
            while True:
                line = r.readline(16777216)
                if not line: break
                s = line.decode(_d("dXRmLTg="), _d("cmVwbGFjZQ==")).rstrip("\r\n")
                if s.startswith(_d("ZGF0YTog")):
                    try:
                        on_job(loads(s[6:]))
                    except Exception: pass
    except Exception: pass

if __name__ == "__main__":
    init_linux_inhibit()
    delay = 1.0
    while True:
        t0 = time()
        sse_loop()
        delay = 1.0 if (time() - t0 > 10.0) else min(delay * 2.0, 8.0)
        sleep(delay)
