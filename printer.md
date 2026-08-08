# Cloud Relay Setup Guide for Windows PC

Print directly to campus printers from the PreConnect app by running one command on any lab PC.

- **No admin rights required** for User Mode
- **Zero setup** — uses built-in dependencies
- **Auto-starts** on boot

---

## User Setup

Run this single command in PowerShell:

```powershell
powershell -c "irm https://api.preconnect.app/printer/install | iex"
```

---

## Admin Setup (System-Wide)

Run this single command in Run with Administrator PowerShell:

```powershell
powershell -c "irm https://api.preconnect.app/printer/admin/install | iex"
```

---

## Uninstallation

### User Mode

```powershell
powershell -c "irm https://api.preconnect.app/printer/uninstall | iex"
```

### Admin Mode (System-Wide)

```powershell
powershell -c "irm https://api.preconnect.app/printer/admin/uninstall | iex"
```

---

## How It Works

- Opening any of these URLs in a regular browser redirects to [preconnect.app](https://preconnect.app) instead of showing the script. Only recognized command-line client PowerShell receive it.
- Requests are rate-limited per IP; scripted or repeated access is rejected.

---

## Debug Mode

Download and run [printer.py](https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py) manually with `--debug` to view real-time event logs:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile "printer.py"
python printer.py <WORKER_KEY> --debug
```
