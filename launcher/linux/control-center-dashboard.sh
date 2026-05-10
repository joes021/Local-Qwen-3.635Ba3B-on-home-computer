#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"
. "$SCRIPT_DIR/control-center-actions.sh"

render_status_header() {
  local profile model_id health_state server_title next_action summary_line
  profile="$(get_saved_profile)"
  model_id="$(python3 - <<'PY' "$(get_install_state_path)"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelId", "n/a"))
PY
)"
  health_state="$(python3 - <<'PY' "$(get_health_center_json)"
import json, sys
payload = json.loads(sys.argv[1])
print(payload.get("overallState", "unknown"))
PY
)"
  server_title="$(python3 - <<'PY' "$(get_effective_service_status_json)"
import json, sys
payload = json.loads(sys.argv[1])
print(payload.get("title", payload.get("state", "unknown")))
PY
)"
  next_action="$(python3 - <<'PY' "$(get_install_state_path)" "$(get_runtime_engine_path)" "$(get_health_url)" "$HOME/.config/opencode/opencode.json"
import json, os, subprocess, sys, urllib.request
state_path, runtime_script, health_url, opencode_config = sys.argv[1:5]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
has_server = False
try:
    with urllib.request.urlopen(health_url, timeout=3) as response:
        has_server = response.status == 200
except Exception:
    pass
payload = subprocess.run(
    [
        sys.executable,
        runtime_script,
        "next-action",
        "--has-server", str(has_server).lower(),
        "--has-model", str(os.path.isfile(state.get("modelFile", ""))).lower(),
        "--has-opencode-config", str(os.path.isfile(opencode_config)).lower(),
    ],
    capture_output=True,
    text=True,
    check=True,
)
data = json.loads(payload.stdout)
print(data.get("title", "n/a"))
PY
)"
  summary_line="$(python3 - <<'PY' "$(get_token_metrics_summary_json)"
import json, sys
payload = json.loads(sys.argv[1])
recent = payload.get("activity", {}).get("recentActivities", [])
if recent:
    item = recent[0]
    print(f"{item.get('source', 'ostalo')} | {item.get('label', '--')} | {item.get('totalMs', 0)} ms")
else:
    print("Jos nema merenja")
PY
)"

  echo "Local Qwen Control Center"
  echo "Verzija: $(python3 - <<'PY' "$(get_local_qwen_root)/version.json"
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        print(json.load(f).get("version", "unknown"))
else:
    print("unknown")
PY
)"
  echo "Server: $server_title | Health: $health_state | Model: $model_id | Profil: $profile"
  echo "Next action: $next_action"
  echo "Last activity: $summary_line"
  echo
}

render_home_screen() {
  clear
  render_status_header
}

show_main_menu() {
  echo "1. Pokretanje"
  echo "2. Modeli"
  echo "3. Tools"
  echo "4. Diagnostics"
  echo "5. Settings"
  echo "6. Exit"
}

show_launch_menu() {
  while true; do
    clear
    render_status_header
    echo "Pokretanje"
    echo "1. Start llama.cpp server"
    echo "2. Stop llama.cpp server"
    echo "3. Run OpenCode"
    echo "4. Run llama.cpp web"
    echo "5. Test prompt"
    echo "6. Test throughput"
    echo "7. Nazad"
    read -r -p "Izaberi broj i pritisni Enter: " choice
    case "$choice" in
      1) run_action_with_result_screen "Start llama.cpp server" "$SCRIPT_DIR/start-server.sh" ;;
      2) run_action_with_result_screen "Stop llama.cpp server" "$SCRIPT_DIR/stop-server.sh" ;;
      3) run_action_with_result_screen "Run OpenCode" "$SCRIPT_DIR/start-opencode.sh" ;;
      4) show_info_screen "Run llama.cpp web" "Linux web launcher jos nije izdvojen kao poseban tok." ;;
      5) run_action_with_result_screen "Test prompt" "$SCRIPT_DIR/test-prompt.sh" ;;
      6) show_info_screen "Test throughput" "Benchmark TUI tok dolazi u sledecim zadacima." ;;
      7) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 7." ;;
    esac
  done
}

show_tools_menu() {
  while true; do
    clear
    render_status_header
    echo "Tools"
    echo "1. Repair install"
    echo "2. Repair model"
    echo "3. Repair runtime"
    echo "4. Repair config"
    echo "5. Guided repair"
    echo "6. Check updates"
    echo "7. Install update"
    echo "8. Nazad"
    read -r -p "Izaberi broj i pritisni Enter: " choice
    case "$choice" in
      1) run_action_with_result_screen "Repair install" "$SCRIPT_DIR/repair-install.sh" ;;
      2) run_action_with_result_screen "Repair model" "$SCRIPT_DIR/repair-model.sh" ;;
      3) run_action_with_result_screen "Repair runtime" "$SCRIPT_DIR/repair-runtime.sh" ;;
      4) run_action_with_result_screen "Repair config" "$SCRIPT_DIR/repair-config.sh" ;;
      5) run_action_with_result_screen "Guided repair" "$SCRIPT_DIR/repair-install.sh" ;;
      6) run_action_with_result_screen "Check updates" "$SCRIPT_DIR/check-updates.sh" ;;
      7) run_action_with_result_screen "Install update" "$SCRIPT_DIR/install-update.sh" ;;
      8) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 8." ;;
    esac
  done
}

