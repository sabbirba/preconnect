import socket
import sys

PRINTER_HOST = "172.16.0.111"
PRINTER_PORT = 515
TIMEOUT = 4.0

def query_lpd(host, cmd_byte, queue):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(TIMEOUT)
    try:
        s.connect((host, PRINTER_PORT))
        s.sendall(cmd_byte + queue.encode("ascii") + b"\n")
        chunks = []
        while True:
            try:
                buf = s.recv(2048)
                if not buf:
                    break
                chunks.append(buf)
            except socket.timeout:
                break
        raw = b"".join(chunks)
        if raw and raw.strip():
            return raw.decode("latin1", errors="replace").strip()
    except Exception:
        pass
    finally:
        s.close()
    return None

def query_raw(host):
    cmd = b"\x1B%-12345X@PJL\r\n@PJL INFO STATUS\r\n\x1B%-12345X"
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(TIMEOUT)
    try:
        s.connect((host, PRINTER_PORT))
        s.sendall(cmd)
        chunks = []
        while True:
            try:
                buf = s.recv(2048)
                if not buf:
                    break
                chunks.append(buf)
                if b"\x0C" in buf:
                    break
            except socket.timeout:
                break
        raw = b"".join(chunks)
        if raw and raw.strip():
            return raw.decode("latin1", errors="replace").strip()
    except Exception:
        pass
    finally:
        s.close()
    return None

def get_pjl_status(host=PRINTER_HOST):
    for cmd_byte in (b"\x04", b"\x03"):
        for q in ("secure", "", "lp", "Hold", "print"):
            res = query_lpd(host, cmd_byte, q)
            if res:
                print(res)
                return
    res = query_raw(host)
    if res:
        print(res)
        return
    print("No response from printer.")

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else PRINTER_HOST
    get_pjl_status(target)
