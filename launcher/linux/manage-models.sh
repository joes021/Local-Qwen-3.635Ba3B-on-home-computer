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
POSITIONAL_ARGS=()

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
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
DEFAULTS_PATH="$(get_defaults_path)"
ROOT="$(get_local_qwen_root)"
MODELS_DIR="$ROOT/models"
CUSTOM_MODELS_PATH="$(get_custom_models_registry_path)"

import_local_gguf_model() {
  local source_path="$1"
  local label="${2:-}"
  local family="${3:-Custom}"
  python3 - <<'PY' "$source_path" "$label" "$family" "$MODELS_DIR" "$CUSTOM_MODELS_PATH"
import json, os, shutil, sys
from pathlib import Path
source_path, label, family, models_dir, registry_path = sys.argv[1:6]
src = Path(source_path)
if not src.exists():
    raise SystemExit(f"Lokalni GGUF nije pronadjen: {source_path}")
if src.suffix.lower() != ".gguf":
    raise SystemExit("Podrzani su samo .gguf fajlovi.")
models = []
registry = Path(registry_path)
if registry.exists():
    try:
        payload = json.loads(registry.read_text(encoding="utf-8-sig"))
        models = payload.get("models", []) or []
    except Exception:
        models = []
target_dir = Path(models_dir)
target_dir.mkdir(parents=True, exist_ok=True)
target_path = target_dir / src.name
if src.resolve() != target_path.resolve():
    shutil.copy2(src, target_path)
size_bytes = target_path.stat().st_size
friendly = label.strip() or target_path.stem
family_text = family.strip() or "Custom"
token = __import__("re").sub(r"[^a-zA-Z0-9_-]+", "_", target_path.stem or "custom")
model = {
    "key": token,
    "id": target_path.name,
    "label": friendly,
    "family": family_text,
    "agenticScore": 6,
    "opencodeFit": 6,
    "useCase": "agentic-general",
    "filename": target_path.name,
    "minExpectedBytes": int(size_bytes),
    "approxSizeGiB": round(size_bytes / (1024 ** 3), 2),
    "minimumGpuMiB": 0,
    "recommendedGpuMiB": 0,
    "minimumRamGiB": 8,
    "preferredProfiles": ["speed", "balanced"],
    "qualityTier": "compact",
    "curationLevel": "custom",
    "description": "Rucno dodat lokalni GGUF model.",
    "customSource": "local-file",
    "originalPath": str(src),
    "sources": [],
}
filtered = [item for item in models if str(item.get("id")) != model["id"]]
filtered.append(model)
registry.parent.mkdir(parents=True, exist_ok=True)
registry.write_text(json.dumps({"updatedAt": __import__("datetime").datetime.utcnow().isoformat() + "Z", "models": filtered}, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(model, ensure_ascii=False))
PY
}

add_huggingface_custom_model() {
  local repo="$1"
  local file_name="$2"
  local label="${3:-}"
  local family="${4:-Custom}"
  python3 - <<'PY' "$repo" "$file_name" "$label" "$family" "$CUSTOM_MODELS_PATH"
import json, sys, urllib.request
from pathlib import Path
repo, file_name, label, family, registry_path = sys.argv[1:6]
repo = repo.strip()
file_name = file_name.strip()
if not repo or not file_name:
    raise SystemExit("Repo i filename su obavezni.")
if not file_name.lower().endswith(".gguf"):
    raise SystemExit("HF model mora da pokazuje na .gguf fajl.")
url = f"https://huggingface.co/{repo}/resolve/main/{file_name}"
size_bytes = 0
try:
    request = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(request, timeout=15) as response:
        size_bytes = int(response.headers.get("Content-Length") or 0)
except Exception:
    size_bytes = 0
registry = Path(registry_path)
models = []
if registry.exists():
    try:
        payload = json.loads(registry.read_text(encoding="utf-8-sig"))
        models = payload.get("models", []) or []
    except Exception:
        models = []
friendly = label.strip() or Path(file_name).stem
family_text = family.strip() or "Custom"
repo_token = __import__("re").sub(r"[^a-zA-Z0-9_-]+", "_", repo)
file_token = __import__("re").sub(r"[^a-zA-Z0-9_-]+", "_", Path(file_name).stem or "custom")
model = {
    "key": f"hf-{repo_token}-{file_token}",
    "id": f"hf-{repo_token}-{file_name}",
    "label": friendly,
    "family": family_text,
    "agenticScore": 6,
    "opencodeFit": 6,
    "useCase": "agentic-general",
    "source": repo,
    "filename": file_name,
    "minExpectedBytes": int(size_bytes * 0.9) if size_bytes > 0 else 0,
    "approxSizeGiB": round(size_bytes / (1024 ** 3), 2) if size_bytes > 0 else 0.0,
    "minimumGpuMiB": 0,
    "recommendedGpuMiB": 0,
    "minimumRamGiB": 8,
    "preferredProfiles": ["speed", "balanced"],
    "qualityTier": "compact",
    "curationLevel": "custom",
    "description": "Rucno dodat Hugging Face GGUF model.",
    "customSource": "huggingface",
    "sources": [{"repo": repo, "filename": file_name}],
}
filtered = [item for item in models if str(item.get("id")) != model["id"]]
filtered.append(model)
registry.parent.mkdir(parents=True, exist_ok=True)
registry.write_text(json.dumps({"updatedAt": __import__("datetime").datetime.utcnow().isoformat() + "Z", "models": filtered}, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(model, ensure_ascii=False))
PY
}

get_installed_model_sizes_json() {
  local defaults_path
  defaults_path="$(get_defaults_path)"
  python3 - <<'PY' "$defaults_path" "$MODELS_DIR"
import json, os, sys
defaults_path, models_dir = sys.argv[1:3]
with open(defaults_path, "r", encoding="utf-8-sig") as f:
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
  local recommendation_json
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
  recommendation_json="$(get_recommendation_json "$gpu_mib" "$ram_gib" "$cpu_threads")"
  python3 - <<'PY' "$recommendation_json"
import json, sys
print(json.loads(sys.argv[1])["recommendedModel"]["id"])
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
    model_browser_json="$(get_model_browser_for_current_machine "$current_id" "$installed_ids" "$installed_sizes_json" "$free_disk_gib")"
    python3 - <<'PY' "$current_id" "$recommended_id" "$model_browser_json"
import json, sys
current_id, recommended_id, payload_json = sys.argv[1:4]
payload = json.loads(payload_json)
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
    if item.get("installed"):
        installed_value = item.get("installedSizeGiB")
        if installed_value and float(installed_value) > 0:
            installed_text = f"{installed_value} GiB"
        else:
            installed_text = "nepoznato"
    else:
        installed_text = "nije skinut"
    need_disk = item.get("diskNeededGiB")
    free_disk = item.get("freeDiskGiB")
    enough_disk = item.get("hasEnoughDisk")
    need_disk_text = f"{need_disk} GiB" if need_disk is not None else "nepoznato"
    free_disk_text = f"{free_disk} GiB" if free_disk is not None else "nepoznato"
    enough_disk_text = "da" if enough_disk is True else "ne" if enough_disk is False else "nepoznato"
    print(f"    Installed: {installed_text} | Need disk: {need_disk_text} | Free disk: {free_disk_text} | Enough disk: {enough_disk_text}")
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
    compare_json="$(python3 "$(get_runtime_engine_path)" model-compare --defaults "$DEFAULTS_PATH" --gpu-mib "$gpu_mib" --ram-gib "$ram_gib" --cpu-threads "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)" --model-ids "$ids")"
    python3 - <<'PY' "$compare_json"
import json, sys
payload = json.loads(sys.argv[1])
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
    install_script="$(get_local_qwen_install_script_path || true)"
    if [ -z "${install_script:-}" ] || [ ! -f "$install_script" ]; then
      echo "Linux install skripta nije pronadjena za model download tok."
      echo "Ocekivana putanja: ~/local-qwen-home/install/linux/install.sh"
      exit 1
    fi
    if [ -n "$MODEL_ID" ]; then
      path="$(select_model "$MODEL_ID")"
      echo "Model postavljen na: $MODEL_ID"
      echo "Model path: $path"
    fi
    INSTALL_ROOT="$ROOT" \
    MODEL_ID="${MODEL_ID:-}" \
    SKIP_RUNTIME_BUILD=1 \
    LOCAL_QWEN_SKIP_PACKAGE_INSTALL=1 \
    LOCAL_QWEN_SKIP_SOURCE_CLONE=1 \
    LOCAL_QWEN_SKIP_OPENCODE_INSTALL=1 \
    bash "$install_script"
    ;;
  add-local)
    [ -n "$MODEL_ID" ] || { echo "Prosledi putanju do lokalnog GGUF fajla."; exit 1; }
    label="${POSITIONAL_ARGS[0]:-}"
    family="${POSITIONAL_ARGS[1]:-Custom}"
    result_json="$(import_local_gguf_model "$MODEL_ID" "$label" "$family")"
    model_file="$(python3 - <<'PY' "$result_json"
import json, sys
payload = json.loads(sys.argv[1])
print(payload.get("id", ""))
PY
)"
    echo "Lokalni model dodat: $model_file"
    ;;
  add-hf)
    [ -n "$MODEL_ID" ] || { echo "Prosledi HF repo."; exit 1; }
    hf_file="${POSITIONAL_ARGS[0]:-}"
    [ -n "$hf_file" ] || { echo "Prosledi HF filename."; exit 1; }
    label="${POSITIONAL_ARGS[1]:-}"
    family="${POSITIONAL_ARGS[2]:-Custom}"
    result_json="$(add_huggingface_custom_model "$MODEL_ID" "$hf_file" "$label" "$family")"
    model_file="$(python3 - <<'PY' "$result_json"
import json, sys
payload = json.loads(sys.argv[1])
print(payload.get("id", ""))
PY
)"
    echo "HF model dodat: $model_file"
    ;;
  *)
    echo "Koriscenje: $0 [list|compare <model-id>|use <model-id>|recommend|download <model-id>|add-local <putanja> [label] [family]|add-hf <repo> <filename> [label] [family]] [--search tekst] [--family Gemma] [--installed-only] [--recommended-only] [--fit-only] [--coder-only] [--verified-only]"
    exit 1
    ;;
esac
