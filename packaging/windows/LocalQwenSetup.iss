#ifndef MyAppName
  #define MyAppName "Local Qwen 3.635Ba3B on home computer"
#endif

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef MySetupBaseName
  #define MySetupBaseName "Local-Qwen-Setup"
#endif

[Setup]
AppId={{9C41C3B8-37D3-4C3C-BA5A-9D3D0F932BA0}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Local Qwen Home Computer
AppPublisherURL=https://github.com/joes021/Local-Qwen-3.635Ba3B-on-home-computer
DefaultDirName={autopf}\LocalQwenSetupBootstrap
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyMemo=yes
DisableReadyPage=no
DisableWelcomePage=no
DisableFinishedPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename={#MySetupBaseName}-{#MyAppVersion}
SetupIconFile=..\..\assets\icons\control-center.ico
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
Uninstallable=no
CreateAppDir=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\..\install\windows\setup-bootstrap.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\version.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\release-notes.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\install\windows\install.ps1"; DestDir: "{app}\install\windows"; Flags: ignoreversion
Source: "..\..\launcher\windows\*"; DestDir: "{app}\launcher\windows"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\assets\icons\*"; DestDir: "{app}\assets\icons"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\config\profiles\*"; DestDir: "{app}\config\profiles"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\Local Qwen Installer"; Filename: "{app}\setup-bootstrap.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\assets\icons\control-center.ico"

[Run]
Filename: "{cmd}"; Parameters: "/c ""{app}\setup-bootstrap.cmd"""; WorkingDir: "{app}"; Flags: waituntilterminated
