#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path


def load_defaults(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def normalize_models(defaults: dict) -> list[dict]:
    models = []
    for key, raw in defaults.get("modelChoices", {}).items():
        item = dict(raw)
        item.setdefault("key", key)
        item.setdefault("label", item.get("id", key))
        item.setdefault("sources", [])
        if item.get("source"):
            item["sources"] = [{"repo": item["source"], "filename": item["filename"]}] + item["sources"]
        deduped = []
        seen = set()
        for source in item["sources"]:
            fingerprint = (source.get("repo"), source.get("filename"))
            if fingerprint in seen:
                continue
            seen.add(fingerprint)
            deduped.append(source)
        item["sources"] = deduped
        models.append(item)
    return models


def choose_profile(gpu_mib: int | None) -> tuple[str, str, str]:
    if not gpu_mib or gpu_mib <= 0:
        return (
            "balanced",
            "unknown",
            "GPU VRAM nije ocitan, pa sistem ostaje na srednjem fallback profilu.",
        )
    if gpu_mib <= 8192:
        return (
            "speed",
            "8GB-or-lower",
            "GPU do 8 GB najbolje prolazi sa manjim context/output pritiskom.",
        )
    if gpu_mib <= 12288:
        return (
            "balanced",
            "12GB-class",
            "GPU do 12 GB je ciljana preporucena klasa za ovaj setup.",
        )
    return (
        "video",
        "above-12GB",
        "Jaci GPU moze da nosi agresivniji profil i kvalitetniji kvant bez istog pritiska.",
    )


def score_model(model: dict, gpu_mib: int | None, ram_gib: int | None, profile: str) -> tuple[float, list[str]]:
    score = 0.0
    reasons: list[str] = []
    recommended_gpu = int(model.get("recommendedGpuMiB", 0) or 0)
    minimum_ram = int(model.get("minimumRamGiB", 0) or 0)
    approx_size = float(model.get("approxSizeGiB", 0) or 0)
    preferred_profiles = set(model.get("preferredProfiles", []))

    if gpu_mib and recommended_gpu:
        gap = gpu_mib - recommended_gpu
        if gap >= 0:
            score += 60
            score += min(20, gap / 1024)
            reasons.append(f"GPU ima dovoljno VRAM-a za {model['label']}.")
        else:
            score -= min(40, abs(gap) / 512)
            reasons.append(f"GPU je ispod ciljane VRAM preporuke za {model['label']}.")

    if ram_gib and minimum_ram:
        if ram_gib >= minimum_ram:
            score += 25
            reasons.append("Sistemski RAM je dovoljno veliki za ovaj model.")
        else:
            score -= 30
            reasons.append("Sistemski RAM je nizak za ovaj model.")

    if preferred_profiles and profile in preferred_profiles:
        score += 20
        reasons.append(f"Model je prirodan fit za profil '{profile}'.")

    if approx_size > 0:
        score += max(0, 15 - approx_size / 2)

    quality_tier = str(model.get("qualityTier", "compact"))
    if quality_tier == "quality":
        score += 12 if gpu_mib and gpu_mib > 16384 else -4
    elif quality_tier == "compact":
        score += 8 if gpu_mib and gpu_mib <= 12288 else 1

    return score, reasons


def build_recommendation(defaults: dict, gpu_mib: int | None, ram_gib: int | None, cpu_threads: int | None) -> dict:
    recommended_profile, detected_class, reason = choose_profile(gpu_mib)
    models = normalize_models(defaults)
    scored = []
    for model in models:
        score, model_reasons = score_model(model, gpu_mib, ram_gib, recommended_profile)
        scored.append(
            {
                "model": model,
                "score": round(score, 2),
                "reasons": model_reasons,
            }
        )

    scored.sort(key=lambda item: item["score"], reverse=True)
    selected = scored[0] if scored else None
    return {
        "recommendedProfile": recommended_profile,
        "detectedClass": detected_class,
        "reason": reason,
        "recommendedModel": selected["model"] if selected else None,
        "candidateScores": scored,
        "hardware": {
            "gpuMiB": gpu_mib,
            "ramGiB": ram_gib,
            "cpuThreads": cpu_threads,
        },
    }


def command_catalog(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    print(json.dumps({"models": normalize_models(defaults)}, indent=2))
    return 0


def command_recommend(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    payload = build_recommendation(defaults, args.gpu_mib, args.ram_gib, args.cpu_threads)
    print(json.dumps(payload, indent=2))
    return 0


def command_latest_release(args: argparse.Namespace) -> int:
    import urllib.request

    url = f"https://api.github.com/repos/{args.repo}/releases/latest"
    request = urllib.request.Request(url, headers={"User-Agent": "local-qwen-runtime"})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode("utf-8"))
    tag_name = payload.get("tag_name", "").lstrip("v")
    print(
        json.dumps(
            {
                "currentVersion": args.current_version,
                "latestVersion": tag_name,
                "updateAvailable": bool(tag_name and tag_name != args.current_version),
                "releaseUrl": payload.get("html_url"),
            },
            indent=2,
        )
    )
    return 0


def audit_agent_risk(security_mode: str, capability_mode: str, working_folder: str) -> dict:
    score = 0
    reasons: list[str] = []
    normalized = working_folder.replace("/", "\\").lower()

    if security_mode == "open":
        score += 4
        reasons.append("Otvoren security mode dozvoljava izlazak van radnog foldera.")
    elif security_mode == "blacklist":
        score += 2
        reasons.append("Blacklist mode je srednji nivo zastite i zavisi od deny pravila.")
    else:
        reasons.append("Strict mode drzi agenta unutar radnog foldera.")

    if capability_mode == "auto-commands":
        score += 5
        reasons.append("Auto command mode dozvoljava samostalno izvrsavanje komandi.")
    elif capability_mode == "confirm-commands":
        score += 3
        reasons.append("Command mode uz potvrdu je umereno rizican.")
    elif capability_mode == "read-write":
        score += 1
        reasons.append("Read-write mod menja fajlove, ali bez shell komandi.")
    else:
        reasons.append("Read-only mod ne menja fajlove i ne izvrsava komande.")

    if normalized in {"c:\\", "c:"} or normalized.startswith("\\\\"):
        score += 3
        reasons.append("Radni folder obuhvata ceo sistem ili veoma sirok opseg.")
    elif normalized.endswith("\\desktop") or normalized.endswith("\\documents"):
        score += 1
        reasons.append("Radni folder je sirok korisnicki opseg.")
    else:
        reasons.append("Radni folder izgleda ciljano i ograniceno.")

    if score >= 8:
        risk = "high"
    elif score >= 4:
        risk = "medium"
    else:
        risk = "low"

    return {
        "securityMode": security_mode,
        "capabilityMode": capability_mode,
        "workingFolder": working_folder,
        "riskLevel": risk,
        "riskScore": score,
        "requiresWarning": risk != "low",
        "reasons": reasons,
    }


def command_agent_audit(args: argparse.Namespace) -> int:
    payload = audit_agent_risk(args.security_mode, args.capability_mode, args.working_folder)
    print(json.dumps(payload, indent=2))
    return 0


def parse_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def build_onboarding_checklist(has_server: bool, has_model: bool, has_opencode_config: bool, profile: str, model_id: str) -> dict:
    steps = [
        {
            "id": "server",
            "title": f"Pokreni llama.cpp server za profil '{profile}'",
            "status": "done" if has_server else "todo",
        },
        {
            "id": "model",
            "title": f"Proveri da je model '{model_id}' dostupan i potpun",
            "status": "done" if has_model else "todo",
        },
        {
            "id": "opencode",
            "title": "Upisi ili proveri OpenCode konfiguraciju",
            "status": "done" if has_opencode_config else "todo",
        },
        {
            "id": "smoke-test",
            "title": "Posalji test prompt i proveri /health",
            "status": "done" if (has_server and has_model) else "todo",
        },
    ]
    ready = all(step["status"] == "done" for step in steps)
    return {
        "ready": ready,
        "profile": profile,
        "modelId": model_id,
        "steps": steps,
    }


def command_onboarding_checklist(args: argparse.Namespace) -> int:
    payload = build_onboarding_checklist(
        has_server=parse_bool(args.has_server),
        has_model=parse_bool(args.has_model),
        has_opencode_config=parse_bool(args.has_opencode_config),
        profile=args.profile,
        model_id=args.model_id,
    )
    print(json.dumps(payload, indent=2))
    return 0


def decide_next_action(has_server: bool, has_model: bool, has_opencode_config: bool) -> dict:
    if not has_model:
        return {
            "actionId": "repair-install",
            "title": "Pokreni repair install",
            "reason": "Model nedostaje ili nije potpun, pa je repair najbrzi put do zdravog stanja.",
        }
    if not has_server:
        return {
            "actionId": "start-server",
            "title": "Pokreni llama.cpp server",
            "reason": "Model postoji, ali server jos nije aktivan.",
        }
    if not has_opencode_config:
        return {
            "actionId": "write-opencode-config",
            "title": "Upisi OpenCode config",
            "reason": "Server radi, ali OpenCode jos nema vezu ka lokalnom endpointu.",
        }
    return {
        "actionId": "open-opencode",
        "title": "Otvori OpenCode",
        "reason": "Osnovne komponente su spremne za rad.",
    }


def command_next_action(args: argparse.Namespace) -> int:
    payload = decide_next_action(
        has_server=parse_bool(args.has_server),
        has_model=parse_bool(args.has_model),
        has_opencode_config=parse_bool(args.has_opencode_config),
    )
    print(json.dumps(payload, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Shared runtime helper for Local Qwen installers and launchers.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    catalog = subparsers.add_parser("catalog")
    catalog.add_argument("--defaults", required=True)
    catalog.set_defaults(func=command_catalog)

    recommend = subparsers.add_parser("recommend")
    recommend.add_argument("--defaults", required=True)
    recommend.add_argument("--gpu-mib", type=int, default=0)
    recommend.add_argument("--ram-gib", type=int, default=0)
    recommend.add_argument("--cpu-threads", type=int, default=0)
    recommend.set_defaults(func=command_recommend)

    latest = subparsers.add_parser("latest-release")
    latest.add_argument("--repo", required=True)
    latest.add_argument("--current-version", required=True)
    latest.set_defaults(func=command_latest_release)

    audit = subparsers.add_parser("agent-audit")
    audit.add_argument("--security-mode", required=True, choices=["strict", "blacklist", "open"])
    audit.add_argument("--capability-mode", required=True, choices=["read-only", "read-write", "confirm-commands", "auto-commands"])
    audit.add_argument("--working-folder", required=True)
    audit.set_defaults(func=command_agent_audit)

    onboarding = subparsers.add_parser("onboarding-checklist")
    onboarding.add_argument("--has-server", required=True)
    onboarding.add_argument("--has-model", required=True)
    onboarding.add_argument("--has-opencode-config", required=True)
    onboarding.add_argument("--profile", required=True)
    onboarding.add_argument("--model-id", required=True)
    onboarding.set_defaults(func=command_onboarding_checklist)

    next_action = subparsers.add_parser("next-action")
    next_action.add_argument("--has-server", required=True)
    next_action.add_argument("--has-model", required=True)
    next_action.add_argument("--has-opencode-config", required=True)
    next_action.set_defaults(func=command_next_action)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
