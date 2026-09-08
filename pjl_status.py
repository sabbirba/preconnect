import socket
import sys

PRINTER_HOST = "172.16.0.111"
PRINTER_PORT = 515
TIMEOUT = 4.0

def get_pjl_status(host=PRINTER_HOST, port=PRINTER_PORT):
    cmd = b"\x1B%-12345X@PJL\r\n@PJL INFO STATUS\r\n\x1B%-12345X"
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(TIMEOUT)
    try:
        s.connect((host, port))
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
        if raw:
            print(raw.decode("latin1", errors="replace").strip())
        else:
            print("No response from printer.")
    except Exception as e:
        print(f"Failed connecting to {host}:{port} -> {e}")
    finally:
        s.close()

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else PRINTER_HOST
    get_pjl_status(target)
