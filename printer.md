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
curl -fsSL preconnect.app/printer | bash
```

### Windows (PowerShell)

```powershell
powershell -c "irm https://preconnect.app/printer | iex"
```

---

## Admin Setup (System-Wide)

### Linux (Terminal with Sudo)

```bash
sudo curl -fsSL preconnect.app/printer/admin | bash
```

### Windows (Administrator PowerShell)

```powershell
powershell -c "irm https://preconnect.app/printer/admin | iex"
```

---

## Uninstall

### User Mode One-Click Uninstall

**Linux / macOS (Terminal):**
```bash
curl -fsSL preconnect.app/printer/uninstall | bash
```

**Windows (PowerShell):**
```powershell
powershell -c "irm https://preconnect.app/printer/uninstall | iex"
```

---

### Admin Mode One-Click Uninstall

**Linux (Terminal with Sudo):**
```bash
sudo curl -fsSL preconnect.app/printer/admin/uninstall | bash
```

**Windows (Administrator PowerShell):**
```powershell
powershell -c "irm https://preconnect.app/printer/admin/uninstall | iex"
```
