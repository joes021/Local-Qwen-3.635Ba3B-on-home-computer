#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"
. "$SCRIPT_DIR/control-center-actions.sh"

get_current_version() {
  python3 - <<'PY' "$(get_local_qwen_root)/version.json"
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    with open(path, "r", encoding="utf-8-sig") as f:
        print(json.load(f).get("version", "unknown"))
else:
    print("unknown")
PY
}

get_current_model_id() {
  python3 - <<'PY' "$(get_install_state_path)"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
    print(json.load(f).get("modelId", "n/a"))
PY
}

get_next_action_title() {
  python3 - <<'PY' "$(get_install_state_path)" "$(get_runtime_engine_path)" "$(get_health_url)" "$HOME/.config/opencode/opencode.json"
import json, os, subprocess, sys, urllib.request
state_path, runtime_script, health_url, opencode_config = sys.argv[1:5]
with open(state_path, "r", encoding="utf-8-sig") as f:
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
}

get_last_activity_summary() {
  python3 - <<'PY' "$(get_token_metrics_summary_json)"
import json, sys
payload = json.loads(sys.argv[1])
recent = payload.get("activity", {}).get("recentActivities", [])
if recent:
    item = recent[0]
    print(f"{item.get('source', 'ostalo')} | {item.get('label', '--')} | {item.get('totalMs', 0)} ms")
else:
    print("Jos nema merenja")
PY
}

build_status_lines() {
  local profile model_id health_state server_title next_action summary_line version
  profile="$(get_saved_profile)"
  model_id="$(get_current_model_id)"
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
  next_action="$(get_next_action_title)"
  summary_line="$(get_last_activity_summary)"
  version="$(get_current_version)"
  if [ "${#model_id}" -gt 34 ]; then
    model_id="${model_id:0:31}..."
  fi
  if [ "${#next_action}" -gt 42 ]; then
    next_action="${next_action:0:39}..."
  fi
  if [ "${#summary_line}" -gt 42 ]; then
    summary_line="${summary_line:0:39}..."
  fi

  printf '%s\n' \
    "Local Qwen Control Center v$version" \
    "Server: $server_title | Health: $health_state" \
    "Model: $model_id | Profil: $profile" \
    "Next: $next_action" \
    "Aktivnost: $summary_line"
}

render_status_header() {
  build_status_lines
  echo
}

run_dashboard_menu() {
  local title="$1"
  local prompt="$2"
  shift 2
  local header
  header="$(build_status_lines)"
  if control_center_has_tui; then
    run_menu "$title" "$header"$'\n\n'"$prompt" "$@"
  else
    run_menu "$title" "$prompt" "$@"
  fi
}

build_home_prompt() {
  python3 - <<'PY' "$(get_health_center_json)" "$(get_repair_summary_json)"
import json, sys
health = json.loads(sys.argv[1])
repair = json.loads(sys.argv[2]) if sys.argv[2] != "null" else None
title = health.get("title", "Stanje nije poznato")
summary = health.get("summary", "Nema dodatnog sazetka.")
primary = health.get("primaryActionTitle", "Nema preporucene akcije")
if repair:
    fixed = len(repair.get("fixed", []) or [])
    repair_line = f"Poslednji repair: {fixed} popravki"
else:
    repair_line = "Poslednji repair: jos nema summary-ja"
print(f"{title}\\n{summary}\\nSledece: {primary}\\n{repair_line}")
PY
}

prompt_nonempty_input() {
  local title="$1"
  local prompt_text="$2"
  local default_value="${3:-}"
  local value
  value="$(prompt_input "$title" "$prompt_text" "$default_value")"
  if [ "$value" = "__CANCEL__" ]; then
    return 1
  fi
  if [ -z "${value// }" ]; then
    show_warning_screen "$title" "Polje je obavezno."
    return 1
  fi
  printf '%s' "$value"
}

prompt_model_id() {
  local title="$1"
  local prompt_text="$2"
  prompt_input "$title" "$prompt_text"
}

get_installed_model_sizes_json() {
  local defaults_path models_dir
  defaults_path="$(get_defaults_path)"
  models_dir="$(get_local_qwen_root)/models"
  python3 - <<'PY' "$defaults_path" "$models_dir"
import json, os, sys
defaults_path, models_dir = sys.argv[1:3]
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)
result = {}
for item in defaults.get("modelChoices", {}).values():
    path = os.path.join(models_dir, item.get("filename", ""))
    if os.path.isfile(path):
        result[item.get("id")] = os.path.getsize(path)
print(json.dumps(result))
PY
}

