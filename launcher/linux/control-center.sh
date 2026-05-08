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
  python3 - <<'PY' "$(get_install_state_path)" "$(get_settings_path)" "$(get_defaults_path)"
import json, os, subprocess, sys

state_path, settings_path, defaults_path = sys.argv[1:4]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)

gpu_name = "n/a"
gpu_mem = None
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

ram_gib = "n/a"
try:
    with open("/proc/meminfo", "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                kib = int(line.split()[1])
                ram_gib = round(kib / 1024 / 1024)
                break
except Exception:
    pass

profile = settings.get("profile", "balanced")
recommended = "balanced"
reason = "GPU VRAM nije ocitan, pa sistem ostaje na srednjem fallback-u."
detected_class = "unknown"
if gpu_mem is not None and gpu_mem <= 8192:
    detected_class = "8GB-or-lower"
    recommended = "speed"
    reason = "GPU do 8 GB najvise dobija od manjeg context/output opterecenja."
elif gpu_mem is not None and gpu_mem <= 12288:
    detected_class = "12GB-class"
    recommended = "balanced"
    reason = "GPU do 12 GB je ciljana preporucena klasa za ovaj setup."
elif gpu_mem is not None:
    detected_class = "above-12GB"
    recommended = "video"
    reason = "Jaci GPU moze da gura agresivniji profil i visi context."

print(f"GPU: {gpu_name} ({gpu_mem if gpu_mem is not None else 'n/a'} MiB)")
print(f"CPU: {cpu_name}")
print(f"RAM: {ram_gib} GiB")
print(f"Detected class: {detected_class}")
print(f"Recommended profile: {recommended}")
print(f"Active profile: {profile}")
print(f"Why: {reason}")
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
  echo "10) Exit"
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
    10) exit 0 ;;
    *) echo "Nepoznat izbor." ;;
  esac
done
