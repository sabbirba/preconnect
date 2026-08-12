# Printer Setup

Print directly to campus printers.

Official Rust repository: [hitblast/preprintd](https://github.com/hitblast/preprintd)

---

## Command Prompt (CMD) Setup

### 1. User Setup (Standard / Non-Admin)

Paste directly into **CMD**:

```cmd
powershell -Command "$d = \"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $py = \"$d\printer.py\"; if (-not (Test-Path $py)) { Invoke-WebRequest -Uri \"https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py\" -OutFile $py -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes(\"<PRINT_KEY>\"), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser); Set-Content \"$d\printer.key\" (\"DPAPI:\" + [Convert]::ToBase64String($e)); Start-Process pythonw -ArgumentList \"`\"$py`\"\""
```

---

### 2. Admin Setup (Administrator)

Paste directly into **CMD (as Administrator)**:

```cmd
powershell -Command "$d = \"$env:ProgramData\printer\"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $py = \"$d\printer.py\"; if (-not (Test-Path $py)) { Invoke-WebRequest -Uri \"https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py\" -OutFile $py -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes(\"<PRINT_KEY>\"), $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine); Set-Content \"$d\printer.key\" (\"DPAPI:\" + [Convert]::ToBase64String($e)); schtasks /Create /TN \"printer\" /TR \"pythonw `\"$py`\"\" /SC ONSTART /RU SYSTEM /RL HIGHEST /F; schtasks /Run /TN \"printer\""
```

---

## PowerShell Setup

### 1. User Setup (Standard / Non-Admin)

Run in **PowerShell**:

```powershell
$d = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $py = "$d\printer.py"; if (-not (Test-Path $py)) { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile $py -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<PRINT_KEY>"), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser); Set-Content "$d\printer.key" ("DPAPI:" + [Convert]::ToBase64String($e)); Start-Process pythonw -ArgumentList "`"$py`""
```

---

### 2. Admin Setup (Administrator)

Run in **PowerShell as Administrator**:

```powershell
$d = "$env:ProgramData\printer"; New-Item -ItemType Directory -Force -Path $d | Out-Null; $py = "$d\printer.py"; if (-not (Test-Path $py)) { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py" -OutFile $py -UseBasicParsing }; Add-Type -AssemblyName System.Security; $e = [System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes("<PRINT_KEY>"), $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine); Set-Content "$d\printer.key" ("DPAPI:" + [Convert]::ToBase64String($e)); schtasks /Create /TN "printer" /TR "pythonw `"$py`"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F; schtasks /Run /TN "printer"
```

---

## Debug Mode

```cmd
powershell -Command "Invoke-WebRequest -Uri \"https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py\" -OutFile \"printer.py\" -UseBasicParsing; python printer.py <PRINT_KEY> --debug"
```

---

## Uninstall

### CMD

Paste into **CMD**:

```cmd
powershell -Command "schtasks /Delete /TN \"printer\" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter \"Name='pythonw.exe' or Name='python.exe'\" | Where-Object { $_.CommandLine -like '*printer*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s=\"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\"; Remove-Item \"$s\printer.*\",\"$s\printer.key\" -Force -ErrorAction SilentlyContinue; Remove-Item \"$env:ProgramData\printer\" -Recurse -Force -ErrorAction SilentlyContinue"
```

---

### PowerShell

Run in **PowerShell**:

```powershell
schtasks /Delete /TN "printer" /F 2>$null; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name='pythonw.exe' or Name='python.exe'" | Where-Object { $_.CommandLine -like '*printer*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; $s="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Remove-Item "$s\printer.*","$s\printer.key" -Force -ErrorAction SilentlyContinue; Remove-Item "$env:ProgramData\printer" -Recurse -Force -ErrorAction SilentlyContinue
```