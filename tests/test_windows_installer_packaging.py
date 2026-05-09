import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
ISS_PATH = REPO_ROOT / "packaging" / "windows" / "LocalQwenSetup.iss"
BOOTSTRAP_PATH = REPO_ROOT / "install" / "windows" / "setup-bootstrap.cmd"
INSTALL_PS1_PATH = REPO_ROOT / "install" / "windows" / "install.ps1"


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

    def test_bootstrap_script_announces_install_plan_and_clean_finish(self):
        content = BOOTSTRAP_PATH.read_text(encoding="utf-8").lower()
        self.assertIn("this installer will", content)
        self.assertIn("installation complete", content)
        self.assertIn("will close automatically", content)

    def test_install_script_contains_explicit_stage_progress_markers(self):
        content = INSTALL_PS1_PATH.read_text(encoding="utf-8")
        self.assertIn("function Write-InstallOverview", content)
        self.assertIn("function Invoke-InstallStage", content)
        self.assertIn("[{0}/{1}]", content)


if __name__ == "__main__":
    unittest.main()
