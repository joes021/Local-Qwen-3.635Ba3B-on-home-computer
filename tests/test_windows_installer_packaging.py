import json
import pathlib
import os
import subprocess
import tempfile
import time
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
ISS_PATH = REPO_ROOT / "packaging" / "windows" / "LocalQwenSetup.iss"
BOOTSTRAP_PATH = REPO_ROOT / "install" / "windows" / "setup-bootstrap.cmd"
INSTALL_PS1_PATH = REPO_ROOT / "install" / "windows" / "install.ps1"
RELEASE_ALL_PATH = REPO_ROOT / "packaging" / "release-all.ps1"
WINDOWS_LAUNCHER_DIR = REPO_ROOT / "launcher" / "windows"
WINDOWS_COMMON_PATH = WINDOWS_LAUNCHER_DIR / "local-qwen-common.ps1"
LINUX_BUILD_WRAPPER_PATH = REPO_ROOT / "packaging" / "linux" / "build-run-package.ps1"


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


def to_git_bash_path(path: pathlib.Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    suffix = resolved.as_posix()[2:]
    return f"/mnt/{drive}{suffix}"


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
        start_server_content = (WINDOWS_LAUNCHER_DIR / "start-server.ps1").read_text(encoding="utf-8")
        dump_ui_content = (WINDOWS_LAUNCHER_DIR / "dump-ui-text.ps1").read_text(encoding="utf-8")
        export_diagnostics_content = (WINDOWS_LAUNCHER_DIR / "export-diagnostics.ps1").read_text(encoding="utf-8")
        common_content = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        self.assertIn("uninstall.ps1", install_content)
        self.assertIn("Uninstall Local Qwen.lnk", install_content)
        self.assertIn("install-update.ps1", install_content)
        self.assertIn("Update Local Qwen.lnk", install_content)
        self.assertIn("Uninstallable=yes", iss_content)
        self.assertIn("Get-DesktopShortcutNames", uninstall_content)
        self.assertIn("$root = Get-LocalQwenStateRoot", uninstall_content)
        self.assertIn('Write-Output "Trenutna verzija: v$($info.currentVersion)"', install_update_content)
        self.assertIn('Write-Output ("Preuzet installer: {0:N2} MiB" -f ($downloadedFile.Length / 1MB))', install_update_content)
        self.assertIn('Start-Process -FilePath $targetPath -PassThru', install_update_content)
        self.assertIn("$codeRoot = Get-LocalQwenCodeRoot", dump_ui_content)
        self.assertIn("function Get-PreferredDumpStateRoot", dump_ui_content)
        self.assertIn('$installedRoot = Join-Path $env:USERPROFILE "LocalQwenHome"', dump_ui_content)
        self.assertIn("$stateRoot = Get-PreferredDumpStateRoot", dump_ui_content)
        self.assertIn('$controlCenterPath = Join-Path $stateRoot "launchers\\control-center.ps1"', dump_ui_content)
        self.assertIn('Write-Output "llama.cpp je pokrenut na http://127.0.0.1:$($state.port)"', start_server_content)
        self.assertIn('Write-Output "Pokretanje nije potvrdjeno u roku od $WaitSeconds sekundi. Pogledaj log:"', start_server_content)
        self.assertIn('throw "Diagnostics bundle nije pronadjen posle export-a: $bundle"', export_diagnostics_content)
        self.assertIn('Write-Output ("Velicina bundle-a: {0:N2} MiB" -f ($bundleInfo.Length / 1MB))', export_diagnostics_content)
        self.assertIn('Remove-Item -LiteralPath $bundleDir -Recurse -Force -ErrorAction SilentlyContinue', common_content)

    def test_linux_packaging_has_powershell_wrapper_for_windows_hosts(self):
        content = LINUX_BUILD_WRAPPER_PATH.read_text(encoding="utf-8")
        self.assertIn('Join-Path $scriptRoot "build-run-installer.sh"', content)
        self.assertIn('$shellRelativeScript = "packaging/linux/build-run-installer.sh"', content)
        self.assertIn('Get-Content (Join-Path $repoRoot "version.json") -Raw | ConvertFrom-Json', content)
        self.assertIn('Push-Location $repoRoot', content)
        self.assertIn('& bash @arguments', content)
        self.assertIn('throw "Linux installer build nije uspeo (exit $LASTEXITCODE)."', content)

    def test_linux_run_package_prefers_gui_wizard_but_keeps_tui_fallback(self):
        build_script = (REPO_ROOT / "packaging" / "linux" / "build-run-installer.sh").read_text(encoding="utf-8")
        gui_script = (REPO_ROOT / "install" / "linux" / "installer-gui.sh").read_text(encoding="utf-8")
        tui_script = (REPO_ROOT / "install" / "linux" / "installer-tui.sh").read_text(encoding="utf-8")

        self.assertIn('installer-gui.sh', build_script)
        self.assertIn('cp "$REPO_ROOT/release-notes.txt" "$PAYLOAD_DIR/"', build_script)
        self.assertIn('WAYLAND_DISPLAY', build_script)
        self.assertIn('exec bash "$SCRIPT_DIR/install/linux/installer-tui.sh" "$@"', build_script)
        self.assertIn('command -v zenity', gui_script)
        self.assertIn('sudo apt-get install -y zenity', gui_script)
        self.assertIn('installer-gui.sh") --skip-zenity-bootstrap', gui_script)
        self.assertIn('pick_terminal()', gui_script)
        self.assertIn('launch_script_in_terminal', gui_script)
        self.assertIn('zenity --entry', gui_script)
        self.assertIn('zenity --list', gui_script)
        self.assertIn('exec bash "$TUI_SCRIPT"', gui_script)
        self.assertIn('LOCAL_QWEN_INSTALLER_TARGET_SCRIPT', tui_script)
        self.assertIn('Potvrdi instalaciju? y/n', tui_script)

    def test_linux_tui_validates_inputs_and_runs_target_script(self):
        script_path = REPO_ROOT / "install" / "linux" / "installer-tui.sh"
        bash_script_path = to_git_bash_path(script_path)
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            output_path = temp_path / "payload.json"
            helper_path = temp_path / "capture-install.sh"
            helper_path.write_bytes(
                (
                    "\n".join(
                        [
                            "#!/usr/bin/env bash",
                            "set -euo pipefail",
                            "python3 - <<'PY' \"$LOCAL_QWEN_INSTALLER_TARGET_OUTPUT\"",
                            "import json, os, sys",
                            "payload = {",
                            "  'INSTALL_ROOT': os.environ.get('INSTALL_ROOT'),",
                            "  'PROFILE': os.environ.get('PROFILE'),",
                            "  'CONTEXT_SIZE': os.environ.get('CONTEXT_SIZE'),",
                            "  'MAX_OUTPUT_TOKENS': os.environ.get('MAX_OUTPUT_TOKENS'),",
                            "  'BUILD_STEPS': os.environ.get('BUILD_STEPS'),",
                            "  'PLAN_STEPS': os.environ.get('PLAN_STEPS'),",
                            "  'GENERAL_STEPS': os.environ.get('GENERAL_STEPS'),",
                            "  'EXPLORE_STEPS': os.environ.get('EXPLORE_STEPS'),",
                            "  'WORKING_DIRECTORY': os.environ.get('WORKING_DIRECTORY'),",
                            "  'SKIP_MODEL_DOWNLOAD': os.environ.get('SKIP_MODEL_DOWNLOAD'),",
                            "  'SKIP_RUNTIME_BUILD': os.environ.get('SKIP_RUNTIME_BUILD'),",
                            "}",
                            "with open(sys.argv[1], 'w', encoding='utf-8') as handle:",
                            "    json.dump(payload, handle)",
                            "PY",
                            "",
                        ]
                    )
                ).encode("utf-8")
            )
            os.chmod(helper_path, 0o755)

            answers = "\n".join(
                [
                    "y",
                    "/tmp/local-qwen-home",
                    "fast",
                    "balanced",
                    "abc",
                    "262144",
                    "8192",
                    "120",
                    "80",
                    "100",
                    "sixty",
                    "60",
                    "workdir",
                    "/tmp/workdir",
                    "y",
                    "y",
                    "y",
                ]
            ) + "\n"

            completed = subprocess.run(
                [
                    "bash",
                    "-lc",
                    (
                        f"export LOCAL_QWEN_INSTALLER_TARGET_SCRIPT='{to_git_bash_path(helper_path)}'; "
                        f"export LOCAL_QWEN_INSTALLER_TARGET_OUTPUT='{to_git_bash_path(output_path)}'; "
                        f"printf '{answers.replace(chr(10), r'\\n')}' | bash '{bash_script_path}'"
                    ),
                ],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=60,
            )

            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            self.assertTrue(output_path.exists(), msg=completed.stdout + completed.stderr)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["INSTALL_ROOT"], "/tmp/local-qwen-home")
            self.assertEqual(payload["PROFILE"], "balanced")
            self.assertEqual(payload["CONTEXT_SIZE"], "262144")
            self.assertEqual(payload["EXPLORE_STEPS"], "60")
            self.assertEqual(payload["WORKING_DIRECTORY"], "/tmp/workdir")
            self.assertEqual(payload["SKIP_MODEL_DOWNLOAD"], "0")
            self.assertEqual(payload["SKIP_RUNTIME_BUILD"], "0")
            self.assertIn("Unos 'y' izgleda kao potvrda", completed.stderr)
            self.assertIn("Dozvoljene vrednosti su: speed balanced video", completed.stderr)
            self.assertIn("Ovde je potreban pozitivan ceo broj.", completed.stderr)
            self.assertIn("Putanja treba da pocinje sa /, ~/ ili ./ .", completed.stderr)

    def test_linux_install_script_supports_smoke_mode_and_release_notes_fallback(self):
        install_script = (REPO_ROOT / "install" / "linux" / "install.sh").read_text(encoding="utf-8")
        self.assertIn('LOCAL_QWEN_SKIP_PACKAGE_INSTALL="${LOCAL_QWEN_SKIP_PACKAGE_INSTALL:-0}"', install_script)
        self.assertIn('LOCAL_QWEN_SKIP_SOURCE_CLONE="${LOCAL_QWEN_SKIP_SOURCE_CLONE:-0}"', install_script)
        self.assertIn('LOCAL_QWEN_SKIP_OPENCODE_INSTALL="${LOCAL_QWEN_SKIP_OPENCODE_INSTALL:-0}"', install_script)
        self.assertIn('LOCAL_QWEN_SKIP_PREREQ_CHECKS="${LOCAL_QWEN_SKIP_PREREQ_CHECKS:-0}"', install_script)
        self.assertIn('if [ "$LOCAL_QWEN_SKIP_PACKAGE_INSTALL" != "1" ]; then', install_script)
        self.assertIn('if [ "$LOCAL_QWEN_SKIP_SOURCE_CLONE" = "1" ]; then', install_script)
        self.assertIn('if [ "$LOCAL_QWEN_SKIP_OPENCODE_INSTALL" = "1" ]; then', install_script)
        self.assertIn('if [ "$LOCAL_QWEN_SKIP_PREREQ_CHECKS" != "1" ]; then', install_script)
        self.assertIn('if [ -f "$REPO_ROOT/release-notes.txt" ]; then', install_script)
        self.assertIn("Release notes nisu dostupne u ovom payload-u.", install_script)

    def test_linux_install_script_smoke_mode_creates_state_and_report(self):
        repo_bash_path = to_git_bash_path(REPO_ROOT)
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            smoke_script = temp_path / "linux-install-smoke.sh"
            smoke_script.write_bytes(
                (
                    "\n".join(
                        [
                            "#!/usr/bin/env bash",
                            "set -euo pipefail",
                            f"cd '{repo_bash_path}'",
                            'TEMP_ROOT="/tmp/local-qwen-smoke-$$"',
                            'rm -rf "$TEMP_ROOT"',
                            'mkdir -p "$TEMP_ROOT"',
                            'INSTALL_ROOT="${TEMP_ROOT}/install-root"',
                            'DESKTOP_DIR="${TEMP_ROOT}/Desktop"',
                            'HOME="${TEMP_ROOT}/home"',
                            'mkdir -p "${HOME}"',
                            'export HOME',
                            'export INSTALL_ROOT',
                            'export XDG_DESKTOP_DIR="${DESKTOP_DIR}"',
                            'export PROFILE=balanced',
                            'export SKIP_MODEL_DOWNLOAD=1',
                            'export SKIP_RUNTIME_BUILD=1',
                            'export LOCAL_QWEN_SKIP_PACKAGE_INSTALL=1',
                            'export LOCAL_QWEN_SKIP_SOURCE_CLONE=1',
                            'export LOCAL_QWEN_SKIP_OPENCODE_INSTALL=1',
                            'export LOCAL_QWEN_SKIP_PREREQ_CHECKS=1',
                            'bash ./install/linux/install.sh >/dev/null',
                            'python3 - <<\'PY\' "$INSTALL_ROOT/state/install-state.json" "$INSTALL_ROOT/state/install-report.json" "$DESKTOP_DIR"',
                            'import json, os, sys',
                            'state_path, report_path, desktop_dir = sys.argv[1:4]',
                            'with open(state_path, "r", encoding="utf-8") as handle:',
                            '    state = json.load(handle)',
                            'with open(report_path, "r", encoding="utf-8") as handle:',
                            '    report = json.load(handle)',
                            'print(json.dumps({',
                            '    "modelId": state.get("modelId"),',
                            '    "profile": state.get("profile"),',
                            '    "hasReport": os.path.isfile(report_path),',
                            '    "desktopEntries": sorted(os.listdir(desktop_dir)),',
                            '    "launchersOk": report.get("components", {}).get("launchers", {}).get("ok"),',
                            '}, ensure_ascii=False))',
                            'PY',
                            'rm -rf "$TEMP_ROOT"',
                            "",
                        ]
                    )
                ).encode("utf-8")
            )
            completed = subprocess.run(
                ["bash", to_git_bash_path(smoke_script)],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=120,
            )
        self.assertEqual(completed.returncode, 0, msg=completed.stderr)
        payload = json.loads(completed.stdout.strip())
        self.assertEqual(payload["profile"], "balanced")
        self.assertTrue(payload["hasReport"])
        self.assertTrue(payload["launchersOk"])
        self.assertIn("local-qwen-control-center.desktop", payload["desktopEntries"])
        self.assertIn("opencode-local-qwen.desktop", payload["desktopEntries"])

    def test_check_updates_hides_raw_json_unless_requested(self):
        content = (WINDOWS_LAUNCHER_DIR / "check-updates.ps1").read_text(encoding="utf-8")
        self.assertIn("param(", content)
        self.assertIn("[switch]$Json", content)
        self.assertIn("if ($Json) {", content)
        self.assertIn("$info | ConvertTo-Json -Depth 10", content)
        self.assertIn('Write-Output "Instalacija je vec na latest verziji: v$($info.currentVersion)"', content)

    def test_write_utf8_no_bom_text_retries_when_file_is_temporarily_locked(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            target_path = pathlib.Path(temp_dir) / "locked.json"
            target_path.write_text("old", encoding="utf-8")
            locker = subprocess.Popen(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    (
                        "$fs = [System.IO.File]::Open("
                        f"'{target_path}',"
                        "[System.IO.FileMode]::Open,"
                        "[System.IO.FileAccess]::ReadWrite,"
                        "[System.IO.FileShare]::None"
                        "); "
                        "Start-Sleep -Milliseconds 500; "
                        "$fs.Dispose()"
                    ),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            try:
                time.sleep(0.1)
                result = run_powershell_snippet(
                    (
                        f". '{WINDOWS_COMMON_PATH}'; "
                        f"Write-Utf8NoBomText -Path '{target_path}' -Content 'new-value'; "
                        "Write-Host 'WRITE_OK'"
                    )
                )
                self.assertEqual(result.returncode, 0, msg=result.stderr)
                self.assertIn("WRITE_OK", result.stdout)
                locker.wait(timeout=5)
                self.assertEqual(target_path.read_text(encoding="utf-8"), "new-value")
            finally:
                if locker.poll() is None:
                    locker.wait(timeout=5)

    def test_manage_models_script_supports_browser_filters(self):
        content = (WINDOWS_LAUNCHER_DIR / "manage-models.ps1").read_text(encoding="utf-8")
        self.assertIn("[switch]$InstalledOnly", content)
        self.assertIn("[switch]$RecommendedOnly", content)
        self.assertIn("[switch]$FitOnly", content)
        self.assertIn("[switch]$CoderOnly", content)
        self.assertIn("[switch]$VerifiedOnly", content)
        self.assertIn("-InstalledOnly:$InstalledOnly", content)
        self.assertIn("-RecommendedOnly:$RecommendedOnly", content)
        self.assertIn("-FitOnly:$effectiveFitOnly", content)
        self.assertIn("-CoderOnly:$CoderOnly", content)
        self.assertIn("-VerifiedOnly:$VerifiedOnly", content)
        self.assertIn("function Format-ModelBrowserValue", content)
        self.assertIn("function Format-EnoughDiskLabel", content)
        self.assertIn("function Format-InstalledSizeLabel", content)
        self.assertIn('return "nepoznato"', content)
        self.assertIn("[switch]$TreatZeroAsUnknown", content)
        self.assertIn('$unknownFitModels = @($browser.models | Where-Object { $_.fitGroup -notin @("recommended", "canRun", "notRecommended") -and -not $_.recommended })', content)
        self.assertIn('$groups["Rucno dodati / nepoznat fit"] = $unknownFitModels', content)
        self.assertIn('Write-Host "Nema modela za zadate filtere."', content)

    def test_release_script_attaches_full_fix_log_asset_and_short_summary(self):
        content = RELEASE_ALL_PATH.read_text(encoding="utf-8")
        self.assertIn('$linuxBuildScript = Join-Path $repoRoot "packaging\\linux\\build-run-package.ps1"', content)
        self.assertIn('& powershell -ExecutionPolicy Bypass -File $linuxBuildScript -Version $Version', content)
        self.assertIn("Local-Qwen-Full-Fix-Log-v$Version.txt", content)
        self.assertIn("--notes-file $releaseSummaryPath", content)
        self.assertIn("Full fix log is attached below in Assets", content)

    def test_parameterized_windows_scripts_start_with_param_block(self):
        expected = {
            "uninstall.ps1",
            "check-updates.ps1",
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
        repair_install = (WINDOWS_LAUNCHER_DIR / "repair-install.ps1").read_text(encoding="utf-8")
        repair_model = (WINDOWS_LAUNCHER_DIR / "repair-model.ps1").read_text(encoding="utf-8")
        repair_runtime = (WINDOWS_LAUNCHER_DIR / "repair-runtime.ps1").read_text(encoding="utf-8")
        test_prompt = (WINDOWS_LAUNCHER_DIR / "test-prompt.ps1").read_text(encoding="utf-8")

        self.assertIn("function Get-OpenCodeExecutable", common)
        self.assertIn("function Test-OpenCodeAvailable", common)
        self.assertIn("Get-OpenCodeExecutable", start_opencode)
        self.assertIn("Get-OpenCodeExecutable", launch_agent)
        self.assertIn("Test-OpenCodeAvailable", verify_install)
        self.assertIn("OPENCODE_ENABLE_EXA", start_opencode)
        self.assertIn("OPENCODE_ENABLE_EXA", launch_agent)
        self.assertIn('Write-Output "OpenCode executable: $openCodeExe"', start_opencode)
        self.assertIn('Write-Output "OpenCode je pokrenut u novom PowerShell prozoru."', start_opencode)
        self.assertNotIn("Get-Command opencode -ErrorAction SilentlyContinue", start_opencode)
        self.assertNotIn("Get-Command opencode -ErrorAction SilentlyContinue", launch_agent)
        self.assertIn("$root = Get-LocalQwenStateRoot", launch_agent)
        self.assertIn("Write-Utf8NoBomText -Path $sessionConfigPath", launch_agent)
        self.assertIn("Write-Utf8NoBomText -Path $sessionMetaPath", launch_agent)
        self.assertIn('$settingsPath = Join-Path (Get-LocalQwenStateRoot) "state\\settings.json"', configure_settings)
        self.assertIn('Write-Output "Sacuvano."', configure_settings)
        self.assertIn("Join-Path (Get-LocalQwenStateRoot) 'state\\settings.json'", repair_config)
        self.assertIn('$messages | ForEach-Object { Write-Output $_ }', repair_config)
        self.assertIn('$messages | ForEach-Object { Write-Output $_ }', repair_install)
        self.assertIn('Write-Output "Repair summary json: $repairSummaryPath"', repair_install)
        self.assertIn('$messages | ForEach-Object { Write-Output $_ }', repair_model)
        self.assertIn('$messages | ForEach-Object { Write-Output $_ }', repair_runtime)
        self.assertIn('Write-Output "Smoke test odgovor:"', test_prompt)
        self.assertIn('reasoning_content', test_prompt)
        self.assertIn('Napomena: model nije vratio finalni tekst, pa je prikazan kratak reasoning izvod.', test_prompt)
        self.assertIn('Write-Output "Finish reason: $($choice.finish_reason)"', test_prompt)
        self.assertIn("$modelPath = Get-StateModelFilePath -State $state", verify_install)
        self.assertIn("Join-Path (Get-LocalQwenStateRoot) \"state\\install-report.json\"", verify_install)

    def test_launch_agent_reuses_shared_agent_mode_alias_mapping(self):
        common = WINDOWS_COMMON_PATH.read_text(encoding="utf-8")
        launch_agent = (WINDOWS_LAUNCHER_DIR / "launch-agent.ps1").read_text(encoding="utf-8")

        self.assertIn("function Resolve-AgentSecurityMode", common)
        self.assertIn("workspace-write", common)
        self.assertIn("benchmark", common)
        self.assertIn("$SecurityMode = Resolve-AgentSecurityMode -Mode $SecurityMode", launch_agent)
        self.assertIn("$CapabilityMode = Resolve-AgentCapabilityMode -Mode $CapabilityMode", launch_agent)
        self.assertNotIn("function Resolve-AgentSecurityMode", launch_agent)
        self.assertNotIn("function Resolve-AgentCapabilityMode", launch_agent)

    def test_repair_app_control_reports_empty_policy_state_clearly(self):
        content = (WINDOWS_LAUNCHER_DIR / "repair-app-control.ps1").read_text(encoding="utf-8")
        self.assertIn("function Show-SmartAppControlStatus", content)
        self.assertIn("Nije pronadjena aktivna VerifiedAndReputableDesktop politika.", content)
        self.assertIn("Smart App Control trenutno ne blokira Local Qwen tok.", content)
        self.assertIn("Pronadjeno politika: {0}", content)

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
        self.assertIn("function Copy-FileWithRetry", common)
        self.assertIn("function Copy-DirectoryContentsWithRetry", common)
        self.assertIn("function Get-OpenCodeModelDisplayName", common)
        self.assertIn("function Import-LocalGgufModel", common)
        self.assertIn("function Add-HuggingFaceCustomModel", common)
        self.assertIn('$payload = Invoke-RuntimeEngineJson -Arguments @($arguments.ToArray())', common)
        self.assertIn("Copy-FileWithRetry -SourcePath $file.FullName -DestinationPath $targetPath", common)
        self.assertIn("Copy-DirectoryContentsWithRetry -SourceDir $entry.Source -DestinationDir $entry.Destination", common)
        self.assertIn('[switch]$ForceRedownload', common)
        self.assertIn('if ((-not $ForceRedownload) -and (Test-ModelFileLooksComplete -Path $targetModelPath -ModelId $ModelId)) {', common)
        self.assertIn('return "already-installed"', common)
        self.assertIn('$selectedModelDisplayName = Get-OpenCodeModelDisplayName -Label $selectedModelLabel', common)
        self.assertIn('if ($ageSeconds -gt $maxAgeSeconds) {', common)
        self.assertIn('if ($source -eq "local-cache") { 10 } else { 120 }', common)

    def test_manage_models_groups_recommended_choice_ahead_of_can_run_bucket(self):
        content = (WINDOWS_LAUNCHER_DIR / "manage-models.ps1").read_text(encoding="utf-8")
        self.assertIn('$recommendedModels = @($browser.models | Where-Object { $_.recommended -or $_.fitGroup -eq "recommended" })', content)
        self.assertIn('$canRunModels = @($browser.models | Where-Object { $_.fitGroup -eq "canRun" -and -not $_.recommended })', content)
        self.assertIn('$groups["Preporuceni za ovu masinu"] = $recommendedModels', content)
        self.assertIn('$groups["Moze da radi uz kompromis"] = $canRunModels', content)

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
        self.assertIn('"Repair Windows App Control.lnk"', common)

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
            self.assertEqual(payload["modelId"], "hf-Qwen_Qwen3-8B-GGUF-Qwen3-8B-Q4_K_M.gguf")
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
              hasCustom = [bool](@($payload.models | Where-Object {{ $_.id -eq 'hf-repo_demo-demo.gguf' }}).Count)
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
            $found = $payload.models | Where-Object {{ $_.id -eq 'hf-repo_demo-demo.gguf' }} | Select-Object -First 1
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

    def test_huggingface_custom_models_with_same_filename_do_not_overwrite_each_other(self):
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
            Add-HuggingFaceCustomModel -Repo 'repo/one' -FileName 'same.gguf' -Label 'One' -Family 'Qwen' | Out-Null
            Add-HuggingFaceCustomModel -Repo 'repo/two' -FileName 'same.gguf' -Label 'Two' -Family 'Qwen' | Out-Null
            $models = @(Get-CustomModels)
            [pscustomobject]@{{
              count = $models.Count
              ids = @($models | ForEach-Object {{ $_.id }})
              labels = @($models | ForEach-Object {{ $_.label }})
            }} | ConvertTo-Json -Depth 10
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertEqual(payload["count"], 2)
            self.assertIn("hf-repo_one-same.gguf", payload["ids"])
            self.assertIn("hf-repo_two-same.gguf", payload["ids"])
            self.assertIn("One", payload["labels"])
            self.assertIn("Two", payload["labels"])

    def test_custom_local_label_does_not_duplicate_local_in_opencode_provider_name(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_user = temp_path / "fake-user"
            install_root = fake_user / "LocalQwenHome"
            state_dir = install_root / "state"
            models_dir = install_root / "models"
            config_dir = fake_user / ".config" / "opencode"
            downloads_dir = fake_user / "Downloads"
            for p in [state_dir, models_dir, config_dir, downloads_dir]:
                p.mkdir(parents=True, exist_ok=True)
            source_model = downloads_dir / "alpha.gguf"
            source_model.write_bytes(b"x" * 4096)
            (state_dir / "install-state.json").write_text(
                json.dumps(
                    {
                        "installRoot": str(install_root),
                        "launchersDir": str(install_root / "launchers"),
                        "desktopTargetDir": str(fake_user / "Desktop" / "Local Qwen Home Computer"),
                        "modelFile": str(models_dir / "baseline.gguf"),
                        "modelId": "baseline.gguf",
                        "port": 8091,
                    }
                ),
                encoding="utf-8",
            )
            (state_dir / "settings.json").write_text(
                json.dumps(
                    {
                        "profile": "balanced",
                        "llama": {"contextSize": 4096, "maxOutputTokens": 1024},
                        "opencode": {"buildSteps": 60, "planSteps": 40, "generalSteps": 60, "exploreSteps": 30},
                    }
                ),
                encoding="utf-8",
            )
            (config_dir / "opencode.json").write_text(
                json.dumps({"agent": {"build": {}, "plan": {}, "general": {}, "explore": {}}}),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["USERPROFILE"] = str(fake_user)
            snippet = f"""
            . '{WINDOWS_COMMON_PATH}'
            Import-LocalGgufModel -SourcePath '{source_model}' -Label 'Alpha Local' -Family 'Custom' | Out-Null
            Set-SelectedModel -ModelId 'alpha.gguf' | Out-Null
            Update-OpenCodeConfig | Out-Null
            $config = Get-Content -Raw '{config_dir / "opencode.json"}' | ConvertFrom-Json
            $provider = $config.provider.'local-llamacpp'.models.'alpha.gguf'
            [pscustomobject]@{{ name = $provider.name }} | ConvertTo-Json -Depth 5
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertEqual(payload["name"], "Alpha Local (llama.cpp)")

    def test_model_download_progress_ignores_stale_local_cache_completion(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_user = temp_path / "fake-user"
            install_root = fake_user / "LocalQwenHome"
            state_dir = install_root / "state"
            state_dir.mkdir(parents=True)
            env = os.environ.copy()
            env["USERPROFILE"] = str(fake_user)
            stale_payload = {
                "status": "completed",
                "modelId": "demo.gguf",
                "source": "local-cache",
                "updatedAt": 1,
                "message": "stale",
            }
            (state_dir / "model-download-progress.json").write_text(json.dumps(stale_payload), encoding="utf-8")
            snippet = f"""
            . '{WINDOWS_COMMON_PATH}'
            $progress = Get-ModelDownloadProgressData
            if ($null -eq $progress) {{
              'null'
            }} else {{
              $progress | ConvertTo-Json -Depth 5
            }}
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            self.assertEqual(completed.stdout.strip(), "null")

    def test_set_selected_model_adds_missing_model_path_property_for_older_install_state(self):
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
            env = os.environ.copy()
            env["USERPROFILE"] = str(fake_user)
            snippet = f"""
            . '{WINDOWS_COMMON_PATH}'
            $state = Set-SelectedModel -ModelId 'Qwen3-8B-Q4_K_M.gguf'
            [pscustomobject]@{{
              modelId = $state.modelId
              modelFile = $state.modelFile
              modelPath = $state.modelPath
            }} | ConvertTo-Json -Depth 5
            """
            completed = run_powershell_snippet(snippet, env=env)
            self.assertEqual(completed.returncode, 0, msg=completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertEqual(payload["modelId"], "Qwen3-8B-Q4_K_M.gguf")
            self.assertTrue(payload["modelFile"].endswith("Qwen3-8B-Q4_K_M.gguf"))
            self.assertTrue(payload["modelPath"].endswith("Qwen3-8B-Q4_K_M.gguf"))

    def test_manage_models_updates_opencode_config_even_when_agent_steps_nodes_are_missing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            fake_user = temp_path / "fake-user"
            install_root = fake_user / "LocalQwenHome"
            state_dir = install_root / "state"
            models_dir = install_root / "models"
            config_dir = fake_user / ".config" / "opencode"
            state_dir.mkdir(parents=True)
            models_dir.mkdir(parents=True)
            config_dir.mkdir(parents=True)
            (state_dir / "install-state.json").write_text(
                json.dumps(
                    {
                        "installRoot": str(install_root),
                        "launchersDir": str(install_root / "launchers"),
                        "desktopTargetDir": str(fake_user / "Desktop" / "Local Qwen Home Computer"),
                        "modelFile": str(models_dir / "baseline.gguf"),
                        "modelId": "baseline.gguf",
                        "port": 8091,
                    }
                ),
                encoding="utf-8",
            )
            (state_dir / "settings.json").write_text(
                json.dumps(
                    {
                        "profile": "balanced",
                        "llama": {"contextSize": 4096, "maxOutputTokens": 1024},
                        "opencode": {"buildSteps": 60, "planSteps": 40, "generalSteps": 60, "exploreSteps": 30},
                    }
                ),
                encoding="utf-8",
            )
            (config_dir / "opencode.json").write_text(
                json.dumps({"agent": {"build": {}, "plan": {}, "general": {}, "explore": {}}}),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["USERPROFILE"] = str(fake_user)
            result = subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(REPO_ROOT / "launcher" / "windows" / "manage-models.ps1"),
                    "-ModelId",
                    "Qwen3-8B-Q4_K_M.gguf",
                ],
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            config = json.loads((config_dir / "opencode.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(config["agent"]["build"]["steps"], 60)
            self.assertEqual(config["agent"]["plan"]["steps"], 40)
            self.assertEqual(config["agent"]["general"]["steps"], 60)
            self.assertEqual(config["agent"]["explore"]["steps"], 30)
            provider = config["provider"]["local-llamacpp"]
            self.assertIn("Qwen3-8B-Q4_K_M.gguf", provider["models"])
            self.assertEqual(provider["models"]["Qwen3-8B-Q4_K_M.gguf"]["name"], "Qwen 3 8B Q4_K_M Local (llama.cpp)")

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
        self.assertIn('Uses launch primary group layout', text)
        self.assertIn('Uses tools tab layout', text)

    def test_export_diagnostics_includes_repair_summary_and_token_history(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "local-qwen-common.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn('state\\repair-summary.json', text)
        self.assertIn('state\\token-metrics-history.json', text)
        self.assertIn('release-notes.txt', text)

    def test_repair_install_reports_json_and_text_summary_paths_separately(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "repair-install.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn("$summaryPath = Get-InstallSummaryPath", text)
        self.assertIn('Write-Output "Repair summary json: $repairSummaryPath"', text)
        self.assertIn('Write-Output "Repair summary text: $summaryPath"', text)

    def test_repair_model_skips_download_when_active_model_is_already_complete(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "repair-model.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn('$source = Download-RecommendedModel -ModelId ([string]$state.modelId)', text)
        self.assertIn('$source -eq "already-installed"', text)
        self.assertIn('$modelPath = Get-StateModelFilePath -State $state', text)
        self.assertIn('Model je vec prisutan i deluje kompletno, pa download nije bio potreban.', text)

    def test_manage_models_fit_only_does_not_append_not_recommended_group(self):
        script_path = REPO_ROOT / "launcher" / "windows" / "manage-models.ps1"
        text = script_path.read_text(encoding="utf-8")

        self.assertIn('$effectiveFitOnly = if ($hasExplicitBrowserFilter) { [bool]$FitOnly } else { $true }', text)
        self.assertIn('-FitOnly:$effectiveFitOnly', text)
        self.assertIn('if ((-not $effectiveFitOnly) -and $notRecommendedModels.Count -gt 0) {', text)
        self.assertNotIn('"Nije preporuceno za ovu konfiguraciju" = @((Get-ModelBrowserPayload).models', text)


if __name__ == "__main__":
    unittest.main()
