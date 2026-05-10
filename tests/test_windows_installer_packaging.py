import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
ISS_PATH = REPO_ROOT / "packaging" / "windows" / "LocalQwenSetup.iss"
BOOTSTRAP_PATH = REPO_ROOT / "install" / "windows" / "setup-bootstrap.cmd"
INSTALL_PS1_PATH = REPO_ROOT / "install" / "windows" / "install.ps1"
RELEASE_ALL_PATH = REPO_ROOT / "packaging" / "release-all.ps1"
WINDOWS_LAUNCHER_DIR = REPO_ROOT / "launcher" / "windows"
WINDOWS_COMMON_PATH = WINDOWS_LAUNCHER_DIR / "local-qwen-common.ps1"


class WindowsInstallerPackagingTests(unittest.TestCase):
    def test_inno_setup_uses_finished_page_and_embeds_hidden_bootstrap_run(self):
        content = ISS_PATH.read_text(encoding="utf-8")
        self.assertIn("DisableFinishedPage=no", content)
        self.assertNotIn("Local Qwen Installer", content)
        self.assertIn("CreateOutputMsgMemoPage", content)
        self.assertIn("CreateInputOptionPage", content)
        self.assertIn("Qwen 3.6 35B A3B IQ2_M (recommended default, about 11 GB)", content)
        self.assertIn("SelectedModelId := 'qwen36-35b-a3b-IQ2_M.gguf'", content)
        self.assertIn("-ModelId", content)
        self.assertIn("GetInstallLogPath", content)
        self.assertIn("GetInstallSummaryPath", content)
        self.assertIn("GetInstallStatusPath", content)
        self.assertIn("GetInstallScriptParameters", content)
        self.assertIn("RefreshLiveInstallUi", content)
        self.assertIn("WaitForInstallCompletion", content)
        self.assertIn("InstallActivityLabel", content)
        self.assertIn("InstallHintLabel", content)
        self.assertIn("BuildInstallActivityText", content)
        self.assertIn("CurStepChanged", content)
        self.assertIn("ssPostInstall", content)
        self.assertIn("SW_HIDE", content)
        self.assertIn("ewNoWait", content)
        self.assertIn("-StatusPath", content)
        self.assertIn("FULL INSTALL LOG", content)
        self.assertIn("Installer workspace actions finished successfully.", content)
        self.assertNotIn("[Run]", content)
        self.assertIn("CreateInputDirPage", content)
        self.assertIn("GetSelectedInstallRoot", content)
        self.assertIn("RequiredDiskCaption", content)
        self.assertIn("GetDefaultInstallRoot", content)
        self.assertNotIn("{userprofile}", content.lower())

    def test_bootstrap_script_announces_install_plan_and_waits_for_manual_close(self):
        content = BOOTSTRAP_PATH.read_text(encoding="utf-8").lower()
        self.assertIn("this installer will", content)
        self.assertIn("installation complete", content)
        self.assertIn("press any key to close this window", content)
        self.assertIn("%systemroot%\\system32\\windowspowershell\\v1.0\\powershell.exe", content)
        self.assertNotIn("\npowershell.exe -noprofile", content)
        self.assertIn("%*", content)

    def test_install_script_contains_explicit_stage_progress_markers(self):
        content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        self.assertIn("function Write-InstallOverview", content)
        self.assertIn("function Invoke-InstallStage", content)
        self.assertIn("[{0}/{1}]", content)
        self.assertIn("[string]$LogPath = \"\"", content)
        self.assertIn("[string]$SummaryPath = \"\"", content)
        self.assertIn("[string]$StatusPath = \"\"", content)
        self.assertIn("[string]$ModelId = \"\"", content)
        self.assertIn("function Write-Utf8NoBomText", content)
        self.assertIn("function Write-InstallStatus", content)
        self.assertIn("function Set-InstallStatusDetail", content)
        self.assertIn("Start-Transcript -Path $LogPath -Force", content)
        self.assertIn("Write-Utf8NoBomText -Path $defaultSummaryPath -Content $summary", content)
        self.assertIn("Write-Utf8NoBomText -Path $LogPath -Content $logContent", content)
        self.assertIn("Stop-Transcript", content)
        self.assertIn("$requestedModelChoice = $null", content)
        self.assertIn("Get-ModelChoiceById -ModelId $ModelId", content)
        self.assertIn('Write-InstallStatus -State "completed"', content)
        self.assertIn('Write-InstallStatus -State "failed"', content)

    def test_install_script_treats_ninja_as_optional_for_turboquant(self):
        content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        self.assertIn("function Ensure-OptionalCommand", content)
        self.assertIn("Ninja-build.Ninja", content)
        self.assertIn("TurboQuant build bice preskocen", content)
        self.assertIn("function Install-PortableNinja", content)
        self.assertIn("ninja/releases/latest/download/ninja-win.zip", content)

    def test_packaging_and_shortcuts_include_uninstall_entrypoints(self):
        install_content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        iss_content = ISS_PATH.read_text(encoding="utf-8")
        uninstall_content = (WINDOWS_LAUNCHER_DIR / "uninstall.ps1").read_text(encoding="utf-8")
        self.assertIn("uninstall.ps1", install_content)
        self.assertIn("Uninstall Local Qwen.lnk", install_content)
        self.assertIn("install-update.ps1", install_content)
        self.assertIn("Update Local Qwen.lnk", install_content)
        self.assertIn("Uninstallable=yes", iss_content)
        self.assertIn("Get-DesktopShortcutNames", uninstall_content)

    def test_release_script_attaches_full_fix_log_asset_and_short_summary(self):
        content = RELEASE_ALL_PATH.read_text(encoding="utf-8")
        self.assertIn("Local-Qwen-Full-Fix-Log-v$Version.txt", content)
        self.assertIn("--notes-file $releaseSummaryPath", content)
        self.assertIn("Full fix log is attached below in Assets", content)

    def test_parameterized_windows_scripts_start_with_param_block(self):
        expected = {
            "uninstall.ps1",
            "manage-models.ps1",
            "configure-settings.ps1",
            "build-turboquant.ps1",
            "launch-agent.ps1",
            "repair-app-control.ps1",
            "start-server.ps1",
            "start-opencode.ps1",
            "test-prompt.ps1",
        }
        for name in expected:
            content = (WINDOWS_LAUNCHER_DIR / name).read_text(encoding="utf-8")
            stripped = content.lstrip("\ufeff \t\r\n")
            self.assertTrue(
                stripped.startswith("param("),
                msg=f"{name} mora da pocne sa param() blokom kada koristi script parametre.",
            )

    def test_windows_opencode_launch_uses_resolver_instead_of_plain_path_lookup(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        start_opencode = (WINDOWS_LAUNCHER_DIR / "start-opencode.ps1").read_text(encoding="utf-8")
        launch_agent = (WINDOWS_LAUNCHER_DIR / "launch-agent.ps1").read_text(encoding="utf-8")
        verify_install = (WINDOWS_LAUNCHER_DIR / "verify-install.ps1").read_text(encoding="utf-8")

        self.assertIn("function Get-OpenCodeExecutable", common)
        self.assertIn("function Test-OpenCodeAvailable", common)
        self.assertIn("Get-OpenCodeExecutable", start_opencode)
        self.assertIn("Get-OpenCodeExecutable", launch_agent)
        self.assertIn("Test-OpenCodeAvailable", verify_install)
        self.assertNotIn("Get-Command opencode -ErrorAction SilentlyContinue", start_opencode)
        self.assertNotIn("Get-Command opencode -ErrorAction SilentlyContinue", launch_agent)

    def test_windows_model_download_has_progress_state_hooks(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        control_center = (WINDOWS_LAUNCHER_DIR / "control-center.ps1").read_text(encoding="utf-8")
        self.assertIn("Get-ModelDownloadProgressPath", common)
        self.assertIn("Get-ModelDownloadProgressData", common)
        self.assertIn("Clear-ModelDownloadProgress", common)
        self.assertIn("LOCAL_QWEN_INSTALL_STATUS_PATH", common)
        self.assertIn("write_install_status(payload)", common)
        self.assertIn("Refresh-ModelDownloadProgressView", control_center)
        self.assertIn("-OnTick", control_center)

    def test_model_browser_omits_empty_search_and_family_arguments(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        self.assertIn('if (-not [string]::IsNullOrWhiteSpace($Search)) {', common)
        self.assertIn('$arguments += @("--search", $Search)', common)
        self.assertIn('if (-not [string]::IsNullOrWhiteSpace($Family)) {', common)
        self.assertIn('$arguments += @("--family", $Family)', common)

    def test_model_browser_reconciles_installed_size_locally(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        self.assertIn("$sizeMap = Get-InstalledModelSizeMap", common)
        self.assertIn("if ($sizeMap.Contains($modelId)) {", common)
        self.assertIn("$model.installedSizeBytes = $installedBytes", common)
        self.assertIn("$model.installedSizeGiB = [math]::Round(($installedBytes / 1GB), 2)", common)

    def test_runtime_helpers_skip_empty_optional_arguments(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        self.assertIn("function Add-OptionalRuntimeArgument", common)
        self.assertIn("function Convert-CollectionToJsonArrayString", common)
        self.assertIn('if (-not [string]::IsNullOrWhiteSpace($Value)) {', common)
        self.assertIn('Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--profile"', common)
        self.assertIn('Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--model-id"', common)
        self.assertIn('Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--lifecycle-state"', common)
        self.assertIn('return "[]"', common)
        self.assertIn('$warningsJson = Convert-CollectionToJsonArrayString -Collection $warnings', common)

    def test_background_worker_uses_explicit_powershell_path_inside_job(self):
        control_center = (WINDOWS_LAUNCHER_DIR / "control-center.ps1").read_text(encoding="utf-8")
        self.assertIn("$powerShellExe = Get-WindowsPowerShellExe", control_center)
        self.assertIn("param($PowerShellExe, $Path, $Args)", control_center)
        self.assertIn("& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $Path @Args", control_center)

    def test_turboquant_build_can_use_local_ninja_fallback(self):
        build_script = (WINDOWS_LAUNCHER_DIR / "build-turboquant.ps1").read_text(encoding="utf-8")
        self.assertIn('Join-Path $state.installRoot "tools\\ninja\\ninja.exe"', build_script)
        self.assertIn('$ninja = Get-ToolPath "ninja"', build_script)
        self.assertIn('[Environment]::SetEnvironmentVariable("PATH", $currentPath, "Process")', build_script)
        self.assertIn('"-DCMAKE_CUDA_ARCHITECTURES=$($defaults.windowsBuild.cudaArch)"', build_script)
        self.assertIn('VsDevCmd.bat', build_script)
        self.assertIn('return "Ninja"', build_script)
        self.assertIn('Get-Command rc.exe -ErrorAction SilentlyContinue', build_script)
        self.assertIn('function Add-ToProcessPath', build_script)
        self.assertIn('function Add-ToProcessVariablePath', build_script)
        self.assertIn('function Set-StatePropertyValue', build_script)
        self.assertIn('function Get-WindowsSdkBinDirectory', build_script)
        self.assertIn('function Ensure-WindowsSdkEnvironment', build_script)
        self.assertIn('function Get-BuildCacheGenerator', build_script)
        self.assertIn('Add-ToProcessPath "$env:SystemRoot\\System32"', build_script)
        self.assertIn('Add-ToProcessPath (Get-WindowsSdkBinDirectory)', build_script)
        self.assertIn('[Environment]::SetEnvironmentVariable("WindowsSDKVersion", ($sdk.Version + "\\"), "Process")', build_script)
        self.assertIn('Add-ToProcessVariablePath -VariableName "LIB" -PathEntry (Join-Path $sdk.LibRoot $libLeaf)', build_script)
        self.assertIn('Set-StatePropertyValue -StateObject $state -Name "turboServerExe" -Value $serverExe.FullName', build_script)
        self.assertIn("Postojeci TurboQuant build cache koristi generator", build_script)

    def test_installer_replaces_existing_windows_launchers_and_support_files(self):
        install_content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        repair = (WINDOWS_LAUNCHER_DIR / "repair-install.ps1").read_text(encoding="utf-8")

        self.assertIn("function Copy-FolderContent", install_content)
        self.assertIn("function Copy-FileWithRetry", install_content)
        self.assertIn("function Stop-RunningLocalQwenProcesses", install_content)
        self.assertIn("Stop-RunningLocalQwenProcesses", install_content)
        self.assertIn("Invoke-WithRetry", install_content)
        self.assertIn("control-center.ps1", install_content)
        self.assertIn("open-control-center.vbs", install_content)
        self.assertIn("HashSet[int]", install_content)
        self.assertIn("function Test-IsAppControlWarningText", install_content)
        self.assertIn("function Test-HealthEndpointAlive", install_content)
        self.assertIn("function Get-FilteredInstallWarnings", install_content)
        self.assertIn("Invoke-RestMethod -Uri (\"http://127.0.0.1:{0}/health\" -f $Port)", install_content)
        self.assertIn('$summaryWarnings = @($script:InstallWarnings)', install_content)
        self.assertIn('$reportData = Get-Content -Raw $installReportPath | ConvertFrom-Json', install_content)
        self.assertIn("[switch]$ReplaceExisting", install_content)
        self.assertIn('Copy-FolderContent -Source (Join-Path $repoRoot "launcher\\windows") -Destination $launchersDir -ReplaceExisting', install_content)
        self.assertIn('Copy-FolderContent -Source (Join-Path $repoRoot "scripts") -Destination $scriptsDir -ReplaceExisting', install_content)
        self.assertIn('Copy-FileWithRetry -Source (Join-Path $repoRoot "version.json") -Destination (Join-Path $InstallRoot "version.json")', install_content)
        self.assertIn('Copy-FileWithRetry -Source (Join-Path $repoRoot "release-notes.txt") -Destination (Join-Path $InstallRoot "release-notes.txt")', install_content)
        self.assertIn('@{ Source = (Join-Path $baseDir "launcher\\windows"); Destination = (Join-Path $root "launchers"); Label = "launchers" }', common)
        self.assertIn('@{ Source = (Join-Path $baseDir "release-notes.txt"); Destination = (Join-Path $root "release-notes.txt"); Label = "release-notes-root" }', common)
        self.assertIn("$restoredSupport = @(Restore-BundledSupportFiles)", repair)
        self.assertIn('Convert-CollectionToJsonArrayString -Collection $found', repair)


if __name__ == "__main__":
    unittest.main()