get_free_disk_gib() {
  local models_dir
  models_dir="$(get_local_qwen_root)/models"
  python3 - <<'PY' "$models_dir"
import os, shutil, sys
path = sys.argv[1]
os.makedirs(path, exist_ok=True)
usage = shutil.disk_usage(path)
print(round(usage.free / (1024 ** 3), 2))
PY
}

get_model_browser_for_current_machine() {
  local current_model_id="$1"
  local installed_ids="$2"
  local installed_sizes_json="$3"
  local free_disk_gib="$4"
  local gpu_mib="0" ram_gib="0" cpu_threads="0"
  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d '[:space:]')"
  fi
  ram_gib="$(python3 - <<'PY'
with open("/proc/meminfo", "r", encoding="utf-8", errors="ignore") as handle:
    for line in handle:
        if line.startswith("MemTotal:"):
            print(round(int(line.split()[1]) / 1024 / 1024))
            break
    else:
        print(0)
PY
)"
  cpu_threads="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)"
  get_model_browser_json "$gpu_mib" "$ram_gib" "$cpu_threads" "$current_model_id" "$installed_ids" "$installed_sizes_json" "$free_disk_gib" "" ""
}

launch_opencode_from_center() {
  local profile
  profile="$(get_saved_profile)"
  "$SCRIPT_DIR/desktop-launch.sh" "$SCRIPT_DIR/start-opencode.sh" "$profile"
}

run_external_terminal_action_or_inline() {
  local title="$1"
  shift
  if { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${XDG_CURRENT_DESKTOP:-}" ]; } && "$SCRIPT_DIR/desktop-launch.sh" "$@" >/dev/null 2>&1; then
    show_info_screen "$title" "Akcija je pokrenuta u novom terminalu. Prati tok tamo dok se ne zavrsi."
    return 0
  fi
  run_action_with_result_screen "$title" "$@"
}

show_launch_menu() {
  while true; do
    choice="$(run_dashboard_menu "Pokretanje" "Izaberi akciju." \
      1 "Start llama.cpp server" \
      2 "Stop llama.cpp server" \
      3 "Run OpenCode" \
      4 "Run llama.cpp web" \
      5 "Test prompt" \
      6 "Test throughput" \
      7 "Nazad")" || return
    case "$choice" in
      1) run_action_with_result_screen "Start llama.cpp server" "$SCRIPT_DIR/start-server.sh" ;;
      2) run_action_with_result_screen "Stop llama.cpp server" "$SCRIPT_DIR/stop-server.sh" ;;
      3) run_action_with_result_screen "Run OpenCode" launch_opencode_from_center ;;
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
    choice="$(run_dashboard_menu "Tools" "Izaberi maintenance ili update akciju." \
      1 "Repair install" \
      2 "Repair model" \
      3 "Repair runtime" \
      4 "Repair config" \
      5 "Guided repair" \
      6 "Check updates" \
      7 "Install update" \
      8 "Nazad")" || return
    case "$choice" in
      1) run_action_with_result_screen "Repair install" "$SCRIPT_DIR/repair-install.sh" ;;
      2) run_action_with_result_screen "Repair model" "$SCRIPT_DIR/repair-model.sh" ;;
      3) run_action_with_result_screen "Repair runtime" "$SCRIPT_DIR/repair-runtime.sh" ;;
      4) run_action_with_result_screen "Repair config" "$SCRIPT_DIR/repair-config.sh" ;;
      5) run_action_with_result_screen "Guided repair" "$SCRIPT_DIR/repair-install.sh" ;;
      6) run_action_with_result_screen "Check updates" "$SCRIPT_DIR/check-updates.sh" ;;
      7) run_external_terminal_action_or_inline "Install update" "$SCRIPT_DIR/install-update.sh" ;;
      8) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 8." ;;
    esac
  done
}

render_model_summary() {
  python3 - <<'PY' "$(get_install_state_path)" "$(get_installed_model_ids_csv)"
import json, sys
state_path, installed_csv = sys.argv[1:3]
with open(state_path, "r", encoding="utf-8-sig") as f:
    state = json.load(f)
installed = [item for item in installed_csv.split(",") if item]
print(f"Aktivni model: {state.get('modelId', 'n/a')}")
print(f"Skinuti modeli: {len(installed)}")
print("Download: nema aktivnog preuzimanja")
print("Status: AKTIVAN | SKINUT | NIJE SKINUT | HF | LOKALNI | PREPORUKA")
PY
}

get_model_browser_payload_json() {
  local current_id installed_ids installed_sizes_json free_disk_gib
  current_id="$(python3 - <<'PY' "$(get_install_state_path)"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelId", ""))
PY
)"
  installed_ids="$(get_installed_model_ids_csv)"
  installed_sizes_json="$(get_installed_model_sizes_json)"
  free_disk_gib="$(get_free_disk_gib)"
  get_model_browser_for_current_machine "$current_id" "$installed_ids" "$installed_sizes_json" "$free_disk_gib"
}