render_model_summary() {
  python3 - <<'PY' "$(get_install_state_path)" "$(get_installed_model_ids_csv)"
import json, sys
state_path, installed_csv = sys.argv[1:3]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
installed = [item for item in installed_csv.split(",") if item]
print(f"Aktivni model: {state.get('modelId', 'n/a')}")
print(f"Skinuti modeli: {len(installed)}")
print("Download: nema aktivnog preuzimanja")
print("Status oznake: [AKTIVAN] [SKINUT] [NIJE SKINUT] [HF] [LOKALNI] [PREPORUKA]")
PY
}

prompt_model_id() {
  local prompt_text="$1"
  local model_id
  read -r -p "$prompt_text" model_id
  printf '%s' "$model_id"
}

show_models_menu() {
  while true; do
    clear
    render_status_header
    echo "Modeli"
    render_model_summary
    echo
    echo "1. Pregled modela"
    echo "2. Aktiviraj model"
    echo "3. Preuzmi model"
    echo "4. Dodaj lokalni GGUF"
    echo "5. Dodaj HF model"
    echo "6. Nazad"
    read -r -p "Izaberi broj i pritisni Enter: " choice
    case "$choice" in
      1) run_action_with_result_screen "Pregled modela" "$SCRIPT_DIR/manage-models.sh" list ;;
      2)
        model_id="$(prompt_model_id "Unesi model id za aktivaciju: ")"
        if [ -n "$model_id" ]; then
          run_action_with_result_screen "Aktiviraj model" "$SCRIPT_DIR/manage-models.sh" use "$model_id"
        else
          show_warning_screen "Aktiviraj model" "Model id je obavezan."
        fi
        ;;
      3)
        model_id="$(prompt_model_id "Unesi model id za download (Enter za preporuceni): ")"
        if [ -n "$model_id" ]; then
          run_action_with_result_screen "Preuzmi model" "$SCRIPT_DIR/manage-models.sh" download "$model_id"
        else
          run_action_with_result_screen "Preuzmi model" "$SCRIPT_DIR/manage-models.sh" recommend
        fi
        ;;
      4) show_info_screen "Dodaj lokalni GGUF" "Linux import lokalnog GGUF modela je sledeci korak ovog TUI plana." ;;
      5) show_info_screen "Dodaj HF model" "Linux Hugging Face custom model tok je sledeci korak ovog TUI plana." ;;
      6) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 6." ;;
    esac
  done
}

show_diagnostics_menu() {
  while true; do
    clear
    render_status_header
    echo "Diagnostics"
    echo "1. Health details"
    echo "2. View logs"
    echo "3. Export diagnostics"
    echo "4. Benchmark pregled"
    echo "5. Nazad"
    read -r -p "Izaberi broj i pritisni Enter: " choice
    case "$choice" in
      1) run_action_with_result_screen "Health details" "$SCRIPT_DIR/verify-install.sh" ;;
      2) run_action_with_result_screen "View logs" "$SCRIPT_DIR/show-logs.sh" ;;
      3) run_action_with_result_screen "Export diagnostics" "$SCRIPT_DIR/export-diagnostics.sh" ;;
      4) show_info_screen "Benchmark pregled" "$(python3 - <<'PY' "$(get_token_metrics_summary_json)"
import json, sys
payload = json.loads(sys.argv[1])
current = payload.get("current")
if not current:
    print("Jos nema benchmark merenja. Pokreni Test prompt ili Test throughput.")
else:
    print(f\"Poslednje merenje: prompt {current.get('promptTokensPerSecond', 0)} tok/s | output {current.get('completionTokensPerSecond', 0)} tok/s | total {current.get('totalTokensPerSecond', 0)} tok/s\")
    print(f\"Prosek total: {payload.get('averages', {}).get('totalTokensPerSecond', 0)} tok/s\")
PY
)" ;;
      5) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 5." ;;
    esac
  done
}

show_settings_menu() {
  while true; do
    clear
    render_status_header
    echo "Settings"
    echo "1. Promeni profil"
    echo "2. Promeni context"
    echo "3. Promeni output"
    echo "4. Promeni stepove"
    echo "5. Promeni working dir"
    echo "6. Quick presets"
    echo "7. Nazad"
    read -r -p "Izaberi broj i pritisni Enter: " choice
    case "$choice" in
      1) run_action_with_result_screen "Promeni profil" "$SCRIPT_DIR/settings-tui.sh" ;;
      2) run_action_with_result_screen "Promeni context" "$SCRIPT_DIR/settings-tui.sh" ;;
      3) run_action_with_result_screen "Promeni output" "$SCRIPT_DIR/settings-tui.sh" ;;
      4) run_action_with_result_screen "Promeni stepove" "$SCRIPT_DIR/settings-tui.sh" ;;
      5) run_action_with_result_screen "Promeni working dir" "$SCRIPT_DIR/settings-tui.sh" ;;
      6) run_action_with_result_screen "Quick presets" "$SCRIPT_DIR/settings-tui.sh" ;;
      7) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 7." ;;
    esac
  done
}

render_home_screen
while true; do
  show_main_menu
  read -r -p "Izaberi broj i pritisni Enter: " choice
  case "$choice" in
    1) show_launch_menu ;;
    2) show_models_menu ;;
    3) show_tools_menu ;;
    4) show_diagnostics_menu ;;
    5) show_settings_menu ;;
    6) exit 0 ;;
    *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 6." ;;
  esac
  render_home_screen
done
