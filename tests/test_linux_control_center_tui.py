import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROL_CENTER_PATH = REPO_ROOT / "launcher" / "linux" / "control-center.sh"
DASHBOARD_PATH = REPO_ROOT / "launcher" / "linux" / "control-center-dashboard.sh"
ACTIONS_PATH = REPO_ROOT / "launcher" / "linux" / "control-center-actions.sh"


class LinuxControlCenterTuiTests(unittest.TestCase):
    def test_linux_dashboard_entry_uses_separate_dashboard_file(self):
        control_center = CONTROL_CENTER_PATH.read_text(encoding="utf-8")
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('exec "$SCRIPT_DIR/control-center-dashboard.sh"', control_center)
        self.assertIn('show_home_menu()', dashboard)
        self.assertIn('run_dashboard_menu', dashboard)

    def test_dashboard_home_menu_has_primary_sections(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('"Home"', dashboard)
        self.assertIn('"Pokretanje"', dashboard)
        self.assertIn('"Modeli"', dashboard)
        self.assertIn('"Tools"', dashboard)
        self.assertIn('"Diagnostics"', dashboard)
        self.assertIn('"Settings"', dashboard)
        self.assertIn('"Exit"', dashboard)

    def test_launch_screen_contains_only_primary_runtime_actions(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")
        launch_block = dashboard.split("show_launch_menu() {", 1)[1].split("show_tools_menu() {", 1)[0]

        self.assertIn('"Start llama.cpp server"', launch_block)
        self.assertIn('"Run OpenCode"', launch_block)
        self.assertIn('"Run llama.cpp web"', launch_block)
        self.assertIn('"Test prompt"', launch_block)
        self.assertIn('"Test throughput"', launch_block)
        self.assertNotIn('Repair install', launch_block)

    def test_models_screen_mentions_model_actions_and_status_labels(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('"Pregled modela"', dashboard)
        self.assertIn('"Aktiviraj model"', dashboard)
        self.assertIn('"Preuzmi model"', dashboard)
        self.assertIn('"Dodaj lokalni GGUF"', dashboard)
        self.assertIn('"Dodaj HF model"', dashboard)
        self.assertIn("Status: AKTIVAN | SKINUT | NIJE SKINUT | HF | LOKALNI | PREPORUKA", dashboard)

    def test_models_screen_uses_picker_and_custom_model_actions(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('run_action_with_result_screen "Dodaj lokalni GGUF" "$SCRIPT_DIR/manage-models.sh" add-local', dashboard)
        self.assertIn('run_action_with_result_screen "Dodaj HF model" "$SCRIPT_DIR/manage-models.sh" add-hf', dashboard)
        self.assertIn('pick_model_id "Pregled modela" "Izaberi model za detalje."', dashboard)
        self.assertIn('run_external_terminal_action_or_inline "Preuzmi model" "$SCRIPT_DIR/manage-models.sh" download "$model_id"', dashboard)

    def test_dashboard_uses_external_terminal_for_long_running_actions_when_possible(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn("run_external_terminal_action_or_inline()", dashboard)
        self.assertIn('"$SCRIPT_DIR/desktop-launch.sh" "$@" >/dev/null 2>&1', dashboard)
        self.assertIn('show_info_screen "$title" "Akcija je pokrenuta u novom terminalu. Prati tok tamo dok se ne zavrsi."', dashboard)
        self.assertIn('run_external_terminal_action_or_inline "Install update" "$SCRIPT_DIR/install-update.sh"', dashboard)

    def test_dashboard_handles_back_without_exiting(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('6|"__BACK__") return ;;', dashboard)
        self.assertIn('"__BACK__") continue ;;', dashboard)

    def test_diagnostics_screen_contains_logs_export_and_benchmark_entries(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('"Health details"', dashboard)
        self.assertIn('"View logs"', dashboard)
        self.assertIn('"Export diagnostics"', dashboard)
        self.assertIn('"Benchmark pregled"', dashboard)

    def test_settings_screen_contains_profile_context_output_and_presets(self):
        dashboard = DASHBOARD_PATH.read_text(encoding="utf-8")

        self.assertIn('"Promeni profil"', dashboard)
        self.assertIn('"Promeni context"', dashboard)
        self.assertIn('"Promeni output"', dashboard)
        self.assertIn('"Promeni stepove"', dashboard)
        self.assertIn('"Promeni working dir"', dashboard)
        self.assertIn('"Quick presets"', dashboard)

    def test_action_result_preview_does_not_use_pipefail_unfriendly_head_pipeline(self):
        actions = ACTIONS_PATH.read_text(encoding="utf-8")

        self.assertIn("extract_nonempty_preview_lines()", actions)
        self.assertIn('summary="$(extract_nonempty_preview_lines "$output" 6)"', actions)
        self.assertIn('details="$(extract_nonempty_preview_lines "$output" 8)"', actions)
        self.assertNotIn("sed '/^[[:space:]]*$/d' | head -n 6", actions)
        self.assertNotIn("sed '/^[[:space:]]*$/d' | head -n 8", actions)


if __name__ == "__main__":
    unittest.main()
