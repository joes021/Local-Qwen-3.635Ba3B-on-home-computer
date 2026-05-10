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
DisableFinishedPage=no
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
Source: "..\..\scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "__pycache__\*,*.pyc"
Source: "..\..\assets\icons\*"; DestDir: "{app}\assets\icons"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\config\profiles\*"; DestDir: "{app}\config\profiles"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
var
  InstallRootPage: TInputDirWizardPage;
  ModelPage: TInputOptionWizardPage;
  DiskInfoLabel: TNewStaticText;
  ResultPage: TOutputMsgMemoWizardPage;
  InstallActivityLabel: TNewStaticText;
  InstallHintLabel: TNewStaticText;
  InstallLogPath: string;
  InstallSummaryPath: string;
  InstallStatusPath: string;
  InstallRunExitCode: Integer;
  InstallRunStarted: Boolean;

const
  RequiredDiskCaption = 'Expected disk usage after a default install: about 20-25 GB.';
  RecommendedDiskCaption = 'Recommended free disk space before install: at least 35 GB.';

function GetDefaultInstallRoot(): string;
var
  UserProfile: string;
begin
  UserProfile := GetEnv('USERPROFILE');
  if UserProfile = '' then
    UserProfile := ExpandConstant('{sd}\Users\Default');
  Result := AddBackslash(UserProfile) + 'LocalQwenHome';
end;

procedure InitializeWizard();
begin
  InstallLogPath := ExpandConstant('{tmp}\LocalQwenSetup-install.log');
  InstallSummaryPath := ExpandConstant('{tmp}\LocalQwenSetup-summary.txt');
  InstallStatusPath := ExpandConstant('{tmp}\LocalQwenSetup-status.ini');
  InstallRunExitCode := 0;
  InstallRunStarted := False;
  InstallRootPage := CreateInputDirPage(
    wpWelcome,
    'Choose LocalQwenHome install folder',
    'Select where the Local Qwen workspace should be installed',
    'Choose the folder where Local Qwen Home Computer should place models, runtime, settings and launchers. You can change this later only by reinstalling or moving the workspace manually.',
    False,
    ''
  );

  InstallRootPage.Add('');
  InstallRootPage.Values[0] := GetDefaultInstallRoot();

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

  ModelPage := CreateInputOptionPage(
    InstallRootPage.ID,
    'Choose default model',
    'Select which GGUF model Local Qwen should download during setup',
    'Default is the recommended Qwen 3.6 35B A3B IQ2_M model around 10-11 GB. Smaller and larger alternatives are available below.',
    False,
    False
  );
  ModelPage.Add('Qwen 3.6 35B A3B IQ2_M (recommended default, about 11 GB)');
  ModelPage.Add('Qwen2.5 Coder 7B Q5_K_M (smaller coding-focused option, about 5.7 GB)');
  ModelPage.Add('Gemma 3 4B Q4_K_M (smallest fast option, about 2.5 GB)');
  ModelPage.Add('Llama 3.1 8B Q4_K_M (general smaller fallback, about 4.9 GB)');
  ModelPage.Add('Qwen 3.6 35B A3B Q4_K_M (larger quality option, about 20.5 GB)');
  ModelPage.Values[0] := True;

  ResultPage := CreateOutputMsgMemoPage(
    wpInstalling,
    'Review installation result',
    'Setup finished the Local Qwen workspace actions.',
    'Read the summary and full log below before pressing Finish. You can select and copy any part of the log.',
    ''
  );

  InstallActivityLabel := TNewStaticText.Create(WizardForm.StatusLabel.Parent);
  InstallActivityLabel.Parent := WizardForm.StatusLabel.Parent;
  InstallActivityLabel.Left := WizardForm.StatusLabel.Left;
  InstallActivityLabel.Top := WizardForm.StatusLabel.Top + WizardForm.StatusLabel.Height + ScaleY(12);
  InstallActivityLabel.Width := WizardForm.StatusLabel.Width;
  InstallActivityLabel.Height := ScaleY(54);
  InstallActivityLabel.AutoSize := False;
  InstallActivityLabel.WordWrap := True;
  InstallActivityLabel.Caption := 'Setup ce ovde prikazivati trenutni korak, aktivnost i detalje model downloada.';

  InstallHintLabel := TNewStaticText.Create(WizardForm.StatusLabel.Parent);
  InstallHintLabel.Parent := WizardForm.StatusLabel.Parent;
  InstallHintLabel.Left := WizardForm.StatusLabel.Left;
  InstallHintLabel.Top := InstallActivityLabel.Top + InstallActivityLabel.Height + ScaleY(6);
  InstallHintLabel.Width := WizardForm.StatusLabel.Width;
  InstallHintLabel.Height := ScaleY(32);
  InstallHintLabel.AutoSize := False;
  InstallHintLabel.WordWrap := True;
  InstallHintLabel.Caption := 'Ako se preuzima model, ovde ces videti procenat, brzinu i ETA dok setup radi u pozadini.';
end;

function GetSelectedModelId(): string;
var
  SelectedModelId: string;
