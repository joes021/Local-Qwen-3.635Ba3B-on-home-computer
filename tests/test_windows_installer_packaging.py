import json
import pathlib
import os
import subprocess
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
ISS_PATH = REPO_ROOT / "packaging" / "windows" / "LocalQwenSetup.iss"
BOOTSTRAP_PATH = REPO_ROOT / "install" / "windows" / "setup-bootstrap.cmd"
INSTALL_PS1_PATH = REPO_ROOT / "install" / "windows" / "install.ps1"
RELEASE_ALL_PATH = REPO_ROOT / "packaging" / "release-all.ps1"
WINDOWS_LAUNCHER_DIR = REPO_ROOT / "launcher" / "windows"
WINDOWS_COMMON_PATH = WINDOWS_LAUNCHER_DIR / "local-qwen-common.ps1"


def run_powershell_snippet(snippet: str, *, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            snippet,
        ],
        capture_output=True,
        text=True,
        env=env,
    )


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
        install_update_content = (WINDOWS_LAUNCHER_DIR / "install-update.ps1").read_text(encoding="utf-8")
        dump_ui_content = (WINDOWS_LAUNCHER_DIR / "dump-ui-text.ps1").read_text(encoding="utf-8")
        self.assertIn("uninstall.ps1", install_content)
        self.assertIn("Uninstall Local Qwen.lnk", install_content)
        self.assertIn("install-update.ps1", install_content)
        self.assertIn("Update Local Qwen.lnk", install_content)
        self.assertIn("Uninstallable=yes", iss_content)
        self.assertIn("Get-DesktopShortcutNames", uninstall_content)
        self.assertIn("$root = Get-LocalQwenStateRoot", uninstall_content)
        self.assertIn('Write-Host "Trenutna verzija: v$($info.currentVersion)"', install_update_content)
        self.assertIn('Write-Host ("Preuzet installer: {0:N2} MiB" -f ($downloadedFile.Length / 1MB))', install_update_content)
        self.assertIn('Start-Process -FilePath $targetPath -PassThru', install_update_content)
        self.assertIn("$codeRoot = Get-LocalQwenCodeRoot", dump_ui_content)
        self.assertIn("function Get-PreferredDumpStateRoot", dump_ui_content)
        self.assertIn('$installedRoot = Join-Path $env:USERPROFILE "LocalQwenHome"', dump_ui_content)
        self.assertIn("$stateRoot = Get-PreferredDumpStateRoot", dump_ui_content)
        self.assertIn('$controlCenterPath = Join-Path $stateRoot "launchers\\control-center.ps1"', dump_ui_content)

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
        configure_settings = (WINDOWS_LAUNCHER_DIR / "configure-settings.ps1").read_text(encoding="utf-8")
        repair_config = (WINDOWS_LAUNCHER_DIR / "repair-config.ps1").read_text(encoding="utf-8")

        self.assertIn("function Get-OpenCodeExecutable", common)
        self.assertIn("function Test-OpenCodeAvailable", common)
        self.assertIn("Get-OpenCodeExecutable", start_opencode)
        self.assertIn("Get-OpenCodeExecutable", launch_agent)
        self.assertIn("Test-OpenCodeAvailable", verify_install)
        self.assertIn("OPENCODE_ENABLE_EXA", start_opencode)
        self.assertIn("OPENCODE_ENABLE_EXA", launch_agent)
        self.assertNotIn("Get-Command opencode -ErrorAction SilentlyContinue", start_opencode)
        self.assertNotIn("Get-Command opencode -ErrorAction SilentlyContinue", launch_agent)
        self.assertIn("$root = Get-LocalQwenStateRoot", launch_agent)
        self.assertIn("Write-Utf8NoBomText -Path $sessionConfigPath", launch_agent)
        self.assertIn("Write-Utf8NoBomText -Path $sessionMetaPath", launch_agent)
        self.assertIn('$settingsPath = Join-Path (Get-LocalQwenStateRoot) "state\\settings.json"', configure_settings)
        self.assertIn("Join-Path (Get-LocalQwenStateRoot) 'state\\settings.json'", repair_config)
        self.assertIn("$modelPath = Get-StateModelFilePath -State $state", verify_install)
        self.assertIn("Join-Path (Get-LocalQwenStateRoot) \"state\\install-report.json\"", verify_install)

    def test_opencode_config_enables_websearch_and_webfetch(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        linux_configure = (REPO_ROOT / "launcher" / "linux" / "configure-settings.sh").read_text(encoding="utf-8")
        self.assertIn('webfetch', common)
        self.assertIn('websearch', common)
        self.assertIn('permission["webfetch"] = "allow"', linux_configure)
        self.assertIn('permission["websearch"] = "allow"', linux_configure)

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
        self.assertIn('$arguments.Add("--search") | Out-Null', common)
        self.assertIn('$arguments.Add($Search) | Out-Null', common)
        self.assertIn('if (-not [string]::IsNullOrWhiteSpace($Family)) {', common)
        self.assertIn('$arguments.Add("--family") | Out-Null', common)
        self.assertIn('$arguments.Add($Family) | Out-Null', common)
        self.assertIn('$arguments = [System.Collections.Generic.List[string]]::new()', common)
        self.assertIn('return Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())', common)
        self.assertIn('Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--installed-model-ids"', common)

    def test_model_browser_reconciles_installed_size_locally(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        self.assertIn("$sizeMap = Get-InstalledModelSizeMap", common)
        self.assertIn('$arguments = [System.Collections.Generic.List[string]]::new()', common)
        self.assertIn("if ($sizeMap.Contains($modelId)) {", common)
        self.assertIn("$model.installedSizeBytes = $installedBytes", common)
        self.assertIn("$model.installedSizeGiB = [math]::Round(($installedBytes / 1GB), 2)", common)
        self.assertIn("function Get-CustomModelsRegistryPath", common)
        self.assertIn("function Get-EffectiveDefaultsPath", common)
        self.assertIn("function Get-InstallSummaryPath", common)
        self.assertIn("function Import-LocalGgufModel", common)
        self.assertIn("function Add-HuggingFaceCustomModel", common)
        self.assertIn('$payload = Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())', common)

    def test_manage_models_groups_recommended_choice_ahead_of_can_run_bucket(self):
        content = (WINDOWS_LAUNCHER_DIR / "manage-models.ps1").read_text(encoding="utf-8")
        self.assertIn('"Preporuceni za ovu masinu" = @($browser.models | Where-Object { $_.recommended -or $_.fitGroup -eq "recommended" })', content)
        self.assertIn('"Moze da radi uz kompromis" = @($browser.models | Where-Object { $_.fitGroup -eq "canRun" -and -not $_.recommended })', content)

    def test_runtime_helpers_skip_empty_optional_arguments(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        self.assertIn("function Add-OptionalRuntimeArgument", common)
        self.assertIn("function Convert-CollectionToJsonArrayString", common)
        self.assertIn("function Convert-CollectionToCliListArgument", common)
        self.assertIn('if (-not [string]::IsNullOrWhiteSpace($Value)) {', common)
        self.assertIn('Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--profile"', common)
        self.assertIn('Add-OptionalRuntimeArgument -ArgumentList $arguments -Flag "--model-id"', common)
        self.assertIn('$arguments.Add("--lifecycle-state") | Out-Null', common)
        self.assertIn('return Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())', common)
        self.assertIn('return "[]"', common)
        self.assertIn('$warningsJson = Convert-CollectionToCliListArgument -Collection $warnings', common)

    def test_background_worker_uses_explicit_powershell_path_inside_job(self):
        control_center = (WINDOWS_LAUNCHER_DIR / "control-center.ps1").read_text(encoding="utf-8")
        self.assertIn("$powerShellExe = Get-WindowsPowerShellExe", control_center)
        self.assertIn("param($PowerShellExe, $Path, $Args)", control_center)
        self.assertIn("& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $Path @Args", control_center)

    def test_turboquant_build_can_use_local_ninja_fallback(self):
        build_script = (WINDOWS_LAUNCHER_DIR / "build-turboquant.ps1").read_text(encoding="utf-8")
        self.assertIn('function Stop-RunningLlamaServerProcesses', build_script)
        self.assertIn('Stop-RunningLlamaServerProcesses', build_script)
        self.assertIn('Get-Process llama-server -ErrorAction SilentlyContinue', build_script)
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
        self.assertIn('Convert-CollectionToCliListArgument -Collection $found', repair)

    def test_windows_common_can_fall_back_to_installed_localqwenhome_when_repo_has_no_state(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        self.assertIn("function Get-LocalQwenCodeRoot", common)
        self.assertIn("function Get-LocalQwenStateRoot", common)
        self.assertIn("function Get-StateModelFilePath", common)
        self.assertIn("return Get-LocalQwenCodeRoot", common)
        self.assertIn('$installedRoot = Join-Path $env:USERPROFILE "LocalQwenHome"', common)
        self.assertIn('if (Test-Path (Join-Path $codeRoot "state\\install-state.json")) {', common)
        self.assertIn("return $codeRoot", common)
        self.assertIn('if (Test-Path (Join-Path $installedRoot "state\\install-state.json")) {', common)
        self.assertIn('return (Resolve-Path $installedRoot).Path', common)
        self.assertIn('if ($State.PSObject.Properties["modelPath"] -and -not [string]::IsNullOrWhiteSpace([string]$State.modelPath)) {', common)
        self.assertIn('$state.modelPath = $resolvedModelPath', common)

    def test_import_local_gguf_model_registers_custom_model_without_touching_real_profile(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_user = temp_path / "fake-user"
            install_root = fake_user / "LocalQwenHome"
            (install_root / "state").mkdir(parents=True)
            (install_root / "models").mkdir(parents=True)
            (install_root / "state" / "install-state.json").write_text(
                json.dumps(
                    {
                        "installRoot": str(install_root),
                        "modelFile": str(install_root / "models" / "baseline.gguf"),
                        "modelId": "baseline.gguf",
                        "port": 8091,
                    }
                ),
                encoding="utf-8",
            )
            local_model = temp_path / "sample.gguf"
            local_model.write_text("GGUFTEST", encoding="ascii")
            env = os.environ.copy()
            env["USERPROFILE"] = str(fake_user)
            snippet = f"""
            . '{WINDOWS_COMMON_PATH}'
            $model = Import-LocalGgufModel -SourcePath '{local_model}' -Label 'Imported sample' -Family 'Custom'
            $catalog = @(Get-ModelCatalog)
            $found = $catalog | Where-Object {{ $_.id -eq 'sample.gguf' }} | Select-Object -First 1
            [pscustomobject]@{{
              imported = [bool]$model
              found = [bool]$found
              label = if ($found) {{ $found.label }} else {{ $null }}
              copied = Test-Path '{install_root / "models" / "sample.gguf"}'
            }} | ConvertTo-Json -Depth 5
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertTrue(payload["imported"])
            self.assertTrue(payload["found"])
            self.assertEqual(payload["label"], "Imported sample")
            self.assertTrue(payload["copied"])

    def test_add_huggingface_custom_model_registers_entry_without_touching_real_profile(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_user = temp_path / "fake-user"
            install_root = fake_user / "LocalQwenHome"
            (install_root / "state").mkdir(parents=True)
            (install_root / "state" / "install-state.json").write_text(
                json.dumps(
                    {
                        "installRoot": str(install_root),
                        "modelFile": str(install_root / "models" / "baseline.gguf"),
                        "modelId": "baseline.gguf",
                        "port": 8091,
                    }
                ),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["USERPROFILE"] = str(fake_user)
            snippet = f"""
            . '{WINDOWS_COMMON_PATH}'
            $model = Add-HuggingFaceCustomModel -Repo 'Qwen/Qwen3-8B-GGUF' -FileName 'Qwen3-8B-Q4_K_M.gguf' -Label 'HF sample' -Family 'Qwen'
            $catalog = @(Get-ModelCatalog)
            $found = $catalog | Where-Object {{ $_.label -eq 'HF sample' }} | Select-Object -First 1
            [pscustomobject]@{{
              added = [bool]$model
              found = [bool]$found
              modelId = if ($found) {{ $found.id }} else {{ $null }}
              source = if ($found) {{ $found.source }} else {{ $null }}
            }} | ConvertTo-Json -Depth 5
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertTrue(payload["added"])
            self.assertTrue(payload["found"])
            self.assertEqual(payload["modelId"], "Qwen3-8B-Q4_K_M.gguf")
            self.assertEqual(payload["source"], "Qwen/Qwen3-8B-GGUF")

    def test_model_browser_supports_install_state_with_model_path_without_model_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_user = temp_path / "fake-user"
            install_root = fake_user / "LocalQwenHome"
            (install_root / "state").mkdir(parents=True)
            (install_root / "models").mkdir(parents=True)
            (install_root / "state" / "install-state.json").write_text(
                json.dumps(
                    {
                        "installRoot": str(install_root),
                        "modelPath": str(install_root / "models" / "Qwen3-8B-Q4_K_M.gguf"),
                        "modelId": "Qwen3-8B-Q4_K_M.gguf",
                        "port": 8091,
                    }
                ),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["USERPROFILE"] = str(fake_user)
            snippet = f"""
            . '{WINDOWS_COMMON_PATH}'
            Add-HuggingFaceCustomModel -Repo 'repo/demo' -FileName 'demo.gguf' -Label 'Demo HF' -Family 'Custom' | Out-Null
            $payload = Get-ModelBrowserPayload
            [pscustomobject]@{{
              hasCustom = [bool](@($payload.models | Where-Object {{ $_.id -eq 'demo.gguf' }}).Count)
              currentModelPath = Get-StateModelFilePath -State (Get-InstallState)
            }} | ConvertTo-Json -Depth 5
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertTrue(payload["hasCustom"])
            self.assertTrue(payload["currentModelPath"].endswith("Qwen3-8B-Q4_K_M.gguf"))
            snippet = f"""
            . '{WINDOWS_COMMON_PATH}'
            Add-HuggingFaceCustomModel -Repo 'repo/demo' -FileName 'demo.gguf' -Label 'Demo HF' -Family 'Custom' | Out-Null
            $payload = Get-ModelBrowserPayload
            $found = $payload.models | Where-Object {{ $_.id -eq 'demo.gguf' }} | Select-Object -First 1
            [pscustomobject]@{{
              fitGroup = $found.fitGroup
              speed = $found.speedEstimateLabel
              diskNeeded = $found.diskNeededGiB
              hasEnoughDisk = $found.hasEnoughDisk
            }} | ConvertTo-Json -Depth 5
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertEqual(payload["fitGroup"], "unknown")
            self.assertEqual(payload["speed"], "nepoznato")
            self.assertIsNone(payload["diskNeeded"])
            self.assertIsNone(payload["hasEnoughDisk"])
            self.assertNotIn("best-for-speed", completed.stdout)

    def test_repair_runtime_uses_state_root_for_launchers(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "repair-runtime.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn("Get-LocalQwenStateRoot", text)
        self.assertNotIn('Join-Path (Get-LocalQwenRoot) "launchers"', text)

    def test_uninstall_keep_models_does_not_emit_raw_boolean_lines(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "uninstall.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn("[void](Remove-PathIfExists", text)

    def test_windows_installer_excludes_pycache_and_pyc(self):
        iss_path = REPO_ROOT / "packaging" / "windows" / "LocalQwenSetup.iss"
        text = iss_path.read_text(encoding="utf-8")

        self.assertIn('Excludes: "__pycache__\\*,*.pyc"', text)

    def test_dump_ui_text_prefers_installed_release_notes_and_version(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "dump-ui-text.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn('Join-Path $stateRoot "release-notes.txt"', text)
        self.assertIn('Join-Path $stateRoot "version.json"', text)

    def test_export_diagnostics_includes_repair_summary_and_token_history(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "local-qwen-common.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn('state\\repair-summary.json', text)
        self.assertIn('state\\token-metrics-history.json', text)
        self.assertIn('release-notes.txt', text)


if __name__ == "__main__":
    unittest.main()
