#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

show_status() {
  python3 - <<'PY' "$(get_effective_service_status_json)" "$(get_health_url)"
import json, sys
status = json.loads(sys.argv[1])
health_url = sys.argv[2]
state = status.get("state", "inactive")
reason = status.get("reason", "")
if state == "active":
    print(f"Status: server aktivan na {health_url}")
elif state == "warming":
    print("Status: STARTING / WARMING - servis se jos podize")
elif state == "failed":
    print(f"Status: start nije uspeo - {reason}")
else:
    print("Status: server nije aktivan")
PY
}

show_quick_panel() {
  python3 - <<'PY' "$(get_effective_service_status_json)" "$(get_install_state_path)" "$(get_settings_path)" "$(get_token_metrics_summary_json)" "$HOME/.config/opencode/opencode.json"
import json, os, sys
status = json.loads(sys.argv[1])
state_path, settings_path, throughput_json, opencode_config = sys.argv[2:6]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)
throughput = json.loads(throughput_json)
current = throughput.get("current")
print("Quick status")
print(f"- Server: {status.get('title', status.get('state', 'unknown'))}")
print(f"- Health: {'ok' if status.get('state') == 'active' else 'not-ready'}")
print(f"- OpenCode: {'config ok' if os.path.isfile(opencode_config) else 'nema config'}")
print(f"- Model: {state.get('modelId', 'n/a')}")
if current:
    print(f"- Throughput: {current.get('totalTokensPerSecond', 0)} tok/s (last)")
else:
    print("- Throughput: nema podataka")
print(f"- Profil: {settings.get('profile', 'balanced')}")
PY
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

show_agent_audit() {
  python3 - <<'PY' "$(get_local_qwen_root)/state/agent-launch-settings.json" "$(get_saved_working_directory)" "$(get_runtime_engine_path)"
import json, os, subprocess, sys
meta_path, fallback_workdir, runtime_script = sys.argv[1:4]
security = "strict"
capability = "confirm-commands"
workdir = fallback_workdir
if os.path.exists(meta_path):
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    security = meta.get("securityMode", security)
    capability = meta.get("capabilityMode", capability)
    workdir = meta.get("workingFolder", workdir)
payload = subprocess.run(
    [sys.executable, runtime_script, "agent-audit", "--security-mode", security, "--capability-mode", capability, "--working-folder", workdir],
    capture_output=True,
    text=True,
    check=True,
)
audit = json.loads(payload.stdout)
print(f"Agent risk: {audit['riskLevel']}")
for reason in audit["reasons"]:
    print(f"- {reason}")
PY
}

show_onboarding() {
  python3 - <<'PY' "$(get_install_state_path)" "$(get_settings_path)" "$(get_runtime_engine_path)" "$(get_health_url)" "$HOME/.config/opencode/opencode.json"
import json, os, subprocess, sys, urllib.request
state_path, settings_path, runtime_script, health_url, opencode_config = sys.argv[1:6]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)
has_server = False
try:
    with urllib.request.urlopen(health_url, timeout=3) as response:
        has_server = response.status == 200
except Exception:
    pass
model_path = state.get("modelFile", "")
has_model = os.path.isfile(model_path)
has_opencode = os.path.isfile(opencode_config)
payload = subprocess.run(
    [
        sys.executable,
        runtime_script,
        "onboarding-checklist",
        "--has-server", str(has_server).lower(),
        "--has-model", str(has_model).lower(),
        "--has-opencode-config", str(has_opencode).lower(),
        "--profile", settings.get("profile", "balanced"),
        "--model-id", state.get("modelId", "n/a"),
    ],
    capture_output=True,
    text=True,
    check=True,
)
data = json.loads(payload.stdout)
print(f"Onboarding ready: {'yes' if data['ready'] else 'no'}")
for step in data["steps"]:
    prefix = "[OK]" if step["status"] == "done" else "[ ]"
    print(f"{prefix} {step['title']}")
PY
}

show_next_action() {
  python3 - <<'PY' "$(get_install_state_path)" "$(get_runtime_engine_path)" "$(get_health_url)" "$HOME/.config/opencode/opencode.json"
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
print(f"Next action: {data['title']}")
print(f"Reason: {data['reason']}")
print(f"Action id: {data['actionId']}")
PY
}

