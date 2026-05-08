#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

show_status() {
  if test_llama_health; then
    echo "Status: server aktivan na $(get_health_url)"
  else
    echo "Status: server nije aktivan"
  fi
}

show_settings() {
  python3 - <<'PY' "$(get_settings_path)" "$(get_install_state_path)"
import json, os, sys
settings_path, state_path = sys.argv[1:3]
settings = {}
state = {}
if os.path.exists(settings_path):
    with open(settings_path, "r", encoding="utf-8") as f:
        settings = json.load(f)
if os.path.exists(state_path):
    with open(state_path, "r", encoding="utf-8") as f:
        state = json.load(f)
print(f"Profil: {settings.get('profile', 'balanced')}")
print(f"Context: {settings.get('llama', {}).get('contextSize', 'n/a')}")
print(f"Output: {settings.get('llama', {}).get('maxOutputTokens', 'n/a')}")
print(f"Build steps: {settings.get('opencode', {}).get('buildSteps', 'n/a')}")
print(f"Plan steps: {settings.get('opencode', {}).get('planSteps', 'n/a')}")
print(f"General steps: {settings.get('opencode', {}).get('generalSteps', 'n/a')}")
print(f"Explore steps: {settings.get('opencode', {}).get('exploreSteps', 'n/a')}")
print(f"Working dir: {settings.get('opencode', {}).get('workingDirectory', os.path.expanduser('~'))}")
print(f"Model: {state.get('modelFile', 'n/a')}")
PY
}

show_hardware() {
  python3 - <<'PY' "$(get_install_state_path)" "$(get_settings_path)" "$(get_defaults_path)" "$(get_runtime_engine_path)"
import json, os, subprocess, sys

state_path, settings_path, defaults_path, runtime_script = sys.argv[1:5]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

gpu_name = "n/a"
gpu_mem = 0
try:
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
        capture_output=True,
        text=True,
        check=True,
    )
    first = result.stdout.strip().splitlines()[0]
    parts = [p.strip() for p in first.split(",")]
    gpu_name = parts[0]
    gpu_mem = int(parts[1])
except Exception:
    pass

cpu_name = "n/a"
try:
    with open("/proc/cpuinfo", "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if line.lower().startswith("model name"):
                cpu_name = line.split(":", 1)[1].strip()
                break
except Exception:
    pass

ram_gib = 0
try:
    with open("/proc/meminfo", "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                ram_gib = round(int(line.split()[1]) / 1024 / 1024)
                break
except Exception:
    pass

payload = subprocess.run(
    [sys.executable, runtime_script, "recommend", "--defaults", defaults_path, "--gpu-mib", str(gpu_mem), "--ram-gib", str(ram_gib), "--cpu-threads", str(os.cpu_count() or 0)],
    capture_output=True,
    text=True,
    check=True,
)
recommendation = json.loads(payload.stdout)

print(f"GPU: {gpu_name} ({gpu_mem if gpu_mem else 'n/a'} MiB)")
print(f"CPU: {cpu_name}")
print(f"RAM: {ram_gib if ram_gib else 'n/a'} GiB")
print(f"Detected class: {recommendation['detectedClass']}")
print(f"Recommended profile: {recommendation['recommendedProfile']}")
print(f"Recommended model: {recommendation['recommendedModel']['id']}")
print(f"Active profile: {settings.get('profile', 'balanced')}")
print(f"Active model: {state.get('modelId', 'n/a')}")
print(f"Why: {recommendation['reason']}")
PY
}

while true; do
  echo
  echo "Local Qwen Control Center"
  show_status
  show_settings
  show_hardware
  echo "1) Start server (saved profile)"
  echo "2) Start server (choose profile)"
  echo "3) Stop server"
  echo "4) Configure settings"
  echo "5) Build runtime"
  echo "6) Write OpenCode config"
  echo "7) Start OpenCode"
  echo "8) Verify install"
  echo "9) View logs"
  echo "10) Repair install"
  echo "11) Test prompt"
  echo "12) Model manager"
  echo "13) Export diagnostics"
  echo "14) Check updates"
  echo "15) Exit"
  read -r -p "Izbor: " choice

  case "$choice" in
    1) "$SCRIPT_DIR/start-server.sh" ;;
    2) read -r -p "Profil (speed/balanced/video): " profile; "$SCRIPT_DIR/start-server.sh" "${profile:-balanced}" ;;
    3) "$SCRIPT_DIR/stop-server.sh" ;;
    4) "$SCRIPT_DIR/settings-tui.sh" ;;
    5) "$SCRIPT_DIR/build-runtime.sh" ;;
    6) "$SCRIPT_DIR/configure-settings.sh" ;;
    7) "$SCRIPT_DIR/start-opencode.sh" ;;
    8) "$SCRIPT_DIR/verify-install.sh" ;;
    9) "$SCRIPT_DIR/show-logs.sh" ;;
    10) "$SCRIPT_DIR/repair-install.sh" ;;
    11) "$SCRIPT_DIR/test-prompt.sh" ;;
    12) "$SCRIPT_DIR/manage-models.sh" ;;
    13) "$SCRIPT_DIR/export-diagnostics.sh" ;;
    14) "$SCRIPT_DIR/check-updates.sh" ;;
    15) exit 0 ;;
    *) echo "Nepoznat izbor." ;;
  esac
done
