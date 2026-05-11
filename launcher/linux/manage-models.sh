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
MODEL_DOWNLOAD_VENV_DIR="$ROOT/state/model-download-venv"

get_model_metadata_json() {
  local selected_id="$1"
  python3 - <<'PY' "$DEFAULTS_PATH" "$selected_id"
import json, sys
defaults_path, selected_id = sys.argv[1:3]
with open(defaults_path, "r", encoding="utf-8-sig") as f:
    defaults = json.load(f)
for item in defaults.get("modelChoices", {}).values():
    if item.get("id") == selected_id or item.get("filename") == selected_id:
        print(json.dumps(item))
        raise SystemExit(0)
raise SystemExit(f"Model nije pronadjen: {selected_id}")
PY
}

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
size_gib = round(size_bytes / (1024 ** 3), 2)
if size_bytes > 0 and size_gib == 0:
    size_gib = 0.01
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
    "approxSizeGiB": size_gib,
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
datetime_mod = __import__("datetime")
registry.write_text(
    json.dumps(
        {
            "updatedAt": datetime_mod.datetime.now(datetime_mod.timezone.utc).isoformat(),
            "models": filtered,
        },
        ensure_ascii=False,
        indent=2,
    ),
    encoding="utf-8",
)
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
datetime_mod = __import__("datetime")
registry.write_text(
    json.dumps(
        {
            "updatedAt": datetime_mod.datetime.now(datetime_mod.timezone.utc).isoformat(),
            "models": filtered,
        },
        ensure_ascii=False,
        indent=2,
    ),
    encoding="utf-8",
)
print(json.dumps(model, ensure_ascii=False))
PY
}

download_huggingface_custom_model() {
  local meta_json="$1"
  local download_python="$2"
  local raw_output status filtered_output
  set +e
  raw_output="$("$download_python" - <<'PY' "$meta_json" "$MODELS_DIR" 2>&1
import json, sys
from pathlib import Path

meta = json.loads(sys.argv[1])
models_dir = Path(sys.argv[2])
filename = str(meta.get("filename", "") or "")
if not filename:
    raise SystemExit("HF custom model nema filename.")

sources = list(meta.get("sources") or [])
if not sources and meta.get("source"):
    sources = [{"repo": meta.get("source"), "filename": filename}]
if not sources:
    raise SystemExit("HF custom model nema izvor za download.")

target_path = models_dir / filename
min_expected = int(meta.get("minExpectedBytes", 0) or 0)
if target_path.is_file():
    current_size = target_path.stat().st_size
    if min_expected <= 0 or current_size >= min_expected:
        print(f"Model je vec prisutan: {target_path}")
        raise SystemExit(0)

import contextlib
import io
import warnings

warnings.filterwarnings(
    "ignore",
    message=r".*local_dir_use_symlinks.*deprecated.*",
    category=UserWarning,
)
warnings.filterwarnings(
    "ignore",
    message=r".*You are sending unauthenticated requests to the HF Hub.*",
    category=UserWarning,
)

try:
    from huggingface_hub import hf_hub_download
except Exception:
    raise SystemExit("huggingface_hub nije dostupan. Pokreni update/install tok ili instaliraj paket pa probaj ponovo.")

models_dir.mkdir(parents=True, exist_ok=True)
last_error = None
for item in sources:
    repo = str(item.get("repo", "") or "").strip()
    source_filename = str(item.get("filename", "") or filename).strip()
    if not repo or not source_filename:
        continue
    try:
        print(f"Preuzimam {source_filename} sa {repo} ...")
        with contextlib.redirect_stderr(io.StringIO()):
            hf_hub_download(
                repo_id=repo,
                filename=source_filename,
                local_dir=str(models_dir),
            )
        if not target_path.is_file():
            candidate = models_dir / source_filename
            if candidate.is_file():
                target_path = candidate
        if not target_path.is_file():
            raise RuntimeError(f"Download nije proizveo fajl: {target_path}")
        final_size = target_path.stat().st_size
        if min_expected > 0 and final_size < min_expected:
            raise RuntimeError(f"Model je skinut nepotpuno: {target_path}")
        print(f"HF model je preuzet: {target_path}")
        raise SystemExit(0)
    except Exception as exc:
        last_error = exc

if last_error is not None:
    raise SystemExit(str(last_error))
raise SystemExit("HF custom model nema validan izvor za download.")
PY
)"
  status=$?
  set -e
  filtered_output="$(RAW_OUTPUT="$raw_output" python3 - <<'PY'
import os
for line in os.environ.get("RAW_OUTPUT", "").splitlines():
    if "Warning: You are sending unauthenticated requests to the HF Hub." in line:
        continue
    print(line)
PY
)"
  if [ -n "$filtered_output" ]; then
    printf '%s\n' "$filtered_output"
  fi
  return "$status"
}

