#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ACTION="${1:-list}"
shift || true
MODEL_ID=""
if [[ "$ACTION" != "list" && "$ACTION" != "recommend" && "$#" -gt 0 && "${1:-}" != --* ]]; then
  MODEL_ID="$1"
  shift || true
fi

SEARCH=""
FAMILY=""
INSTALLED_ONLY=0
RECOMMENDED_ONLY=0
FIT_ONLY=0
CODER_ONLY=0
VERIFIED_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --search)
      SEARCH="${2:-}"
      shift 2
      ;;
    --family)
      FAMILY="${2:-}"
      shift 2
      ;;
    --installed-only)
      INSTALLED_ONLY=1
      shift
      ;;
    --recommended-only)
      RECOMMENDED_ONLY=1
      shift
      ;;
    --fit-only)
      FIT_ONLY=1
      shift
      ;;
    --coder-only)
      CODER_ONLY=1
      shift
      ;;
    --verified-only)
      VERIFIED_ONLY=1
      shift
      ;;
    *)
      echo "Nepoznat argument: $1"
      exit 1
      ;;
  esac
done

STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
DEFAULTS_PATH="$(get_defaults_path)"
ROOT="$(get_local_qwen_root)"
MODELS_DIR="$ROOT/models"

get_installed_model_sizes_json() {
  python3 - <<'PY' "$DEFAULTS_PATH" "$MODELS_DIR"
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
  python3 - <<'PY' "$MODELS_DIR"
import os, shutil, sys
path = sys.argv[1]
os.makedirs(path, exist_ok=True)
usage = shutil.disk_usage(path)
print(round(usage.free / (1024 ** 3), 2))
PY
}

get_recommended_model_id() {
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
  get_recommendation_json "$gpu_mib" "$ram_gib" "$cpu_threads" | python3 - <<'PY'
import json, sys
print(json.load(sys.stdin)["recommendedModel"]["id"])
PY
}

get_download_candidates_for_current_machine() {
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
  get_download_candidates_json "$gpu_mib" "$ram_gib" "$cpu_threads"
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

  local extra_args=()
  [[ "$INSTALLED_ONLY" -eq 1 ]] && extra_args+=(--installed-only)
  [[ "$RECOMMENDED_ONLY" -eq 1 ]] && extra_args+=(--recommended-only)
  [[ "$FIT_ONLY" -eq 1 ]] && extra_args+=(--fit-only)
  [[ "$CODER_ONLY" -eq 1 ]] && extra_args+=(--coder-only)
  [[ "$VERIFIED_ONLY" -eq 1 ]] && extra_args+=(--verified-only)

  get_model_browser_json "$gpu_mib" "$ram_gib" "$cpu_threads" "$current_model_id" "$installed_ids" "$installed_sizes_json" "$free_disk_gib" "$SEARCH" "$FAMILY" "${extra_args[@]}"
}

select_model() {
  local selected_id="$1"
  python3 - <<'PY' "$STATE_PATH" "$DEFAULTS_PATH" "$selected_id" "$MODELS_DIR" "$SETTINGS_PATH"
import json, os, sys
state_path, defaults_path, selected_id, models_dir, settings_path = sys.argv[1:6]
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)
models = defaults.get("modelChoices", {})
meta = None
for item in models.values():
    if item.get("id") == selected_id or item.get("filename") == selected_id:
        meta = item
        break
if meta is None:
    raise SystemExit(f"Model nije pronadjen: {selected_id}")
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
state["modelId"] = meta["id"]
state["modelFile"] = os.path.join(models_dir, meta["filename"])
with open(state_path, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
if os.path.exists(settings_path):
    with open(settings_path, "r", encoding="utf-8") as f:
        settings = json.load(f)
else:
    settings = {}
settings.setdefault("model", {})
settings["model"]["selectedId"] = meta["id"]
with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2)
print(state["modelFile"])
PY
}

case "$ACTION" in
  list)
    current_id="$(python3 - <<'PY' "$STATE_PATH"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelId", ""))
PY
)"
    recommended_id="$(get_recommended_model_id)"
    installed_ids="$(get_installed_model_ids_csv)"
    installed_sizes_json="$(get_installed_model_sizes_json)"
    free_disk_gib="$(get_free_disk_gib)"
    echo "Aktivni model: $current_id"
    echo "Preporuceni model: $recommended_id"
    get_model_browser_for_current_machine "$current_id" "$installed_ids" "$installed_sizes_json" "$free_disk_gib" | python3 - <<'PY' "$current_id" "$recommended_id"
