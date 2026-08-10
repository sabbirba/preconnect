# Cloud Relay Setup Guide for Windows Lab PC

Print directly to campus printers from the PreConnect app by running pure PowerShell commands on any lab PC.

- **No admin rights required** for User Mode
- **Zero setup** — uses built-in dependencies
- **Real-time** — instant job delivery (~2ms latency)
- **Auto-starts** on boot

---

## User Setup (Persistent Auto-Start)

Run this command in PowerShell (replace `<WORKER_KEY>` with your worker key):

```powershell
$d="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$d\printer.pyw" -UseBasicParsing; Set-Content "$d\printer.key" "<WORKER_KEY>"; Start-Process pythonw -ArgumentList "`"$d\printer.pyw`"" -WindowStyle Hidden
```

---

## Admin Setup (System-Wide Service with ACL Protection)

Run this command in Administrator PowerShell (replace `<WORKER_KEY>` with your worker key).

```powershell
$d="$env:ProgramData\printer"; New-Item -ItemType Directory -Force -Path $d; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$d\printer.pyw" -UseBasicParsing; Set-Content "$d\printer.key" "<WORKER_KEY>"; icacls "$d\printer.key" /inheritance:r /grant:r "SYSTEM:(F)" "Administrators:(F)"; schtasks /Create /TN "printer" /TR "pythonw.exe `"$d\printer.pyw`"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F; schtasks /Run /TN "printer"
```

---

## Admin Setup (Zero-Dependency Standalone Python)

Run this command in Administrator PowerShell on fresh lab PCs **without Python pre-installed**

```powershell
$d="$env:ProgramData\printer"; New-Item -ItemType Directory -Force -Path $d; Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile "$d\py.zip" -UseBasicParsing; Expand-Archive "$d\py.zip" -DestinationPath "$d\py" -Force; Remove-Item "$d\py.zip"; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$d\printer.pyw" -UseBasicParsing; Set-Content "$d\printer.key" "<WORKER_KEY>"; icacls "$d\printer.key" /inheritance:r /grant:r "SYSTEM:(F)" "Administrators:(F)"; schtasks /Create /TN "printer" /TR "`"$d\py\pythonw.exe`" `"$d\printer.pyw`"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F; schtasks /Run /TN "printer"
```

---

## Direct / Quick Background Run (One-time)

Run printer worker in the background directly without installation:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "printer.pyw" -UseBasicParsing; Start-Process "pythonw" -ArgumentList "printer.pyw","<WORKER_KEY>" -WindowStyle Hidden
```

---

## Admin Management Commands

- **Check Service Status**:
  ```powershell
  schtasks /Query /TN "printer" /FO LIST /V
  ```

- **Restart Service**:
  ```powershell
  schtasks /Run /TN "printer"
  ```

---

## Debug Mode

Download and run [printer.py](https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py) manually with `--debug` to view real-time event logs:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "printer.py" -UseBasicParsing
python printer.py <WORKER_KEY> --debug
```

---

## Uninstall

### User Mode Uninstall:
```powershell
$d="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='pythonw.exe' or Name='python.exe'" | Where-Object { $_.CommandLine -like "*printer.pyw*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Item "$d\printer.pyw","$d\printer.key" -Force -ErrorAction SilentlyContinue
```

### Admin Mode Uninstall:
```powershell
schtasks /Delete /TN "printer" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='pythonw.exe' or Name='python.exe'" | Where-Object { $_.CommandLine -like "*printer.pyw*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Remove-Item "$env:ProgramData\printer" -Recurse -Force -ErrorAction SilentlyContinue
```

---

## Architecture & Security

- **Mercure Event Stream**: Streams real-time job notifications from `/.well-known/mercure` over persistent HTTP sockets.
- **Heartbeat & Queue Release**: Worker pings `POST /print/ping` every 5 seconds with `X-Worker-Ident` headers. Unclaimed jobs are flushed every 1 second.
- **Hardware Serial Lock**: LPR printer connections are serialized using a thread-safe mutex lock to prevent port socket collisions.
- **NTFS ACL Protection**: Admin setups restrict `printer.key` permissions to `SYSTEM` exclusively.