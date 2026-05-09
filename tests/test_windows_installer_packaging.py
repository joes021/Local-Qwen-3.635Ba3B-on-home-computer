import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
ISS_PATH = REPO_ROOT / "packaging" / "windows" / "LocalQwenSetup.iss"
BOOTSTRAP_PATH = REPO_ROOT / "install" / "windows" / "setup-bootstrap.cmd"
INSTALL_PS1_PATH = REPO_ROOT / "install" / "windows" / "install.ps1"
RELEASE_ALL_PATH = REPO_ROOT / "packaging" / "release-all.ps1"


class WindowsInstallerPackagingTests(unittest.TestCase):
    def test_inno_setup_closes_without_finished_page_and_does_not_hide_bootstrap(self):
        content = ISS_PATH.read_text(encoding="utf-8")
        self.assertIn("DisableFinishedPage=yes", content)
        run_line = next(
            line for line in content.splitlines()
            if line.strip().startswith("Filename:") and "setup-bootstrap.cmd" in line
        )
        self.assertNotIn("runhidden", run_line.lower())
        self.assertIn("waituntilterminated", run_line.lower())
        self.assertIn("CreateInputDirPage", content)
        self.assertIn("GetSelectedInstallRoot", content)
        self.assertIn("RequiredDiskCaption", content)
        self.assertIn("GetDefaultInstallRoot", content)
        self.assertNotIn("{userprofile}", content.lower())

    def test_bootstrap_script_announces_install_plan_and_clean_finish(self):
        content = BOOTSTRAP_PATH.read_text(encoding="utf-8").lower()
        self.assertIn("this installer will", content)
        self.assertIn("installation complete", content)
        self.assertIn("will close automatically", content)
        self.assertIn("%systemroot%\\system32\\windowspowershell\\v1.0\\powershell.exe", content)
        self.assertNotIn("\npowershell.exe -noprofile", content)
        self.assertIn("%*", content)

    def test_install_script_contains_explicit_stage_progress_markers(self):
        content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        self.assertIn("function Write-InstallOverview", content)
        self.assertIn("function Invoke-InstallStage", content)
        self.assertIn("[{0}/{1}]", content)

    def test_install_script_treats_ninja_as_optional_for_turboquant(self):
        content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        self.assertIn("function Ensure-OptionalCommand", content)
        self.assertIn("Ninja-build.Ninja", content)
        self.assertIn("TurboQuant build bice preskocen", content)

    def test_packaging_and_shortcuts_include_uninstall_entrypoints(self):
        install_content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        iss_content = ISS_PATH.read_text(encoding="utf-8")
        self.assertIn("uninstall.ps1", install_content)
        self.assertIn("Uninstall Local Qwen.lnk", install_content)
        self.assertIn("install-update.ps1", install_content)
        self.assertIn("Update Local Qwen.lnk", install_content)
        self.assertIn("Uninstallable=yes", iss_content)

    def test_release_script_attaches_full_fix_log_asset_and_short_summary(self):
        content = RELEASE_ALL_PATH.read_text(encoding="utf-8")
        self.assertIn("Local-Qwen-Full-Fix-Log-v$Version.txt", content)
        self.assertIn("--notes-file $releaseSummaryPath", content)
        self.assertIn("Full fix log is attached below in Assets", content)


if __name__ == "__main__":
    unittest.main()