build_model_menu_items() {
  python3 - <<'PY' "$(get_model_browser_payload_json)"
import json, sys
payload = json.loads(sys.argv[1])
for item in payload.get("models", []):
    status_bits = []
    if item.get("active"):
        status_bits.append("AKTIVAN")
    elif item.get("installed"):
        status_bits.append("SKINUT")
    else:
        status_bits.append("NIJE_SKINUT")
    if item.get("installed"):
        pass
    if item.get("customSource") == "huggingface":
        status_bits.append("HF")
    elif item.get("customSource") == "local-file":
        status_bits.append("LOKALNI")
    if item.get("recommended"):
        status_bits.append("PREPORUKA")
    display_name = item.get('label', item.get('id'))
    status_text = " / ".join(status_bits) if status_bits else "status nepoznat"
    label = f"{display_name[:42]} [{status_text}]"
    print(item.get("id", ""))
    print(label[:72].rstrip())
PY
}

show_model_details_screen() {
  local model_id="$1"
  local details
  details="$(python3 - <<'PY' "$(get_model_browser_payload_json)" "$model_id"
import json, sys
payload = json.loads(sys.argv[1])
model_id = sys.argv[2]
for item in payload.get("models", []):
    if item.get("id") == model_id:
        lines = [
            f"Naziv: {item.get('label', item.get('id'))}",
            f"Status: {'AKTIVAN ' if item.get('active') else ''}{'SKINUT' if item.get('installed') else 'NIJE SKINUT'}",
            f"Porodica: {item.get('family', 'nepoznato')}",
            f"Fit: {item.get('fitGroup', 'unknown')}",
            f"Brzina: {item.get('speedEstimateLabel', 'nepoznato')}",
            f"Instalirano: {item.get('installedSizeGiB', 'nepoznato')} GiB",
            f"Disk potrebno: {item.get('diskNeededGiB', 'nepoznato')} GiB",
            f"Disk slobodno: {item.get('freeDiskGiB', 'nepoznato')} GiB",
            f"Enough disk: {'da' if item.get('hasEnoughDisk') else 'ne' if item.get('hasEnoughDisk') is not None else 'nepoznato'}",
            f"Izvor: {item.get('source', 'nepoznato')}",
            "",
            item.get('description', 'Bez opisa.'),
        ]
        print("\\n".join(str(x) for x in lines))
        break
else:
    print(f"Model nije pronadjen: {model_id}")
PY
)"
  show_info_screen "Detalji modela" "$details"
}

pick_model_id() {
  local title="$1"
  local prompt="$2"
  local menu_args=()
  mapfile -t _model_lines < <(build_model_menu_items)
  if [ "${#_model_lines[@]}" -eq 0 ]; then
    show_warning_screen "$title" "Nema modela za prikaz."
    return 1
  fi
  local i
  for ((i = 0; i < ${#_model_lines[@]}; i += 2)); do
    menu_args+=("${_model_lines[$i]}" "${_model_lines[$((i + 1))]}")
  done
  run_dashboard_menu "$title" "$prompt" "${menu_args[@]}"
}

show_models_menu() {
  while true; do
    local prompt model_id
    prompt="$(render_model_summary)"
    choice="$(run_dashboard_menu "Modeli" "$prompt" \
      1 "Pregled modela" \
      2 "Aktiviraj model" \
      3 "Preuzmi model" \
      4 "Dodaj lokalni GGUF" \
      5 "Dodaj HF model" \
      6 "Nazad")" || return
    case "$choice" in
      1)
        model_id="$(pick_model_id "Pregled modela" "Izaberi model za detalje.")" || continue
        [ "$model_id" = "__BACK__" ] && continue
        show_model_details_screen "$model_id"
        ;;
      2)
        model_id="$(pick_model_id "Aktiviraj model" "Izaberi model za aktivaciju.")" || continue
        [ "$model_id" = "__BACK__" ] && continue
        if [ -n "$model_id" ]; then
          run_action_with_result_screen "Aktiviraj model" "$SCRIPT_DIR/manage-models.sh" use "$model_id"
        else
          show_warning_screen "Aktiviraj model" "Model id je obavezan."
        fi
        ;;
      3)
        model_id="$(pick_model_id "Preuzmi model" "Izaberi model za preuzimanje.")" || continue
        [ "$model_id" = "__BACK__" ] && continue
        if [ -n "$model_id" ]; then
          run_external_terminal_action_or_inline "Preuzmi model" "$SCRIPT_DIR/manage-models.sh" download "$model_id"
        else
          run_external_terminal_action_or_inline "Preuzmi model" "$SCRIPT_DIR/manage-models.sh" recommend
        fi
        ;;
      4)
        local_path="$(prompt_nonempty_input "Dodaj lokalni GGUF" "Unesi punu putanju do .gguf fajla:")" || continue
        local_label="$(prompt_input "Dodaj lokalni GGUF" "Opcioni prikazni naziv modela:" "")"
        [ "$local_label" = "__CANCEL__" ] && local_label=""
        local_family="$(prompt_input "Dodaj lokalni GGUF" "Porodica modela (npr. Qwen, Gemma, Custom):" "Custom")"
        [ "$local_family" = "__CANCEL__" ] && local_family="Custom"
        run_action_with_result_screen "Dodaj lokalni GGUF" "$SCRIPT_DIR/manage-models.sh" add-local "$local_path" "$local_label" "$local_family"
        ;;
      5)
        hf_repo="$(prompt_nonempty_input "Dodaj HF model" "Unesi Hugging Face repo, npr. Qwen/Qwen3-8B-GGUF:")" || continue
        hf_file="$(prompt_nonempty_input "Dodaj HF model" "Unesi TACAN GGUF filename sa kvantizacijom, npr. Qwen3-8B-Q4_K_M.gguf:")" || continue
        hf_label="$(prompt_input "Dodaj HF model" "Opcioni prikazni naziv modela:" "")"
        [ "$hf_label" = "__CANCEL__" ] && hf_label=""
        hf_family="$(prompt_input "Dodaj HF model" "Porodica modela (npr. Qwen, Gemma, Custom):" "Custom")"
        [ "$hf_family" = "__CANCEL__" ] && hf_family="Custom"
        run_action_with_result_screen "Dodaj HF model" "$SCRIPT_DIR/manage-models.sh" add-hf "$hf_repo" "$hf_file" "$hf_label" "$hf_family"
        ;;
      6|"__BACK__") return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 6." ;;
    esac
  done
}

