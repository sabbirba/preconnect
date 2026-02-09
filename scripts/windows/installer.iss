#define MyAppName "PreConnect"
#define MyAppPublisher "PreConnect"
#define MyAppURL "https://preconnect.app"
#define MyAppExeName "PreConnect.exe"
#ifndef AppVersionFull
#define AppVersionFull AppVersion
#endif

[Setup]
AppId={{A0C7B1E9-2F31-4E1A-9B0C-2B8E91A6C0A1}}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputBaseFilename={#MyAppName}-windows-release-{#AppVersionFull}
OutputDir=..\\..\\artifacts
SetupIconFile=..\\..\\windows\\runner\\resources\\app_icon.ico
UninstallDisplayIcon={app}\\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\\..\\build\\windows\\x64\\runner\\Release\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{commondesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
