import base64
import json
import socket
import time
import urllib.request

def stream():
    req = urllib.request.Request("https://api.preconnect.app/printer", headers={"Accept": "text/event-stream", "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(req) as resp:
            for line in resp:
                line = line.decode("utf-8").strip()
                if line.startswith("data: "):
                    try:
                        job = json.loads(line[6:])
                        handle(job)
                    except Exception:
                        pass
    except Exception:
        pass

def handle(job):
    try:
        control = base64.b64decode(job["controlFile"])
        payload = base64.b64decode(job["payload"])
        host = job["printerHost"]
        queue = job["printerQueue"]
        
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect((host, 515))
        
        if not send_ack(s, b"\x02" + queue.encode("utf-8") + b"\n"):
            s.close()
            return
            
        cf_hdr = f"\x02{len(control)} cfA002sysprint\n".encode("utf-8")
        if not send_ack(s, cf_hdr) or not send_ack(s, control + b"\x00"):
            s.close()
            return
            
        df_hdr = f"\x03{len(payload)} dfA002sysprint\n".encode("utf-8")
        if send_ack(s, df_hdr):
            send_ack(s, payload + b"\x00")
            
        s.close()
    except Exception:
        pass

def send_ack(s, data):
    s.sendall(data)
    ack = s.recv(1)
    return len(ack) == 1 and ack[0] == 0

if __name__ == "__main__":
    while True:
        stream()
        time.sleep(5)
