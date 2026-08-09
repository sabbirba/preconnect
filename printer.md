# Cloud Relay Setup Guide for Windows PC

Print directly to campus printers from the PreConnect app by running one command on any lab PC.

- **No admin rights required** for User Mode
- **Zero setup** — uses built-in dependencies with automatic TLS 1.2/1.1/1.0 protocol support
- **Real-time Mercure SSE** — instant job delivery (~2ms latency)
- **Auto-starts** on boot

---

## User Setup

Run this single command in PowerShell:

```powershell
powershell -c "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls; irm https://api.preconnect.app/printer/install | iex"
```

---

## Admin Setup (System-Wide)

Run this single command in Administrator PowerShell:

```powershell
powershell -c "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls; irm https://api.preconnect.app/printer/admin/install | iex"
```

---

## Uninstallation

### User Mode

```powershell
powershell -c "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls; irm https://api.preconnect.app/printer/uninstall | iex"
```

### Admin Mode (System-Wide)

```powershell
powershell -c "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls; irm https://api.preconnect.app/printer/admin/uninstall | iex"
```

---

## Debug Mode

Download and run [printer.py](https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py) manually with `--debug` to view real-time event logs:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile "printer.py"
python printer.py <WORKER_KEY> --debug
```

### Sample Terminal Debug Output

```text
[OK] Claimed new job!
[OK] Handling job for 172.16.0.111:secure (payload size: 464997 bytes)
[OK] Job transferred successfully. Shutting down current socket connection.
```

---

## Architecture & Security

- **Mercure Event Stream**: Streams real-time job notifications from `/.well-known/mercure` over persistent HTTP sockets.
- **Heartbeat & Queue Release**: Worker pings `POST /print/ping` every 5 seconds with `X-Worker-Ident` headers. Unclaimed jobs are flushed every 1 second.
- **Hardware Serial Lock**: LPR printer connections to `172.16.0.111:515` are serialized using a thread-safe mutex lock to prevent port 515 socket collisions.
- **Security & Privacy**: Browsing installer URLs directly in a browser redirects to [preconnect.app](https://preconnect.app). Script requests are rate-limited per IP.