show_diagnostics_menu() {
  while true; do
    choice="$(run_dashboard_menu "Diagnostics" "Pregled zdravlja, logova i bundle exporta." \
      1 "Health details" \
      2 "View logs" \
      3 "Export diagnostics" \
      4 "Benchmark pregled" \
      5 "Nazad")" || return
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
    print(f"Poslednje merenje: prompt {current.get('promptTokensPerSecond', 0)} tok/s | output {current.get('completionTokensPerSecond', 0)} tok/s | total {current.get('totalTokensPerSecond', 0)} tok/s")
    print(f"Prosek total: {payload.get('averages', {}).get('totalTokensPerSecond', 0)} tok/s")
PY
)" ;;
      5) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 5." ;;
    esac
  done
}

show_settings_menu() {
  while true; do
    choice="$(run_dashboard_menu "Settings" "Promena profila i runtime podesavanja." \
      1 "Promeni profil" \
      2 "Promeni context" \
      3 "Promeni output" \
      4 "Promeni stepove" \
      5 "Promeni working dir" \
      6 "Quick presets" \
      7 "Nazad")" || return
    case "$choice" in
      1) run_external_terminal_action_or_inline "Promeni profil" "$SCRIPT_DIR/settings-tui.sh" profile ;;
      2) run_external_terminal_action_or_inline "Promeni context" "$SCRIPT_DIR/settings-tui.sh" context ;;
      3) run_external_terminal_action_or_inline "Promeni output" "$SCRIPT_DIR/settings-tui.sh" output ;;
      4) run_external_terminal_action_or_inline "Promeni stepove" "$SCRIPT_DIR/settings-tui.sh" steps ;;
      5) run_external_terminal_action_or_inline "Promeni working dir" "$SCRIPT_DIR/settings-tui.sh" workdir ;;
      6) run_external_terminal_action_or_inline "Quick presets" "$SCRIPT_DIR/settings-tui.sh" presets ;;
      7) return ;;
      *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 7." ;;
    esac
  done
}

show_home_menu() {
  run_dashboard_menu "Home" "$(build_home_prompt)" \
    1 "Pokretanje" \
    2 "Modeli" \
    3 "Tools" \
    4 "Diagnostics" \
    5 "Settings" \
    6 "Exit"
}

while true; do
  choice="$(show_home_menu)" || exit 0
  case "$choice" in
    1) show_launch_menu ;;
    2) show_models_menu ;;
    3) show_tools_menu ;;
    4) show_diagnostics_menu ;;
    5) show_settings_menu ;;
    6) exit 0 ;;
    "__BACK__") continue ;;
    *) show_warning_screen "Nepoznat izbor" "Izaberi opciju od 1 do 6." ;;
  esac
done
