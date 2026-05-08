#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

PROFILE="${1:-}"
ROOT="$(get_local_qwen_root)"
STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
DEFAULTS_PATH="$(get_defaults_path)"

if [ -z "$PROFILE" ]; then
  PROFILE="$(get_saved_profile)"
fi

python3 - <<'PY' "$STATE_PATH" "$SETTINGS_PATH" "$DEFAULTS_PATH" "$PROFILE"
import json, os, subprocess, sys, time

state_path, settings_path, defaults_path, profile = sys.argv[1:5]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

profile_data = defaults["profiles"][profile]
ctx = settings["llama"]["contextSize"]
out_tokens = settings["llama"]["maxOutputTokens"]
server = state.get("turboServerExe") or state["llamaServerExe"]
model = state["modelFile"]
port = state["port"]
threads = state["threads"]
gpu_layers = 999
uses_turbo = bool(state.get("turboServerExe")) and os.path.abspath(server) == os.path.abspath(state["turboServerExe"])

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
        ctx = min(ctx, 4096)
        out_tokens = min(out_tokens, 1024)
    elif detected_vram_mib is not None and detected_vram_mib <= 12288:
        gpu_layers = 20
        ctx = min(ctx, 8192)
        out_tokens = min(out_tokens, 2048)
    elif detected_vram_mib is not None:
        gpu_layers = 28
        ctx = min(ctx, 16384)
        out_tokens = min(out_tokens, 4096)
    else:
        gpu_layers = 20
        ctx = min(ctx, 8192)
        out_tokens = min(out_tokens, 2048)

args = [
    server, "-m", model, "--port", str(port),
    "-ngl", str(gpu_layers),
    "-ncmoe", str(profile_data["ncmoe"]),
    "-c", str(ctx),
    "-fa", "on",
    "-n", str(out_tokens),
    "-t", str(threads),
]
if uses_turbo:
    args.extend(["-ctk", profile_data["cacheTypeK"], "-ctv", profile_data["cacheTypeV"]])
if state.get("noMmap", True):
    args.append("--no-mmap")
if state.get("mlock", True):
    args.append("--mlock")

log_dir = os.path.join(state["installRoot"], "logs")
os.makedirs(log_dir, exist_ok=True)
stamp = time.strftime("%Y%m%d-%H%M%S")
stdout_path = os.path.join(log_dir, f"llama-{profile}-{stamp}.out.log")
stderr_path = os.path.join(log_dir, f"llama-{profile}-{stamp}.err.log")

with open(stdout_path, "wb") as out, open(stderr_path, "wb") as err:
    subprocess.Popen(args, stdout=out, stderr=err, start_new_session=True)

print(f"llama.cpp start requested for profile {profile}")
print(f"stdout: {stdout_path}")
print(f"stderr: {stderr_path}")
PY