import json, sys
current_id, recommended_id = sys.argv[1:3]
payload = json.load(sys.stdin)
print(f"Hardverska klasa: {payload.get('detectedClass')}")
print(f"Preporucen profil: {payload.get('recommendedProfile')}")
print()
print(f"Model browser: {len(payload.get('models', []))} vidljivih modela")
for item in payload.get("models", []):
    marker = "*" if item.get("active") else "+" if item.get("recommended") else "-"
    status = []
    if item.get("installed"):
        status.append("installed")
    if item.get("recommended"):
        status.append("recommended")
    status.append(item.get("fitGroup"))
    if item.get("useCaseBadges"):
        status.append("badge=" + "|".join(item.get("useCaseBadges")))
    print(f"{marker} {item.get('id')} | {item.get('family')} | {item.get('approxSizeGiB')} GiB | {'/'.join(status)} | Speed {item.get('speedEstimateLabel')} | Agentic {item.get('agenticScore')}/10 | OpenCode {item.get('opencodeFit')}/10")
    print(f"    Installed: {item.get('installedSizeGiB')} GiB | Need disk: {item.get('diskNeededGiB')} GiB | Free disk: {item.get('freeDiskGiB')} GiB | Enough disk: {'da' if item.get('hasEnoughDisk') else 'ne'}")
    print(f"    {item.get('description')}")
print()
print("* = trenutno aktivan model")
print("+ = preporucen model za ovaj hardver")
PY
    ;;
  compare)
    [ -n "$MODEL_ID" ] || { echo "Prosledi model id za compare."; exit 1; }
    gpu_mib="0"
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
    current_id="$(python3 - <<'PY' "$STATE_PATH"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelId", ""))
PY
)"
    recommended_id="$(get_recommended_model_id)"
    ids="$MODEL_ID,$current_id,$recommended_id"
    python3 "$(get_runtime_engine_path)" model-compare --defaults "$DEFAULTS_PATH" --gpu-mib "$gpu_mib" --ram-gib "$ram_gib" --cpu-threads "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)" --model-ids "$ids" | python3 - <<'PY'
import json, sys
payload = json.load(sys.stdin)
print("Model compare")
print(f"- Best speed: {payload.get('summary', {}).get('bestForSpeed')}")
print(f"- Best coding: {payload.get('summary', {}).get('bestForCoding')}")
print(f"- Best quality: {payload.get('summary', {}).get('bestForQuality')}")
for item in payload.get("models", []):
    print()
    print(item.get("id"))
    print(f"  Family: {item.get('family')} | Speed: {item.get('speedEstimateLabel')} | Agentic: {item.get('agenticScore')}/10 | OpenCode: {item.get('opencodeFit')}/10")
    print(f"  Size: {item.get('approxSizeGiB')} GiB | Fit: {item.get('fitGroup')} | Badge: {', '.join(item.get('useCaseBadges', []))}")
PY
    ;;
  use)
    [ -n "$MODEL_ID" ] || { echo "Prosledi model id."; exit 1; }
    path="$(select_model "$MODEL_ID")"
    echo "Model postavljen na: $MODEL_ID"
    echo "Model path: $path"
    "$SCRIPT_DIR/configure-settings.sh" >/dev/null
    ;;
  recommend)
    recommended_id="$(get_recommended_model_id)"
    path="$(select_model "$recommended_id")"
    echo "Preporuceni model je aktiviran: $recommended_id"
    echo "Model path: $path"
    "$SCRIPT_DIR/configure-settings.sh" >/dev/null
    ;;
  download)
    if [ -n "$MODEL_ID" ]; then
      path="$(select_model "$MODEL_ID")"
      echo "Model postavljen na: $MODEL_ID"
      echo "Model path: $path"
    fi
    INSTALL_ROOT="$ROOT" SKIP_RUNTIME_BUILD=1 bash "$ROOT/install/linux/install.sh"
    ;;
  *)
    echo "Koriscenje: $0 [list|compare <model-id>|use <model-id>|recommend|download <model-id>] [--search tekst] [--family Gemma] [--installed-only] [--recommended-only] [--fit-only] [--coder-only] [--verified-only]"
    exit 1
    ;;
esac