ensure_model_download_python() {
  local python_bin="$MODEL_DOWNLOAD_VENV_DIR/bin/python"
  if [ ! -x "$python_bin" ]; then
    python3 -m venv "$MODEL_DOWNLOAD_VENV_DIR"
  fi
  "$python_bin" -m pip install -U pip >/dev/null
  "$python_bin" -m pip install -U huggingface_hub >/dev/null
  printf '%s\n' "$python_bin"
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

def visible_badges(item):
    badges = list(item.get("useCaseBadges", []) or [])
    hidden = {"balanced-agentic"}
    badges = [badge for badge in badges if badge not in hidden]
    if "best-starter-model" in badges and "best-for-speed" in badges:
        badges = [badge for badge in badges if badge != "best-for-speed"]
    if "best-quality-model" in badges and "best-for-speed" in badges:
        badges = [badge for badge in badges if badge != "best-for-speed"]
    if "best-for-coding" in badges and "best-for-speed" in badges:
        badges = [badge for badge in badges if badge != "best-for-speed"]
    return badges

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
    fit_group = item.get("fitGroup")
    if fit_group and fit_group not in status:
        status.append(fit_group)
    badges = visible_badges(item)
    if badges:
        status.append("badge=" + "|".join(badges))
    approx_size = item.get("approxSizeGiB")
    if approx_size is None or float(approx_size) <= 0:
        size_text = "nepoznato"
    else:
        size_text = f"{approx_size} GiB"
    print(f"{marker} {item.get('id')} | {item.get('family')} | {size_text} | {'/'.join(status)} | Speed {item.get('speedEstimateLabel')} | Agentic {item.get('agenticScore')}/10 | OpenCode {item.get('opencodeFit')}/10")
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
    ids="$(python3 - <<'PY' "$MODEL_ID" "$current_id" "$recommended_id"
import sys
seen = []
for value in sys.argv[1:]:
    value = str(value or "").strip()
    if value and value not in seen:
        seen.append(value)
print(",".join(seen))
PY
)"
    compare_json="$(python3 "$(get_runtime_engine_path)" model-compare --defaults "$DEFAULTS_PATH" --gpu-mib "$gpu_mib" --ram-gib "$ram_gib" --cpu-threads "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)" --model-ids "$ids")"
    python3 - <<'PY' "$compare_json"
import json, sys
payload = json.loads(sys.argv[1])

def visible_badges(item):
    badges = list(item.get("useCaseBadges", []) or [])
    hidden = {"balanced-agentic"}
    badges = [badge for badge in badges if badge not in hidden]
    if "best-starter-model" in badges and "best-for-speed" in badges:
        badges = [badge for badge in badges if badge != "best-for-speed"]
    if "best-quality-model" in badges and "best-for-speed" in badges:
        badges = [badge for badge in badges if badge != "best-for-speed"]
    if "best-for-coding" in badges and "best-for-speed" in badges:
        badges = [badge for badge in badges if badge != "best-for-speed"]
    return badges

print("Model compare")
summary = payload.get('summary', {})
print(f"- Best speed: {summary.get('bestForSpeed') or 'nema jasnog favorita u ovom poredjenju'}")
print(f"- Best coding: {summary.get('bestForCoding') or 'nema jasnog favorita u ovom poredjenju'}")
print(f"- Best quality: {summary.get('bestForQuality') or 'nema jasnog favorita u ovom poredjenju'}")
for item in payload.get("models", []):
    print()
    print(item.get("id"))
    print(f"  Family: {item.get('family')} | Speed: {item.get('speedEstimateLabel')} | Agentic: {item.get('agenticScore')}/10 | OpenCode: {item.get('opencodeFit')}/10")
    print(f"  Size: {item.get('approxSizeGiB')} GiB | Fit: {item.get('fitGroup')} | Badge: {', '.join(visible_badges(item))}")
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
      meta_json="$(get_model_metadata_json "$MODEL_ID")"
      custom_source="$(python3 - <<'PY' "$meta_json"
import json, sys
print(json.loads(sys.argv[1]).get("customSource", ""))
PY
)"
      path="$(select_model "$MODEL_ID")"
      echo "Model postavljen na: $MODEL_ID"
      echo "Model path: $path"
      case "$custom_source" in
        huggingface)
          download_python="$(ensure_model_download_python)"
          download_huggingface_custom_model "$meta_json" "$download_python"
          "$SCRIPT_DIR/configure-settings.sh" >/dev/null
          exit 0
          ;;
        local-file)
          if [ -f "$path" ]; then
            echo "Lokalni model je vec prisutan: $path"
            "$SCRIPT_DIR/configure-settings.sh" >/dev/null
            exit 0
          fi
          echo "Lokalni model nije pronadjen na ocekivanoj putanji: $path"
          exit 1
          ;;
      esac
    fi
    install_script="$(get_local_qwen_install_script_path || true)"
    if [ -z "${install_script:-}" ] || [ ! -f "$install_script" ]; then
      echo "Linux install skripta nije pronadjena za model download tok."
      echo "Ocekivana putanja: ~/local-qwen-home/install/linux/install.sh"
      exit 1
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