begin
  SelectedModelId := 'qwen36-35b-a3b-IQ2_M.gguf';
  if ModelPage.Values[1] then
    SelectedModelId := 'qwen2.5-coder-7b-instruct-q5_k_m.gguf'
  else if ModelPage.Values[2] then
    SelectedModelId := 'gemma-3-4b-it-Q4_K_M.gguf'
  else if ModelPage.Values[3] then
    SelectedModelId := 'Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf'
  else if ModelPage.Values[4] then
    SelectedModelId := 'Qwen3.6-35B-A3B-Q4_K_M.gguf';

  Result := SelectedModelId;
end;

function GetInstallScriptParameters(): string;
begin
  Result :=
    '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\install\windows\install.ps1') + '"' +
    ' -InstallRoot "' + InstallRootPage.Values[0] + '"' +
    ' -DesktopFolder "' + ExpandConstant('{userdesktop}') + '"' +
    ' -ModelId "' + GetSelectedModelId() + '"' +
    ' -StatusPath "' + InstallStatusPath + '"' +
    ' -LogPath "' + InstallLogPath + '"' +
    ' -SummaryPath "' + InstallSummaryPath + '"';
end;

function GetSelectedInstallRoot(Param: string): string;
begin
  Result := InstallRootPage.Values[0];
end;

function GetInstallLogPath(Param: string): string;
begin
  Result := InstallLogPath;
end;

function GetInstallSummaryPath(Param: string): string;
begin
  Result := InstallSummaryPath;
end;

function GetInstallStatusPath(Param: string): string;
begin
  Result := InstallStatusPath;
end;

function GetInstallerStateValue(const Key: string): string;
begin
  if not FileExists(InstallStatusPath) then begin
    Result := '';
    exit;
  end;

  Result := Trim(GetIniString('status', Key, '', InstallStatusPath));
end;

function FormatEtaText(const RawSeconds: string): string;
var
  TotalSeconds: Integer;
  Hours: Integer;
  Minutes: Integer;
  Seconds: Integer;
begin
  Result := '';
  if RawSeconds = '' then
    exit;

  TotalSeconds := StrToIntDef(RawSeconds, -1);
  if TotalSeconds < 0 then
    exit;

  Hours := TotalSeconds div 3600;
  Minutes := (TotalSeconds mod 3600) div 60;
  Seconds := TotalSeconds mod 60;
  if Hours > 0 then
    Result := IntToStr(Hours) + ' h ' + IntToStr(Minutes) + ' min'
  else if Minutes > 0 then
    Result := IntToStr(Minutes) + ' min ' + IntToStr(Seconds) + ' s'
  else
    Result := IntToStr(Seconds) + ' s';
end;

function GetProgressPercentValue(const RawValue: string): Extended;
begin
  Result := -1.0;
  if RawValue = '' then
    exit;
  try
    Result := StrToFloat(RawValue);
  except
    Result := -1.0;
  end;
end;

function BuildInstallActivityText(): string;
var
  StageNumber: string;
  TotalStages: string;
  StageName: string;
  DetailText: string;
  ActivityType: string;
  ProgressPercent: string;
  DownloadedGiB: string;
  TotalGiB: string;
  SpeedMBps: string;
  EtaSeconds: string;
  SourceText: string;
  ModelStatus: string;
begin
  StageNumber := GetInstallerStateValue('stageNumber');
  TotalStages := GetInstallerStateValue('totalStages');
  StageName := GetInstallerStateValue('stageName');
  DetailText := GetInstallerStateValue('detail');
  ActivityType := GetInstallerStateValue('activityType');
  ProgressPercent := GetInstallerStateValue('progressPercent');
  DownloadedGiB := GetInstallerStateValue('downloadedGiB');
  TotalGiB := GetInstallerStateValue('totalGiB');
  SpeedMBps := GetInstallerStateValue('speedMBps');
  EtaSeconds := GetInstallerStateValue('etaSeconds');
  SourceText := GetInstallerStateValue('source');
  ModelStatus := GetInstallerStateValue('modelStatus');

  Result := '';
  if (StageNumber <> '') and (TotalStages <> '') then
    Result := Result + 'Korak [' + StageNumber + '/' + TotalStages + ']';
  if StageName <> '' then begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + StageName;
  end;
  if DetailText <> '' then begin
    if Result <> '' then
      Result := Result + #13#10;
    Result := Result + DetailText;
  end;
  if ActivityType = 'model-download' then begin
    Result := Result + #13#10 + 'Download: ';
    if ProgressPercent <> '' then
      Result := Result + ProgressPercent + '%'
    else
      Result := Result + 'u toku';
    if (DownloadedGiB <> '') and (TotalGiB <> '') then
      Result := Result + ' | ' + DownloadedGiB + ' / ' + TotalGiB + ' GiB';
    if SpeedMBps <> '' then
      Result := Result + ' | ' + SpeedMBps + ' MB/s';
    if EtaSeconds <> '' then
      Result := Result + ' | ETA ' + FormatEtaText(EtaSeconds);
    if SourceText <> '' then
      Result := Result + ' | izvor ' + SourceText;
    if ModelStatus <> '' then
      Result := Result + ' | status ' + ModelStatus;
  end;
