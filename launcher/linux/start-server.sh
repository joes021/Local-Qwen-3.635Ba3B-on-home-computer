#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

PROFILE="${1:-}"
ROOT="$(get_local_qwen_root)"
STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
DEFAULTS_PATH="$(get_defaults_path)"
TURBOQUANT_CONFIG_PATH="$(get_turboquant_config_path)"

if [ -z "$PROFILE" ]; then
  PROFILE="$(get_saved_profile)"
fi

if test_llama_health; then
  lifecycle_json="$(get_service_lifecycle_json)"
  stdout_path="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("stdout", "") or "")
PY
)"
  stderr_path="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("stderr", "") or "")
PY
)"
  set_service_lifecycle_state "active" "$PROFILE" "$stdout_path" "$stderr_path" "Health endpoint je vec aktivan."
  echo "llama.cpp server je vec aktivan na $(get_health_url)"
  exit 0
fi

python3 - <<'PY' "$STATE_PATH" "$SETTINGS_PATH" "$DEFAULTS_PATH" "$PROFILE" "$TURBOQUANT_CONFIG_PATH"
import json, os, subprocess, sys, time

state_path, settings_path, defaults_path, profile, turboquant_config_path = sys.argv[1:6]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)
turboquant_config = {}
if turboquant_config_path and os.path.isfile(turboquant_config_path):
    try:
        with open(turboquant_config_path, "r", encoding="utf-8-sig") as f:
            turboquant_config = json.load(f)
    except Exception:
        turboquant_config = {}

profile_data = defaults["profiles"][profile]
ctx = int(turboquant_config.get("context") or settings["llama"]["contextSize"])
out_tokens = settings["llama"]["maxOutputTokens"]
context_customized = settings.get("llama", {}).get("contextSizeCustomized")
if context_customized is None:
    context_customized = int(ctx) != int(profile_data["contextSize"])
else:
    context_customized = bool(context_customized)

output_customized = settings.get("llama", {}).get("maxOutputTokensCustomized")
if output_customized is None:
    output_customized = int(out_tokens) != 8192
else:
    output_customized = bool(output_customized)

runtime_preference = str(turboquant_config.get("runtimePreference") or "turboquant").strip().lower()
if runtime_preference == "llama.cpp":
    server = state["llamaServerExe"]
else:
    server = state.get("turboServerExe") or state["llamaServerExe"]
model = state["modelFile"]
port = state["port"]
threads = state["threads"]
gpu_layers = 999
uses_turbo = bool(state.get("turboServerExe")) and os.path.abspath(server) == os.path.abspath(state["turboServerExe"])
ncmoe = int(turboquant_config.get("ncmoe") or profile_data["ncmoe"])
cache_type_k = str(turboquant_config.get("ctk") or profile_data["cacheTypeK"])
cache_type_v = str(turboquant_config.get("ctv") or profile_data["cacheTypeV"])
flash_attention = bool(turboquant_config.get("flashAttention", True))
mlock = bool(turboquant_config.get("mlock", state.get("mlock", True)))
mmap_mode = str(turboquant_config.get("mmapMode") or ("no-mmap" if state.get("noMmap", True) else "mmap")).strip().lower()

if not uses_turbo:
    detected_vram_mib = None
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.total", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            check=True,
        )
        first_line = result.stdout.strip().splitlines()[0]
        detected_vram_mib = int(first_line.strip())
    except Exception:
        detected_vram_mib = None

    if detected_vram_mib is not None and detected_vram_mib <= 8192:
        gpu_layers = 10
        if not context_customized:
            ctx = min(ctx, 4096)
        if not output_customized:
            out_tokens = min(out_tokens, 1024)
    elif detected_vram_mib is not None and detected_vram_mib <= 12288:
        gpu_layers = 20
        if not context_customized:
            ctx = min(ctx, 8192)
        if not output_customized:
            out_tokens = min(out_tokens, 2048)
    elif detected_vram_mib is not None:
        gpu_layers = 28
        if not context_customized:
            ctx = min(ctx, 16384)
        if not output_customized:
            out_tokens = min(out_tokens, 4096)
    else:
        gpu_layers = 20
        if not context_customized:
            ctx = min(ctx, 8192)
        if not output_customized:
            out_tokens = min(out_tokens, 2048)

args = [
    server, "-m", model, "--port", str(port),
    "-ngl", str(gpu_layers),
    "-ncmoe", str(ncmoe),
    "-c", str(ctx),
    "-fa", "on" if flash_attention else "off",
    "-n", str(out_tokens),
    "-t", str(threads),
]
if uses_turbo:
    args.extend(["-ctk", cache_type_k, "-ctv", cache_type_v])
if mmap_mode == "no-mmap":
    args.append("--no-mmap")
if mlock:
    args.append("--mlock")

log_dir = os.path.join(state["installRoot"], "logs")
os.makedirs(log_dir, exist_ok=True)
stamp = time.strftime("%Y%m%d-%H%M%S")
stdout_path = os.path.join(log_dir, f"llama-{profile}-{stamp}.out.log")
stderr_path = os.path.join(log_dir, f"llama-{profile}-{stamp}.err.log")
lifecycle_path = os.path.join(state["installRoot"], "state", "server-lifecycle.json")
os.makedirs(os.path.dirname(lifecycle_path), exist_ok=True)
with open(lifecycle_path, "w", encoding="utf-8") as f:
    json.dump({
        "state": "starting",
        "profile": profile,
        "stdout": stdout_path,
        "stderr": stderr_path,
        "reason": "llama.cpp startup requested",
        "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }, f, ensure_ascii=False, indent=2)

with open(stdout_path, "wb") as out, open(stderr_path, "wb") as err:
    subprocess.Popen(args, stdout=out, stderr=err, start_new_session=True)

print(f"llama.cpp start requested for profile {profile}")
print(f"stdout: {stdout_path}")
print(f"stderr: {stderr_path}")
PY

(
  deadline=$((SECONDS + 180))
  while [ "$SECONDS" -lt "$deadline" ]; do
    sleep 3
    if test_llama_health; then
      lifecycle_json="$(get_service_lifecycle_json)"
      stdout_path="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("stdout", "") or "")
PY
)"
      stderr_path="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("stderr", "") or "")
PY
)"
      set_service_lifecycle_state "active" "$PROFILE" "$stdout_path" "$stderr_path" "Health endpoint returned OK."
      exit 0
    fi
  done
  lifecycle_json="$(get_service_lifecycle_json)"
  stdout_path="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("stdout", "") or "")
PY
)"
  stderr_path="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("stderr", "") or "")
PY
)"
  set_service_lifecycle_state "timeout" "$PROFILE" "$stdout_path" "$stderr_path" "Health endpoint nije postao dostupan u roku od 180 sekundi."
) >/dev/null 2>&1 &
