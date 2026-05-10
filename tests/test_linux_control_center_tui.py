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

    def test_dashboard_home_menu_has_primary_sections(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('echo "1. Pokretanje"', dashboard)
        self.assertIn('echo "2. Modeli"', dashboard)
        self.assertIn('echo "3. Tools"', dashboard)
        self.assertIn('echo "4. Diagnostics"', dashboard)
        self.assertIn('echo "5. Settings"', dashboard)
        self.assertIn('echo "6. Exit"', dashboard)

    def test_launch_screen_contains_only_primary_runtime_actions(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
        launch_block = dashboard.split("show_launch_menu() {", 1)[1].split("show_tools_menu() {", 1)[0]

        self.assertIn('echo "1. Start llama.cpp server"', launch_block)
        self.assertIn('echo "3. Run OpenCode"', launch_block)
        self.assertIn('echo "4. Run llama.cpp web"', launch_block)
        self.assertIn('echo "5. Test prompt"', launch_block)
        self.assertIn('echo "6. Test throughput"', launch_block)
        self.assertNotIn('Repair install', launch_block)


if __name__ == "__main__":
    unittest.main()
