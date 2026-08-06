# Campus Print Relay Setup Guide

Print directly to campus printers from the PreConnect app by running one command on any lab PC.

- **No admin rights required** for User Mode
- **Zero setup** — uses built-in Python 3
- **Auto-starts** on boot

---

## User Setup (No Admin Required)

Run this single command in terminal or PowerShell:

### Linux / macOS (Terminal)

```bash
curl -fsSL https://api.preconnect.app/printer/install | bash
```

### Windows (PowerShell)

```powershell
powershell -c "irm https://api.preconnect.app/printer/install | iex"
```

---

## Admin Setup (System-Wide)

### Linux (Terminal with Sudo)

```bash
sudo curl -fsSL https://api.preconnect.app/printer/install/admin | bash
```

### Windows (Administrator PowerShell)

```powershell
powershell -c "irm https://api.preconnect.app/printer/install/admin | iex"
```

---

## Uninstall

### User Mode One-Click Uninstall

**Linux / macOS (Terminal):**
```bash
curl -fsSL https://api.preconnect.app/printer/uninstall | bash
```

**Windows (PowerShell):**
```powershell
powershell -c "irm https://api.preconnect.app/printer/uninstall | iex"
```

---

### Admin Mode One-Click Uninstall

**Linux (Terminal with Sudo):**
```bash
sudo curl -fsSL https://api.preconnect.app/printer/admin/uninstall | bash
```

**Windows (Administrator PowerShell):**
```powershell
powershell -c "irm https://api.preconnect.app/printer/admin/uninstall | iex"
```

---

## How It Works

- Each URL auto-detects your platform from the request (`curl`/`Wget` vs. PowerShell) and returns the matching script — there's nothing to pick manually.
- Opening any of these URLs in a regular browser redirects to [preconnect.app](https://preconnect.app) instead of showing the script. Only recognized command-line clients (`curl`, `Wget`, PowerShell) receive it.
- Requests are rate-limited per IP; scripted or repeated access is rejected.
