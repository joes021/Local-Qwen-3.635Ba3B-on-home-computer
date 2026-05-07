#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

STATE_PATH="$(get_install_state_path)"
DEFAULTS_PATH="$(get_defaults_path)"

python3 - <<'PY' "$STATE_PATH" "$DEFAULTS_PATH"
import json
import os
import shutil
import subprocess
import sys

state_path, defaults_path = sys.argv[1:3]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)

llama_source = state["llamaSourceDir"]
turbo_source = state["turboDir"]
build_generator = defaults.get("linuxBuild", {}).get("generator", "Ninja")

def run(cmd, cwd=None, allow_fail=False):
    print("+", " ".join(cmd))
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0 and not allow_fail:
        raise SystemExit(result.returncode)
    return result.returncode == 0

def find_server(root):
    for current_root, _, files in os.walk(root):
        if "llama-server" in files:
            return os.path.join(current_root, "llama-server")
    return ""

cuda_available = shutil.which("nvcc") is not None
cmake_args = ["cmake", "-G", build_generator]

llama_build_dir = os.path.join(llama_source, "build")
os.makedirs(llama_build_dir, exist_ok=True)
llama_config = cmake_args + ["-S", llama_source, "-B", llama_build_dir]
llama_config.append("-DGGML_CUDA=ON" if cuda_available else "-DGGML_CUDA=OFF")
run(llama_config)
run(["cmake", "--build", llama_build_dir, "-j"])

llama_server = find_server(llama_build_dir)
if not llama_server:
    raise SystemExit("llama-server nije pronadjen nakon build-a upstream llama.cpp")

state["llamaBuildDir"] = llama_build_dir
state["llamaServerExe"] = llama_server

if cuda_available:
    turbo_build_dir = os.path.join(turbo_source, defaults["turboquant"]["buildDir"])
    os.makedirs(turbo_build_dir, exist_ok=True)
    turbo_config = cmake_args + ["-S", turbo_source, "-B", turbo_build_dir, "-DGGML_CUDA=ON"]
    if run(turbo_config, allow_fail=True) and run(["cmake", "--build", turbo_build_dir, "-j"], allow_fail=True):
        turbo_server = find_server(turbo_build_dir)
        if turbo_server:
            state["turboBuildDir"] = turbo_build_dir
            state["turboServerExe"] = turbo_server

state["cudaAvailableAtBuild"] = cuda_available
with open(state_path, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)

print("llamaServerExe:", state["llamaServerExe"])
print("turboServerExe:", state.get("turboServerExe", ""))
PY
