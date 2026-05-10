import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROL_CENTER_PATH = REPO_ROOT / "launcher" / "linux" / "control-center.sh"
DASHBOARD_PATH = REPO_ROOT / "launcher" / "linux" / "control-center-dashboard.sh"


class LinuxControlCenterTuiTests(unittest.TestCase):
    def test_linux_dashboard_entry_uses_separate_dashboard_file(self):
        control_center = CONTROL_CENTER_PATH.read_text(encoding="utf-8")
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('exec "$SCRIPT_DIR/control-center-dashboard.sh"', control_center)
        self.assertIn("render_home_screen()", dashboard)
        self.assertIn("show_main_menu()", dashboard)


if __name__ == "__main__":
    unittest.main()