end;

function BuildInstallHintText(): string;
var
  ActivityType: string;
begin
  ActivityType := GetInstallerStateValue('activityType');
  if ActivityType = 'model-download' then
    Result := 'Model se preuzima. Nemoj gasiti installer dok se procenat, brzina i ETA menjaju.'
  else if ActivityType = 'turboquant' then
    Result := 'TurboQuant build moze potrajati duze. Warning ili fallback ce biti prikazani na kraju.'
  else if ActivityType = 'opencode' then
    Result := 'OpenCode proverava ili osvezava CLI paket. To nekad traje malo duze bez velikog pomeranja progres bara.'
  else
    Result := 'Setup je aktivan. Ovaj blok se osvezava kako prelazi kroz workspace, runtime, model i OpenCode tok.';
end;

procedure RefreshLiveInstallUi();
var
  StageNumber: Integer;
  ProgressPercent: Extended;
  GaugeValue: Integer;
begin
  InstallActivityLabel.Caption := BuildInstallActivityText();
  InstallHintLabel.Caption := BuildInstallHintText();

  StageNumber := StrToIntDef(GetInstallerStateValue('stageNumber'), 0);
  ProgressPercent := GetProgressPercentValue(GetInstallerStateValue('progressPercent'));
  GaugeValue := 0;
  if StageNumber > 0 then
    GaugeValue := (StageNumber - 1) * 100;
  if ProgressPercent >= 0 then
    GaugeValue := GaugeValue + Round(ProgressPercent)
  else if StageNumber > 0 then
    GaugeValue := GaugeValue + 35;

  if GaugeValue < 0 then
    GaugeValue := 0;
  if GaugeValue > 1000 then
    GaugeValue := 1000;

  WizardForm.ProgressGauge.Max := 1000;
  WizardForm.ProgressGauge.Position := GaugeValue;
  WizardForm.StatusLabel.Caption := 'Configuring LocalQwenHome workspace, runtime, model and OpenCode...';
  WizardForm.StatusLabel.Update;
  InstallActivityLabel.Update;
  InstallHintLabel.Update;
  WizardForm.ProgressGauge.Update;
end;

procedure WaitForInstallCompletion();
var
  CurrentState: string;
  PollCount: Integer;
begin
  PollCount := 0;
  while True do begin
    RefreshLiveInstallUi();
    CurrentState := Lowercase(GetInstallerStateValue('state'));
    if (CurrentState = 'completed') or (CurrentState = 'failed') then
      break;
    if PollCount > 72000 then begin
      InstallRunExitCode := -2;
      break;
    end;
    PollCount := PollCount + 1;
    Sleep(300);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  SummaryText: AnsiString;
  LogText: AnsiString;
  HeaderText: string;
begin
  if CurPageID = ResultPage.ID then begin
    SummaryText := '';
    LogText := '';

    if FileExists(InstallSummaryPath) then
      LoadStringFromFile(InstallSummaryPath, SummaryText);

    if FileExists(InstallLogPath) then
      LoadStringFromFile(InstallLogPath, LogText);

    if SummaryText = '' then
      SummaryText := 'Installation summary is not available.';

    if LogText = '' then
      LogText := 'Installation log is not available.' + #13#10 +
        'Expected path: ' + InstallLogPath;

    HeaderText := '';
    if InstallRunStarted then begin
      if InstallRunExitCode = 0 then
        HeaderText := 'Installer workspace actions finished successfully.'
      else
        HeaderText := 'Installer workspace actions finished with exit code ' + IntToStr(InstallRunExitCode) + '.';
    end else begin
      HeaderText := 'Installer workspace actions were not started.';
    end;

    ResultPage.RichEditViewer.Text :=
      HeaderText + #13#10 + #13#10 +
      SummaryText + #13#10 + #13#10 +
      '----------------------------------------' + #13#10 +
      'FULL INSTALL LOG' + #13#10 +
      '----------------------------------------' + #13#10 +
      LogText;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Executed: Boolean;
begin
  if CurStep = ssPostInstall then begin
    InstallRunStarted := True;
    DeleteFile(InstallLogPath);
    DeleteFile(InstallSummaryPath);
    DeleteFile(InstallStatusPath);
    WizardForm.StatusLabel.Caption := 'Configuring LocalQwenHome workspace, runtime, model and OpenCode...';
    InstallActivityLabel.Caption := 'Pokrecem LocalQwenHome install skriptu...';
    InstallHintLabel.Caption := 'Prvi detalji ce se pojaviti cim install skripta zapise status.';
    Executed := Exec(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      GetInstallScriptParameters(),
      ExpandConstant('{app}'),
      SW_HIDE,
      ewNoWait,
      ResultCode
    );
    if Executed then begin
      WaitForInstallCompletion();
      if Lowercase(GetInstallerStateValue('state')) = 'completed' then
        InstallRunExitCode := 0
      else if InstallRunExitCode = 0 then
        InstallRunExitCode := 1;
    end else
      InstallRunExitCode := -1;
  end;
end;
