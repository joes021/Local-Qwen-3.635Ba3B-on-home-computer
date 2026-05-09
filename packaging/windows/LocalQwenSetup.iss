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
Uninstallable=yes
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
Filename: "{cmd}"; Parameters: "/c ""{app}\setup-bootstrap.cmd"" -InstallRoot ""{code:GetSelectedInstallRoot}"""; WorkingDir: "{app}"; Flags: waituntilterminated

[Code]
var
  InstallRootPage: TInputDirWizardPage;
  DiskInfoLabel: TNewStaticText;

const
  RequiredDiskCaption = 'Expected disk usage after a default install: about 20-25 GB.';
  RecommendedDiskCaption = 'Recommended free disk space before install: at least 35 GB.';

procedure InitializeWizard();
begin
  InstallRootPage := CreateInputDirPage(
    wpWelcome,
    'Choose LocalQwenHome install folder',
    'Select where the Local Qwen workspace should be installed',
    'Choose the folder where Local Qwen Home Computer should place models, runtime, settings and launchers. You can change this later only by reinstalling or moving the workspace manually.',
    False,
    ''
  );

  InstallRootPage.Add('');
  InstallRootPage.Values[0] := ExpandConstant('{userprofile}\LocalQwenHome');

  DiskInfoLabel := TNewStaticText.Create(InstallRootPage.Surface);
  DiskInfoLabel.Parent := InstallRootPage.Surface;
  DiskInfoLabel.Left := ScaleX(0);
  DiskInfoLabel.Top := InstallRootPage.Edits[0].Top + InstallRootPage.Edits[0].Height + ScaleY(12);
  DiskInfoLabel.Width := InstallRootPage.SurfaceWidth;
  DiskInfoLabel.Height := ScaleY(54);
  DiskInfoLabel.AutoSize := False;
  DiskInfoLabel.WordWrap := True;
  DiskInfoLabel.Caption :=
    RequiredDiskCaption + #13#10 +
    RecommendedDiskCaption + #13#10 +
    'Use Browse if you want to place LocalQwenHome on another disk or folder.';
end;

function GetSelectedInstallRoot(Param: string): string;
begin
  Result := InstallRootPage.Values[0];
end;