show_diagnostics() {
  python3 - <<'PY' "$(get_effective_service_status_json)" "$(get_service_lifecycle_json)" "$(get_install_state_path)" "$(get_settings_path)" "$(get_runtime_engine_path)" "$(get_local_qwen_root)/version.json"
import json, os, subprocess, sys
status_json, lifecycle_json, state_path, settings_path, runtime_script, version_path = sys.argv[1:7]
status = json.loads(status_json)
lifecycle = json.loads(lifecycle_json)
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)
current_version = "unknown"
if os.path.exists(version_path):
    try:
        with open(version_path, "r", encoding="utf-8") as f:
            current_version = json.load(f).get("version", "unknown")
    except Exception:
        pass
payload = subprocess.run(
    [sys.executable, runtime_script, "latest-release", "--repo", "joes021/Local-Qwen-3.635Ba3B-on-home-computer", "--current-version", current_version],
    capture_output=True,
    text=True,
)
latest = None
if payload.returncode == 0 and payload.stdout.strip():
    try:
        latest = json.loads(payload.stdout)
    except Exception:
        latest = None
print("Diagnostics")
print(f"- Effective state: {status.get('state')}")
print(f"- Effective reason: {status.get('reason')}")
print(f"- Lifecycle state: {lifecycle.get('state')}")
print(f"- Lifecycle updated: {lifecycle.get('updatedAt')}")
print(f"- Stdout log: {lifecycle.get('stdout')}")
print(f"- Stderr log: {lifecycle.get('stderr')}")
print(f"- Profile: {settings.get('profile')}")
print(f"- Model: {state.get('modelId')}")
if latest:
    print(f"- GitHub latest: {latest.get('latestVersion')}")
    print(f"- Update available: {'da' if latest.get('updateAvailable') else 'ne'}")
PY
}

show_throughput() {
  python3 - <<'PY' "$(get_token_metrics_summary_json)"
import json, sys
payload = json.loads(sys.argv[1])
current = payload.get("current")
print("Token throughput")
if not current:
    print("- Jos nema benchmark merenja. Pokreni test prompt.")
else:
    print(f"- Poslednje merenje: prompt {current.get('promptTokensPerSecond', 0)} tok/s | output {current.get('completionTokensPerSecond', 0)} tok/s | total {current.get('totalTokensPerSecond', 0)} tok/s | total {current.get('totalMs', 0)} ms")
    print(f"- Prosek: prompt {payload.get('averages', {}).get('promptTokensPerSecond', 0)} tok/s | output {payload.get('averages', {}).get('completionTokensPerSecond', 0)} tok/s | total {payload.get('averages', {}).get('totalTokensPerSecond', 0)} tok/s")
    history = payload.get("history", [])
    for item in history:
        print(f"- {item.get('measuredAt')}: in {item.get('promptTokensPerSecond', 0)} tok/s | out {item.get('completionTokensPerSecond', 0)} tok/s | total {item.get('totalTokensPerSecond', 0)} tok/s")
PY
}

get_next_action_id() {
  python3 - <<'PY' "$(get_install_state_path)" "$(get_runtime_engine_path)" "$(get_health_url)" "$HOME/.config/opencode/opencode.json"
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
print(json.loads(payload.stdout)["actionId"])
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
  show_quick_panel
  show_status
  show_settings
  show_hardware
  show_agent_audit
  show_onboarding
  show_next_action
  show_diagnostics
  show_throughput
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
  echo "15) Agent audit"
  echo "16) Run next action"
  echo "17) Refresh diagnostics only"
  echo "18) Exit"
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
    15) "$SCRIPT_DIR/agent-audit.sh" ;;
    16)
      next_action="$(get_next_action_id)"
      case "$next_action" in
        repair-install) "$SCRIPT_DIR/repair-install.sh" ;;
        start-server) "$SCRIPT_DIR/start-server.sh" ;;
        write-opencode-config) "$SCRIPT_DIR/configure-settings.sh" ;;
        open-opencode) "$SCRIPT_DIR/start-opencode.sh" ;;
        *) echo "Nepoznat next action: $next_action" ;;
      esac
      ;;
    17) show_diagnostics ;;
    18) exit 0 ;;
    *) echo "Nepoznat izbor." ;;
  esac
done
