#!/usr/bin/env python3
import argparse
import json
import math
import re
from datetime import datetime, timezone
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
        item.setdefault("family", "Other")
        item.setdefault("agenticScore", 5)
        item.setdefault("opencodeFit", 5)
        item.setdefault("useCase", "agentic-general")
        item.setdefault("curationLevel", "supported")
        item.setdefault("minimumGpuMiB", item.get("recommendedGpuMiB", 0) or 0)
        item.setdefault("primaryRecommendation", False)
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
    minimum_gpu = int(model.get("minimumGpuMiB", 0) or 0)
    recommended_gpu = int(model.get("recommendedGpuMiB", 0) or 0)
    minimum_ram = int(model.get("minimumRamGiB", 0) or 0)
    approx_size = float(model.get("approxSizeGiB", 0) or 0)
    preferred_profiles = set(model.get("preferredProfiles", []))
    agentic_score = int(model.get("agenticScore", 5) or 5)
    opencode_fit = int(model.get("opencodeFit", 5) or 5)
    curation_level = str(model.get("curationLevel", "supported"))
    primary_recommendation = bool(model.get("primaryRecommendation", False))

    score += agentic_score * 3
    score += opencode_fit * 4
    if primary_recommendation:
        score += 18
        reasons.append("Ovo je primarni preporuceni model za Local Qwen setup.")

    if curation_level == "verified":
        score += 12
        reasons.append("Kurirani verified izbor za agentic/OpenCode rad.")
    elif curation_level == "experimental":
        score -= 4
        reasons.append("Model je oznacen kao eksperimentalni izbor.")

    if gpu_mib and minimum_gpu and gpu_mib < minimum_gpu:
        score -= 60
        reasons.append(f"GPU je ispod minimalnog praga za {model['label']}.")
    elif gpu_mib and recommended_gpu:
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


def classify_download_group(model: dict, gpu_mib: int | None, ram_gib: int | None, score: float) -> tuple[str, list[str]]:
    reasons: list[str] = []
    minimum_gpu = int(model.get("minimumGpuMiB", 0) or 0)
    recommended_gpu = int(model.get("recommendedGpuMiB", 0) or 0)
    minimum_ram = int(model.get("minimumRamGiB", 0) or 0)
    agentic_score = int(model.get("agenticScore", 5) or 5)
    opencode_fit = int(model.get("opencodeFit", 5) or 5)

    if minimum_gpu and gpu_mib and gpu_mib < minimum_gpu:
        reasons.append("GPU je ispod minimalnog praga.")
        return "notRecommended", reasons
    if minimum_ram and ram_gib and ram_gib < minimum_ram:
        reasons.append("RAM je ispod minimalnog praga.")
        return "notRecommended", reasons

    if recommended_gpu and gpu_mib and gpu_mib >= recommended_gpu and agentic_score >= 7 and opencode_fit >= 7:
        reasons.append("Hardver i agentic/OpenCode fit su dobri za ovu masinu.")
        return "recommended", reasons

    if score >= 35:
        reasons.append("Model moze da radi uz kompromis u brzini, kontekstu ili izlazu.")
        return "canRun", reasons

    reasons.append("Model je vidljiv radi orijentacije, ali nije preporucen za ovu konfiguraciju.")
    return "notRecommended", reasons


def build_download_candidates(defaults: dict, gpu_mib: int | None, ram_gib: int | None, cpu_threads: int | None) -> dict:
    recommendation = build_recommendation(defaults, gpu_mib, ram_gib, cpu_threads)
    groups = {
        "recommended": [],
        "canRun": [],
        "notRecommended": [],
    }

    for candidate in recommendation["candidateScores"]:
        model = dict(candidate["model"])
        group, extra_reasons = classify_download_group(model, gpu_mib, ram_gib, float(candidate["score"]))
        groups[group].append(
            {
                **model,
                "score": candidate["score"],
                "fitGroup": group,
                "fitReasons": candidate["reasons"] + extra_reasons,
            }
        )

    for key in groups:
        groups[key].sort(key=lambda item: float(item.get("score", 0)), reverse=True)

    return {
        "recommendedProfile": recommendation["recommendedProfile"],
        "detectedClass": recommendation["detectedClass"],
        "reason": recommendation["reason"],
        "hardware": recommendation["hardware"],
        "recommendedModel": recommendation["recommendedModel"],
        "groups": groups,
    }


def filter_models(
    defaults: dict,
    gpu_mib: int | None,
    ram_gib: int | None,
    cpu_threads: int | None,
    verified_only: bool = False,
    coder_only: bool = False,
    fit_only: bool = False,
) -> dict:
    catalog = normalize_models(defaults)
    download_candidates = build_download_candidates(defaults, gpu_mib, ram_gib, cpu_threads)
    fit_ids: set[str] = set()
    for group_name in ("recommended", "canRun"):
        for item in download_candidates["groups"].get(group_name, []):
            fit_ids.add(str(item.get("id")))

    visible_models: list[dict] = []
    for model in catalog:
        if verified_only and str(model.get("curationLevel", "")).lower() != "verified":
            continue
        if coder_only:
            family = str(model.get("family", "")).lower()
            use_case = str(model.get("useCase", "")).lower()
            label = str(model.get("label", "")).lower()
            if "coder" not in family and "code" not in use_case and "coder" not in label:
                continue
        if fit_only and str(model.get("id")) not in fit_ids:
            continue
        visible_models.append(model)

    return {
        "recommendedProfile": download_candidates["recommendedProfile"],
        "detectedClass": download_candidates["detectedClass"],
        "reason": download_candidates["reason"],
        "hardware": download_candidates["hardware"],
        "recommendedModel": download_candidates["recommendedModel"],
        "appliedFilters": {
            "verifiedOnly": verified_only,
            "coderOnly": coder_only,
            "fitOnly": fit_only,
        },
        "models": visible_models,
    }


def resolve_install_model(
    defaults: dict,
    gpu_mib: int | None,
    ram_gib: int | None,
    cpu_threads: int | None,
    current_model_id: str | None = None,
    current_model_complete: bool = False,
    skip_model_download: bool = False,
    available_complete_model_ids: list[str] | None = None,
) -> dict:
    recommendation = build_recommendation(defaults, gpu_mib, ram_gib, cpu_threads)
    catalog = normalize_models(defaults)
    by_id = {str(item.get("id")): item for item in catalog}
    recommended_model = recommendation["recommendedModel"]
    available_complete_model_ids = [str(item) for item in (available_complete_model_ids or []) if str(item)]

    if skip_model_download and current_model_complete and current_model_id and str(current_model_id) in by_id:
        return {
            "selectionMode": "preserve-existing",
            "reason": "Refresh bez model downloada zadrzava vec kompletan lokalni model umesto prepisivanja na novu preporuku.",
            "selectedModel": by_id[str(current_model_id)],
            "recommendedModel": recommended_model,
            "hardware": recommendation["hardware"],
        }

    if skip_model_download and available_complete_model_ids:
        if recommended_model and str(recommended_model.get("id")) in available_complete_model_ids:
            chosen_id = str(recommended_model.get("id"))
        else:
            chosen_id = available_complete_model_ids[0]
        if chosen_id in by_id:
            return {
                "selectionMode": "reuse-local-complete",
                "reason": "Aktivni model nije zdrav, ali postoji vec kompletan lokalni model pa refresh bez downloada prelazi na njega.",
                "selectedModel": by_id[chosen_id],
                "recommendedModel": recommended_model,
                "hardware": recommendation["hardware"],
            }

    return {
        "selectionMode": "recommended",
        "reason": "Koristi se trenutna hardverska preporuka modela.",
        "selectedModel": recommended_model,
        "recommendedModel": recommended_model,
        "hardware": recommendation["hardware"],
    }


def build_model_browser(
    defaults: dict,
    gpu_mib: int | None,
    ram_gib: int | None,
    cpu_threads: int | None,
    current_model_id: str | None = None,
    installed_model_ids: list[str] | None = None,
    installed_model_sizes: dict[str, int] | None = None,
    free_disk_gib: float | None = None,
    search: str = "",
    family: str = "",
    installed_only: bool = False,
    recommended_only: bool = False,
    fit_only: bool = False,
    coder_only: bool = False,
    verified_only: bool = False,
) -> dict:
    recommendation = build_recommendation(defaults, gpu_mib, ram_gib, cpu_threads)
    download_candidates = build_download_candidates(defaults, gpu_mib, ram_gib, cpu_threads)
    installed_set = {str(item) for item in (installed_model_ids or []) if str(item)}
    installed_model_sizes = {str(key): int(value) for key, value in (installed_model_sizes or {}).items()}
    if free_disk_gib is not None and free_disk_gib < 0:
        free_disk_gib = None
    current_model_id = str(current_model_id or "")
    search = str(search or "").strip().lower()
    family = str(family or "").strip().lower()

    fit_map: dict[str, str] = {}
    for group_name in ("recommended", "canRun", "notRecommended"):
        for item in download_candidates["groups"].get(group_name, []):
            fit_map[str(item.get("id"))] = group_name

    visible: list[dict] = []
    for model in normalize_models(defaults):
        model_id = str(model.get("id"))
        model_family = str(model.get("family", ""))
        use_case = str(model.get("useCase", ""))
        label = str(model.get("label", ""))
        fit_group = fit_map.get(model_id, "unknown")
        installed = model_id in installed_set
        active = bool(current_model_id and model_id == current_model_id)
        recommended = bool(recommendation.get("recommendedModel") and recommendation["recommendedModel"].get("id") == model_id)

        if search:
            haystack = " ".join([model_id, label, model_family, use_case, str(model.get("description", ""))]).lower()
            if search not in haystack:
                continue
        if family and model_family.lower() != family:
            continue
        if installed_only and not installed:
            continue
        if recommended_only and not recommended:
            continue
        if fit_only and fit_group not in {"recommended", "canRun"}:
            continue
        if coder_only and "coder" not in model_family.lower() and "code" not in use_case.lower() and "coder" not in label.lower():
            continue
        if verified_only and str(model.get("curationLevel", "")).lower() != "verified":
            continue

        entry = dict(model)
        badges: list[str] = []
        quality_tier = str(model.get("qualityTier", "")).lower()
        use_case_lower = use_case.lower()
        installed_size_bytes = int(installed_model_sizes.get(model_id, 0))
        approx_size_bytes = int(float(model.get("approxSizeGiB", 0) or 0) * (1024 ** 3))
        disk_needed_bytes = max(0, approx_size_bytes - installed_size_bytes)
        disk_needed_gib = round(disk_needed_bytes / (1024 ** 3), 2) if disk_needed_bytes > 0 else 0.0

        if "code" in use_case_lower or "coder" in model_family.lower() or "coder" in label.lower():
            badges.append("best-for-coding")
            badges.append("best-coding-model")
        if quality_tier == "quality":
            badges.append("best-quality")
            badges.append("best-quality-model")
        if quality_tier == "compact" and int(model.get("recommendedGpuMiB", 0) or 0) <= 8192:
            badges.append("best-for-speed")
        if model.get("primaryRecommendation"):
            badges.append("balanced-agentic")
            badges.append("best-starter-model")
        if "reason" in use_case_lower:
            badges.append("reasoning")

        if fit_group == "recommended":
            speed_label = "brzo" if quality_tier == "compact" and (not gpu_mib or gpu_mib <= 8192) else "stabilno"
        elif fit_group == "canRun":
            speed_label = "umereno"
        else:
            speed_label = "sporo / rizicno"

        speed_reason = (
            "Dobar fit za ovu masinu i mali kvant."
            if speed_label == "brzo"
            else "Treba malo vise prostora ili VRAM-a, ali deluje upotrebljivo."
            if speed_label == "umereno"
            else "Ovaj izbor je veci ili tezi od idealnog fit-a za ovu masinu."
        )

        entry["installed"] = installed
        entry["active"] = active
        entry["recommended"] = recommended
        entry["fitGroup"] = fit_group
        entry["useCaseBadges"] = list(dict.fromkeys(badges))
        entry["installedSizeBytes"] = installed_size_bytes
        entry["installedSizeGiB"] = round(installed_size_bytes / (1024 ** 3), 2) if installed_size_bytes > 0 else 0.0
        entry["diskNeededBytes"] = disk_needed_bytes
        entry["diskNeededGiB"] = disk_needed_gib
        entry["freeDiskGiB"] = round(float(free_disk_gib), 2) if free_disk_gib is not None else None
        entry["hasEnoughDisk"] = True if free_disk_gib is None else bool(float(free_disk_gib) >= disk_needed_gib)
        entry["speedEstimateLabel"] = speed_label
        entry["speedEstimateReason"] = speed_reason
        entry["statusTags"] = [
            tag
            for tag, enabled in (
                ("installed", installed),
                ("active", active),
                ("recommended", recommended),
                ("fit", fit_group in {"recommended", "canRun"}),
                ("verified", str(model.get("curationLevel", "")).lower() == "verified"),
            )
            if enabled
        ]
        visible.append(entry)

    return {
        "recommendedProfile": recommendation["recommendedProfile"],
        "detectedClass": recommendation["detectedClass"],
        "reason": recommendation["reason"],
        "hardware": recommendation["hardware"],
        "recommendedModel": recommendation["recommendedModel"],
        "appliedFilters": {
            "search": search,
            "family": family,
            "installedOnly": installed_only,
            "recommendedOnly": recommended_only,
            "fitOnly": fit_only,
            "coderOnly": coder_only,
            "verifiedOnly": verified_only,
        },
        "models": visible,
    }


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


def build_settings_presets(defaults: dict, gpu_mib: int | None, ram_gib: int | None, cpu_threads: int | None) -> dict:
    recommendation = build_recommendation(defaults, gpu_mib, ram_gib, cpu_threads)
    recommended_profile = str(recommendation.get("recommendedProfile") or "balanced")
    recommended_model = recommendation.get("recommendedModel") or {}
    recommended_model_label = str(recommended_model.get("label") or "trenutna preporuka")
    recommended_model_id = str(recommended_model.get("id") or "")
    defaults_steps = defaults.get("opencode", {}).get("steps", {})
    default_build = int(defaults_steps.get("build", 120) or 120)
    default_plan = int(defaults_steps.get("plan", 80) or 80)
    default_general = int(defaults_steps.get("general", 100) or 100)
    default_explore = int(defaults_steps.get("explore", 60) or 60)

    strong_hardware = bool((gpu_mib or 0) >= 16384 or (ram_gib or 0) >= 32)
    medium_hardware = bool((gpu_mib or 0) >= 8192 or (ram_gib or 0) >= 24)

    best_current_context = int(defaults.get("profiles", {}).get(recommended_profile, {}).get("contextSize", 262144) or 262144)
    best_current_output = 8192
    best_current_build = default_build
    best_current_plan = default_plan
    best_current_general = default_general
    best_current_explore = default_explore
    best_current_summary = f"Prati trenutnu preporuku za ovu masinu: profil '{recommended_profile}' i model '{recommended_model_label}'."

    if recommended_profile == "speed":
        best_current_context = 131072
        best_current_output = 6144
        best_current_build = 120
        best_current_plan = 80
        best_current_general = 100
        best_current_explore = 60
    elif recommended_profile == "balanced":
        best_current_context = 262144
        best_current_output = 8192
        best_current_build = 130
        best_current_plan = 90
        best_current_general = 110
        best_current_explore = 70
    elif recommended_profile == "video":
        best_current_context = 262144
        best_current_output = 12288
        best_current_build = 150
        best_current_plan = 100
        best_current_general = 120
        best_current_explore = 80
        best_current_summary = f"Prati video-klasu preporuke za ovu masinu i koristi agresivniji preset uz model '{recommended_model_label}'."

    long_context_profile = "video" if strong_hardware else "balanced"
    long_context_context = 327680 if strong_hardware else 262144
    long_context_output = 12288 if strong_hardware else 8192

    presets = [
        {
            "id": "laptop-safe",
            "title": "Laptop safe",
            "profile": "speed",
            "contextSize": 65536 if not medium_hardware else 131072,
            "maxOutputTokens": 4096 if not medium_hardware else 6144,
            "buildSteps": 80,
            "planSteps": 60,
            "generalSteps": 80,
            "exploreSteps": 50,
            "target": "Slabiji laptop ili masina gde zelis najmanji termalni i VRAM pritisak.",
            "summary": "Najstabilniji preset za tisi i sigurniji rad kada je prioritet da sve radi bez naprezanja.",
            "tradeoff": "Manji context i kraci izlaz nego kod jacih presetova.",
            "modelId": recommended_model_id,
        },
        {
            "id": "coding-fast",
            "title": "Coding fast",
            "profile": "speed",
            "contextSize": 131072,
            "maxOutputTokens": 6144,
            "buildSteps": 140,
            "planSteps": 100,
            "generalSteps": 110,
            "exploreSteps": 80,
            "target": "Brzi dnevni coding tok za OpenCode i agentic rad na lokalnoj masini.",
            "summary": "Naglasak je na brzom odzivu i jacem code-oriented agent ritmu uz speed profil.",
            "tradeoff": "Manje prostora za long-context zadatke nego kod context-heavy presetova.",
            "modelId": "qwen2.5-coder-7b-instruct-q5_k_m.gguf",
        },
        {
            "id": "long-context",
            "title": "Long context",
            "profile": long_context_profile,
            "contextSize": long_context_context,
            "maxOutputTokens": long_context_output,
            "buildSteps": 120 if not strong_hardware else 140,
            "planSteps": 90 if not strong_hardware else 100,
            "generalSteps": 110 if not strong_hardware else 120,
            "exploreSteps": 70 if not strong_hardware else 80,
            "target": "Sesije gde ti je prioritet veci context i duzi kontinuitet rada.",
            "summary": "Podize context sto vise ima smisla za ovu klasu hardvera, uz oprezniji output balans.",
            "tradeoff": "Vise memorijskog pritiska i potencijalno sporiji odziv od coding-fast preset-a.",
            "modelId": recommended_model_id,
        },
        {
            "id": "best-current-setup",
            "title": "Best current setup",
            "profile": recommended_profile,
            "contextSize": best_current_context,
            "maxOutputTokens": best_current_output,
            "buildSteps": best_current_build,
            "planSteps": best_current_plan,
            "generalSteps": best_current_general,
            "exploreSteps": best_current_explore,
            "target": "Automatski prati preporuku za ovu konkretnu masinu.",
            "summary": best_current_summary,
            "tradeoff": "Menja se sa klasom hardvera i zato nije univerzalan preset za svaku masinu.",
            "modelId": recommended_model_id,
        },
    ]

    return {
        "recommendedProfile": recommended_profile,
        "detectedClass": recommendation["detectedClass"],
        "reason": recommendation["reason"],
        "hardware": recommendation["hardware"],
        "recommendedModel": recommended_model,
        "presets": presets,
    }


def build_settings_preset_preview(
    defaults: dict,
    gpu_mib: int | None,
    ram_gib: int | None,
    cpu_threads: int | None,
    preset_id: str,
    current_profile: str,
    current_context: int,
    current_output: int,
    current_build: int,
    current_plan: int,
    current_general: int,
    current_explore: int,
) -> dict:
    bundle = build_settings_presets(defaults, gpu_mib, ram_gib, cpu_threads)
    selected = None
    for preset in bundle["presets"]:
        if str(preset.get("id")) == str(preset_id):
            selected = preset
            break
    if selected is None:
        raise ValueError(f"Preset not found: {preset_id}")

    current = {
        "profile": current_profile,
        "contextSize": int(current_context),
        "maxOutputTokens": int(current_output),
        "buildSteps": int(current_build),
        "planSteps": int(current_plan),
        "generalSteps": int(current_general),
        "exploreSteps": int(current_explore),
    }
    target = {
        "profile": str(selected["profile"]),
        "contextSize": int(selected["contextSize"]),
        "maxOutputTokens": int(selected["maxOutputTokens"]),
        "buildSteps": int(selected["buildSteps"]),
        "planSteps": int(selected["planSteps"]),
        "generalSteps": int(selected["generalSteps"]),
        "exploreSteps": int(selected["exploreSteps"]),
    }

    changed_fields: list[str] = []
    compare_lines: list[str] = []
    labels = {
        "profile": "Profil",
        "contextSize": "Context",
        "maxOutputTokens": "Output",
        "buildSteps": "Build",
        "planSteps": "Plan",
        "generalSteps": "General",
        "exploreSteps": "Explore",
    }
    for key, label in labels.items():
        if current[key] != target[key]:
            changed_fields.append(key)
            compare_lines.append(f"{label}: {current[key]} -> {target[key]}")

    if not compare_lines:
        compare_lines.append("Preset se vec poklapa sa trenutnim vrednostima.")

    return {
        "preset": selected,
        "current": current,
        "target": target,
        "changedFields": changed_fields,
        "compareLines": compare_lines,
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


def command_download_candidates(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    payload = build_download_candidates(defaults, args.gpu_mib, args.ram_gib, args.cpu_threads)
    print(json.dumps(payload, indent=2))
    return 0


def command_filter_models(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    payload = filter_models(
        defaults,
        args.gpu_mib,
        args.ram_gib,
        args.cpu_threads,
        verified_only=args.verified_only,
        coder_only=args.coder_only,
        fit_only=args.fit_only,
    )
    print(json.dumps(payload, indent=2))
    return 0


def command_resolve_install_model(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    available_complete_model_ids = []
    if args.available_complete_model_ids:
        available_complete_model_ids = [item for item in str(args.available_complete_model_ids).split(",") if item]
    payload = resolve_install_model(
        defaults,
        args.gpu_mib,
        args.ram_gib,
        args.cpu_threads,
        current_model_id=args.current_model_id,
        current_model_complete=parse_bool(args.current_model_complete),
        skip_model_download=parse_bool(args.skip_model_download),
        available_complete_model_ids=available_complete_model_ids,
    )
    print(json.dumps(payload, indent=2))
    return 0


def command_model_browser(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    installed_model_ids = []
    if args.installed_model_ids:
        installed_model_ids = [item for item in str(args.installed_model_ids).split(",") if item]
    installed_model_sizes: dict[str, int] = {}
    if args.installed_model_sizes_json:
        try:
            installed_model_sizes = json.loads(args.installed_model_sizes_json)
        except json.JSONDecodeError:
            installed_model_sizes = {}
    payload = build_model_browser(
        defaults,
        args.gpu_mib,
        args.ram_gib,
        args.cpu_threads,
        current_model_id=args.current_model_id,
        installed_model_ids=installed_model_ids,
        installed_model_sizes=installed_model_sizes,
        free_disk_gib=args.free_disk_gib,
        search=args.search,
        family=args.family,
        installed_only=args.installed_only,
        recommended_only=args.recommended_only,
        fit_only=args.fit_only,
        coder_only=args.coder_only,
        verified_only=args.verified_only,
    )
    print(json.dumps(payload, indent=2))
    return 0


def command_model_compare(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    browser = build_model_browser(
        defaults,
        args.gpu_mib,
        args.ram_gib,
        args.cpu_threads,
        current_model_id="",
        installed_model_ids=[],
        installed_model_sizes={},
        free_disk_gib=-1,
    )
    available = {str(item["id"]): item for item in browser["models"]}
    model_ids = [item for item in str(args.model_ids).split(",") if item]
    compared = [available[item_id] for item_id in model_ids if item_id in available]

    def first_by_badge(badge: str):
        for item in compared:
            if badge in item.get("useCaseBadges", []):
                return item
        return None

    best_speed = first_by_badge("best-for-speed") or max(compared, key=lambda item: (item.get("opencodeFit", 0), -item.get("approxSizeGiB", 0)), default=None)
    best_coding = first_by_badge("best-for-coding") or max(compared, key=lambda item: (item.get("agenticScore", 0), item.get("opencodeFit", 0)), default=None)
    best_quality = first_by_badge("best-quality-model") or max(compared, key=lambda item: (item.get("approxSizeGiB", 0), item.get("agenticScore", 0)), default=None)

    payload = {
        "models": compared,
        "summary": {
            "bestForSpeed": best_speed["id"] if best_speed else None,
            "bestForCoding": best_coding["id"] if best_coding else None,
            "bestForQuality": best_quality["id"] if best_quality else None,
        },
    }
    print(json.dumps(payload, indent=2))
    return 0


def command_settings_presets(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    payload = build_settings_presets(defaults, args.gpu_mib, args.ram_gib, args.cpu_threads)
    print(json.dumps(payload, indent=2))
    return 0


def command_settings_preset_preview(args: argparse.Namespace) -> int:
    defaults = load_defaults(args.defaults)
    payload = build_settings_preset_preview(
        defaults,
        args.gpu_mib,
        args.ram_gib,
        args.cpu_threads,
        args.preset_id,
        args.current_profile,
        args.current_context,
        args.current_output,
        args.current_build,
        args.current_plan,
        args.current_general,
        args.current_explore,
    )
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


def build_health_center(
    has_server: bool,
    has_model: bool,
    has_runtime: bool,
    has_opencode_config: bool,
    has_install_report: bool,
    lifecycle_state: str,
    current_model_id: str,
    profile: str,
    warnings: list[str],
) -> dict:
    checks = [
        {
            "id": "runtime",
            "title": "llama.cpp runtime",
            "ok": has_runtime,
            "description": "llama-server postoji i spreman je za start." if has_runtime else "llama-server nedostaje ili je runtime polomljen.",
            "repairAction": "repair-runtime",
        },
        {
            "id": "model",
            "title": "Aktivni model",
            "ok": has_model,
            "description": f"Model '{current_model_id}' je dostupan i potpun." if has_model else f"Model '{current_model_id}' nedostaje ili je nepotpun.",
            "repairAction": "repair-model",
        },
        {
            "id": "opencode-config",
            "title": "OpenCode config",
            "ok": has_opencode_config,
            "description": "OpenCode config pokazuje na lokalni endpoint." if has_opencode_config else "OpenCode config nedostaje ili nije upisan.",
            "repairAction": "repair-config",
        },
        {
            "id": "install-report",
            "title": "Install report",
            "ok": has_install_report,
            "description": "Install report postoji za diagnostics i repair tok." if has_install_report else "Install report nedostaje, pa je diagnostics slabiji.",
            "repairAction": "repair-all",
        },
    ]

    service = summarize_service_status(has_health=has_server, lifecycle_state=lifecycle_state)
    warning_entries = [
        {
            "id": f"warning-{index + 1}",
            "title": warning,
            "severity": "warning",
        }
        for index, warning in enumerate(warnings)
        if str(warning).strip()
    ]
    wdac_warning = any(
        ("wdac" in str(warning).lower()) or ("app control" in str(warning).lower())
        for warning in warnings
    )

    broken_count = sum(1 for item in checks if not item["ok"])
    if broken_count == 0 and not warning_entries and service["effectiveState"] == "active":
        overall = "healthy"
        title = "Sistem je zdrav"
        summary = "Runtime, model, OpenCode i health endpoint su svi spremni."
    elif broken_count == 0 and service["effectiveState"] == "warming":
        overall = "warming"
        title = "Sistem se podize"
        summary = "Osnovne komponente su prisutne, a server je u STARTING / WARMING stanju."
    elif broken_count <= 1 and service["effectiveState"] != "failed":
        overall = "attention"
        title = "Treba mala popravka"
        summary = "Jedna ili dve komponente traze intervenciju, ali instalacija je blizu zdravog stanja."
    else:
        overall = "broken"
        title = "Sistem trazi repair"
        summary = "Vise kljucnih komponenti nije spremno i preporucen je repair tok."

    recommended_actions: list[dict] = []
    if not has_runtime:
        recommended_actions.append({
            "id": "repair-runtime",
            "title": "Repair runtime",
            "reason": "llama.cpp runtime nedostaje ili nije spreman.",
        })
    if not has_model:
        recommended_actions.append({
            "id": "repair-model",
            "title": "Repair model",
            "reason": "Aktivni model nije potpun ili ne postoji na disku.",
        })
    if not has_opencode_config:
        recommended_actions.append({
            "id": "repair-config",
            "title": "Repair config",
            "reason": "OpenCode config nije upisan ili nije validan za lokalni endpoint.",
        })
    if wdac_warning:
        recommended_actions.append({
            "id": "repair-app-control",
            "title": "Repair App Control",
            "reason": "Windows policy warning ukazuje da App Control / WDAC moze blokirati llama-server.exe.",
        })
    if broken_count > 1 or warning_entries:
        recommended_actions.append({
            "id": "repair-all",
            "title": "Repair all",
            "reason": "Jednim korakom obnavlja launchere, runtime, model i config gde je potrebno.",
        })
    if not recommended_actions and service["effectiveState"] != "active":
        recommended_actions.append({
            "id": "start-server",
            "title": "Pokreni server",
            "reason": "Komponente su spremne, ostaje samo da server potvrdi health.",
        })

    severity_score = 0
    severity_score += broken_count * 3
    if service["effectiveState"] == "failed":
        severity_score += 3
    elif service["effectiveState"] == "warming":
        severity_score += 1
    severity_score += len(warning_entries)
    if wdac_warning:
        severity_score += 1

    if severity_score >= 8:
        severity_level = "critical"
        severity_label = "kriticno"
    elif severity_score >= 5:
        severity_level = "high"
        severity_label = "visoko"
    elif severity_score >= 2:
        severity_level = "medium"
        severity_label = "srednje"
    else:
        severity_level = "low"
        severity_label = "nisko"

    primary_action = recommended_actions[0] if recommended_actions else {
        "id": "none",
        "title": "Nema potrebe za repair-om",
        "reason": "Sve kljucne komponente izgledaju zdravo.",
    }

    return {
        "overallState": overall,
        "severityLevel": severity_level,
        "severityLabel": severity_label,
        "severityScore": severity_score,
        "title": title,
        "summary": summary,
        "profile": profile,
        "modelId": current_model_id,
        "service": service,
        "checks": checks,
        "warnings": warning_entries,
        "primaryAction": primary_action,
        "recommendedActions": recommended_actions,
    }


def command_health_center(args: argparse.Namespace) -> int:
    warnings = []
    if args.warnings_json:
        try:
            warnings = json.loads(args.warnings_json)
        except json.JSONDecodeError:
            warnings = [args.warnings_json]
    payload = build_health_center(
        has_server=parse_bool(args.has_server),
        has_model=parse_bool(args.has_model),
        has_runtime=parse_bool(args.has_runtime),
        has_opencode_config=parse_bool(args.has_opencode_config),
        has_install_report=parse_bool(args.has_install_report),
        lifecycle_state=args.lifecycle_state,
        current_model_id=args.model_id,
        profile=args.profile,
        warnings=warnings,
    )
    print(json.dumps(payload, indent=2))
    return 0


def summarize_service_status(has_health: bool, lifecycle_state: str) -> dict:
    if has_health:
        return {
            "state": "active",
            "effectiveState": "active",
            "title": "AKTIVAN",
            "reason": "Health endpoint odgovara i server je spreman.",
        }
    if lifecycle_state in {"starting", "warming"}:
        return {
            "state": "warming",
            "effectiveState": "warming",
            "title": "STARTING / WARMING",
            "reason": "Server se jos podize i model se ucitava u pozadini.",
        }
    if lifecycle_state in {"failed", "timeout"}:
        return {
            "state": "failed",
            "effectiveState": "failed",
            "title": "FAILED",
            "reason": "Poslednji start nije potvrdjen ili je eksplicitno pao.",
        }
    return {
        "state": "inactive",
        "effectiveState": "inactive",
        "title": "NIJE AKTIVAN",
        "reason": "Nema health potvrde i nema aktivnog warmup/start lifecycle signala.",
    }


def command_service_status(args: argparse.Namespace) -> int:
    payload = summarize_service_status(
        has_health=parse_bool(args.has_health),
        lifecycle_state=args.lifecycle_state,
    )
    print(json.dumps(payload, indent=2))
    return 0


def summarize_token_metrics(payload: dict) -> dict:
    usage = payload.get("usage", {}) or {}
    timings = payload.get("timings", {}) or {}
    prompt_tokens = int(usage.get("prompt_tokens") or usage.get("promptTokens") or timings.get("prompt_n") or 0)
    completion_tokens = int(
        usage.get("completion_tokens")
        or usage.get("completionTokens")
        or timings.get("predicted_n")
        or timings.get("completion_n")
        or 0
    )
    total_tokens = prompt_tokens + completion_tokens

    prompt_ms = float(timings.get("prompt_ms") or timings.get("prompt_eval_ms") or 0)
    completion_ms = float(timings.get("predicted_ms") or timings.get("completion_ms") or timings.get("eval_ms") or 0)
    total_ms = float(timings.get("total_ms") or payload.get("_elapsed_ms") or 0)
    if total_ms <= 0 and prompt_ms > 0 and completion_ms > 0:
        total_ms = prompt_ms + completion_ms

    prompt_tps = float(timings.get("prompt_per_second") or 0)
    if prompt_tps <= 0 and prompt_tokens > 0 and prompt_ms > 0:
        prompt_tps = prompt_tokens / (prompt_ms / 1000.0)

    completion_tps = float(timings.get("predicted_per_second") or timings.get("completion_per_second") or 0)
    if completion_tps <= 0 and completion_tokens > 0 and completion_ms > 0:
        completion_tps = completion_tokens / (completion_ms / 1000.0)

    total_tps = 0.0
    if total_tokens > 0 and total_ms > 0:
        total_tps = total_tokens / (total_ms / 1000.0)

    return {
        "measuredAt": payload.get("_measured_at") or datetime.now(timezone.utc).isoformat(),
        "label": payload.get("_label") or "request",
        "promptTokens": prompt_tokens,
        "completionTokens": completion_tokens,
        "totalTokens": total_tokens,
        "promptMs": round(prompt_ms, 2),
        "completionMs": round(completion_ms, 2),
        "totalMs": round(total_ms, 2),
        "promptTokensPerSecond": round(prompt_tps, 2) if prompt_tps > 0 else 0.0,
        "completionTokensPerSecond": round(completion_tps, 2) if completion_tps > 0 else 0.0,
        "totalTokensPerSecond": round(total_tps, 2) if total_tps > 0 else 0.0,
    }


def parse_llama_timing_metrics(text: str, label: str = "live-log") -> list[dict]:
    prompt_pattern = re.compile(
        r"prompt eval time\s*=\s*(?P<prompt_ms>[\d.]+)\s*ms\s*/\s*(?P<prompt_tokens>\d+)\s*tokens.*?(?P<prompt_tps>[\d.]+)\s*tokens per second"
    )
    eval_pattern = re.compile(
        r"eval time\s*=\s*(?P<completion_ms>[\d.]+)\s*ms\s*/\s*(?P<completion_tokens>\d+)\s*tokens.*?(?P<completion_tps>[\d.]+)\s*tokens per second"
    )
    total_pattern = re.compile(
        r"total time\s*=\s*(?P<total_ms>[\d.]+)\s*ms\s*/\s*(?P<total_tokens>\d+)\s*tokens"
    )
    start_pattern = re.compile(r"slot print_timing:\s*id\s+\d+\s*\|\s*task\s+(?P<task_id>-?\d+)\s*\|")

    lines = text.splitlines()
    parsed: list[dict] = []

    for index, line in enumerate(lines):
        start_match = start_pattern.search(line)
        if not start_match:
            continue
        if index + 3 >= len(lines):
            continue

        prompt_match = prompt_pattern.search(lines[index + 1])
        eval_match = eval_pattern.search(lines[index + 2])
        total_match = total_pattern.search(lines[index + 3])
        if not (prompt_match and eval_match and total_match):
            continue

        task_id = start_match.group("task_id")
        prompt_tokens = int(prompt_match.group("prompt_tokens"))
        completion_tokens = int(eval_match.group("completion_tokens"))
        total_tokens = int(total_match.group("total_tokens"))
        prompt_ms = float(prompt_match.group("prompt_ms"))
        completion_ms = float(eval_match.group("completion_ms"))
        total_ms = float(total_match.group("total_ms"))
        prompt_tps = float(prompt_match.group("prompt_tps"))
        completion_tps = float(eval_match.group("completion_tps"))
        total_tps = 0.0
        if total_tokens > 0 and total_ms > 0:
            total_tps = total_tokens / (total_ms / 1000.0)

        parsed.append(
            {
                "measuredAt": datetime.now(timezone.utc).isoformat(),
                "label": label,
                "promptTokens": prompt_tokens,
                "completionTokens": completion_tokens,
                "totalTokens": total_tokens,
                "promptMs": round(prompt_ms, 2),
                "completionMs": round(completion_ms, 2),
                "totalMs": round(total_ms, 2),
                "promptTokensPerSecond": round(prompt_tps, 2),
                "completionTokensPerSecond": round(completion_tps, 2),
                "totalTokensPerSecond": round(total_tps, 2) if total_tps > 0 else 0.0,
                "signature": f"{task_id}:{prompt_tokens}:{completion_tokens}:{round(total_ms, 2)}",
                "taskId": task_id,
            }
        )

    return parsed


def merge_token_metric_history(history: list[dict], items: list[dict], max_history: int) -> list[dict]:
    merged: list[dict] = []
    seen: set[str] = set()

    for item in history:
        signature = item.get("signature") or f"{item.get('label', 'request')}:{item.get('promptTokens', 0)}:{item.get('completionTokens', 0)}:{item.get('totalMs', 0)}"
        if signature in seen:
            continue
        enriched = dict(item)
        enriched["signature"] = signature
        merged.append(enriched)
        seen.add(signature)

    for item in items:
        signature = item.get("signature") or f"{item.get('label', 'request')}:{item.get('promptTokens', 0)}:{item.get('completionTokens', 0)}:{item.get('totalMs', 0)}"
        if signature in seen:
            continue
        merged.append(item)
        seen.add(signature)

    return merged[-max(1, max_history):]


def summarize_history_payload(history: list[dict]) -> dict:
    current = history[-1] if history else None
    avg_prompt_tps = 0.0
    avg_completion_tps = 0.0
    avg_total_tps = 0.0
    avg_total_ms = 0.0
    source_counts = {"testPrompt": 0, "opencode": 0, "other": 0}
    if history:
        avg_prompt_tps = sum(item.get("promptTokensPerSecond", 0.0) for item in history) / len(history)
        avg_completion_tps = sum(item.get("completionTokensPerSecond", 0.0) for item in history) / len(history)
        avg_total_tps = sum(item.get("totalTokensPerSecond", 0.0) for item in history) / len(history)
        avg_total_ms = sum(item.get("totalMs", 0.0) for item in history) / len(history)
        for item in history:
            label = str(item.get("label", "")).lower()
            if "test" in label:
                source_counts["testPrompt"] += 1
            elif "opencode" in label:
                source_counts["opencode"] += 1
            else:
                source_counts["other"] += 1

    return {
        "current": current,
        "history": history,
        "historyCount": len(history),
        "requestCount": len(history),
        "lastMeasuredAt": current.get("measuredAt") if current else None,
        "lastLabel": current.get("label") if current else None,
        "activity": {
            "averageTotalMs": round(avg_total_ms, 2),
            "sources": source_counts,
        },
        "averages": {
            "promptTokensPerSecond": round(avg_prompt_tps, 2),
            "completionTokensPerSecond": round(avg_completion_tps, 2),
            "totalTokensPerSecond": round(avg_total_tps, 2),
        },
    }


def command_token_metrics(args: argparse.Namespace) -> int:
    response_path = Path(args.response_file)
    history_path = Path(args.history_file)
    with response_path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    payload["_label"] = args.label
    current = summarize_token_metrics(payload)

    history = []
    if history_path.exists():
        try:
            with history_path.open("r", encoding="utf-8") as handle:
                history = json.load(handle)
        except Exception:
            history = []

    history = merge_token_metric_history(history, [current], args.max_history)
    history_path.parent.mkdir(parents=True, exist_ok=True)
    with history_path.open("w", encoding="utf-8") as handle:
        json.dump(history, handle, ensure_ascii=False, indent=2)

    print(json.dumps(summarize_history_payload(history), indent=2))
    return 0


def command_log_token_metrics(args: argparse.Namespace) -> int:
    log_path = Path(args.log_file)
    history_path = Path(args.history_file)
    if not log_path.exists():
        print(json.dumps(summarize_history_payload([]), indent=2))
        return 0

    try:
        text = log_path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        text = ""

    if args.tail_lines and args.tail_lines > 0:
        text = "\n".join(text.splitlines()[-args.tail_lines :])

    parsed = parse_llama_timing_metrics(text, args.label)

    history: list[dict] = []
    if history_path.exists():
        try:
            with history_path.open("r", encoding="utf-8") as handle:
                history = json.load(handle)
        except Exception:
            history = []

    history = merge_token_metric_history(history, parsed, args.max_history)
    history_path.parent.mkdir(parents=True, exist_ok=True)
    with history_path.open("w", encoding="utf-8") as handle:
        json.dump(history, handle, ensure_ascii=False, indent=2)

    print(json.dumps(summarize_history_payload(history), indent=2))
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

    download_candidates = subparsers.add_parser("download-candidates")
    download_candidates.add_argument("--defaults", required=True)
    download_candidates.add_argument("--gpu-mib", type=int, default=0)
    download_candidates.add_argument("--ram-gib", type=int, default=0)
    download_candidates.add_argument("--cpu-threads", type=int, default=0)
    download_candidates.set_defaults(func=command_download_candidates)

    filter_models_parser = subparsers.add_parser("filter-models")
    filter_models_parser.add_argument("--defaults", required=True)
    filter_models_parser.add_argument("--gpu-mib", type=int, default=0)
    filter_models_parser.add_argument("--ram-gib", type=int, default=0)
    filter_models_parser.add_argument("--cpu-threads", type=int, default=0)
    filter_models_parser.add_argument("--verified-only", action="store_true")
    filter_models_parser.add_argument("--coder-only", action="store_true")
    filter_models_parser.add_argument("--fit-only", action="store_true")
    filter_models_parser.set_defaults(func=command_filter_models)

    resolve_install_model_parser = subparsers.add_parser("resolve-install-model")
    resolve_install_model_parser.add_argument("--defaults", required=True)
    resolve_install_model_parser.add_argument("--gpu-mib", type=int, default=0)
    resolve_install_model_parser.add_argument("--ram-gib", type=int, default=0)
    resolve_install_model_parser.add_argument("--cpu-threads", type=int, default=0)
    resolve_install_model_parser.add_argument("--current-model-id", default="")
    resolve_install_model_parser.add_argument("--current-model-complete", default="false")
    resolve_install_model_parser.add_argument("--skip-model-download", default="false")
    resolve_install_model_parser.add_argument("--available-complete-model-ids", default="")
    resolve_install_model_parser.set_defaults(func=command_resolve_install_model)

    model_browser_parser = subparsers.add_parser("model-browser")
    model_browser_parser.add_argument("--defaults", required=True)
    model_browser_parser.add_argument("--gpu-mib", type=int, default=0)
    model_browser_parser.add_argument("--ram-gib", type=int, default=0)
    model_browser_parser.add_argument("--cpu-threads", type=int, default=0)
    model_browser_parser.add_argument("--current-model-id", default="")
    model_browser_parser.add_argument("--installed-model-ids", default="")
    model_browser_parser.add_argument("--installed-model-sizes-json", default="{}")
    model_browser_parser.add_argument("--free-disk-gib", type=float, default=-1)
    model_browser_parser.add_argument("--search", default="")
    model_browser_parser.add_argument("--family", default="")
    model_browser_parser.add_argument("--installed-only", action="store_true")
    model_browser_parser.add_argument("--recommended-only", action="store_true")
    model_browser_parser.add_argument("--fit-only", action="store_true")
    model_browser_parser.add_argument("--coder-only", action="store_true")
    model_browser_parser.add_argument("--verified-only", action="store_true")
    model_browser_parser.set_defaults(func=command_model_browser)

    model_compare_parser = subparsers.add_parser("model-compare")
    model_compare_parser.add_argument("--defaults", required=True)
    model_compare_parser.add_argument("--gpu-mib", type=int, default=0)
    model_compare_parser.add_argument("--ram-gib", type=int, default=0)
    model_compare_parser.add_argument("--cpu-threads", type=int, default=0)
    model_compare_parser.add_argument("--model-ids", required=True)
    model_compare_parser.set_defaults(func=command_model_compare)

    settings_presets_parser = subparsers.add_parser("settings-presets")
    settings_presets_parser.add_argument("--defaults", required=True)
    settings_presets_parser.add_argument("--gpu-mib", type=int, default=0)
    settings_presets_parser.add_argument("--ram-gib", type=int, default=0)
    settings_presets_parser.add_argument("--cpu-threads", type=int, default=0)
    settings_presets_parser.set_defaults(func=command_settings_presets)

    settings_preset_preview_parser = subparsers.add_parser("settings-preset-preview")
    settings_preset_preview_parser.add_argument("--defaults", required=True)
    settings_preset_preview_parser.add_argument("--gpu-mib", type=int, default=0)
    settings_preset_preview_parser.add_argument("--ram-gib", type=int, default=0)
    settings_preset_preview_parser.add_argument("--cpu-threads", type=int, default=0)
    settings_preset_preview_parser.add_argument("--preset-id", required=True)
    settings_preset_preview_parser.add_argument("--current-profile", required=True)
    settings_preset_preview_parser.add_argument("--current-context", type=int, required=True)
    settings_preset_preview_parser.add_argument("--current-output", type=int, required=True)
    settings_preset_preview_parser.add_argument("--current-build", type=int, required=True)
    settings_preset_preview_parser.add_argument("--current-plan", type=int, required=True)
    settings_preset_preview_parser.add_argument("--current-general", type=int, required=True)
    settings_preset_preview_parser.add_argument("--current-explore", type=int, required=True)
    settings_preset_preview_parser.set_defaults(func=command_settings_preset_preview)

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

    health_center = subparsers.add_parser("health-center")
    health_center.add_argument("--has-server", required=True)
    health_center.add_argument("--has-model", required=True)
    health_center.add_argument("--has-runtime", required=True)
    health_center.add_argument("--has-opencode-config", required=True)
    health_center.add_argument("--has-install-report", required=True)
    health_center.add_argument("--lifecycle-state", required=True)
    health_center.add_argument("--model-id", required=True)
    health_center.add_argument("--profile", required=True)
    health_center.add_argument("--warnings-json", default="[]")
    health_center.set_defaults(func=command_health_center)

    service_status = subparsers.add_parser("service-status")
    service_status.add_argument("--has-health", required=True)
    service_status.add_argument("--lifecycle-state", required=True)
    service_status.set_defaults(func=command_service_status)

    token_metrics = subparsers.add_parser("token-metrics")
    token_metrics.add_argument("--response-file", required=True)
    token_metrics.add_argument("--history-file", required=True)
    token_metrics.add_argument("--label", default="request")
    token_metrics.add_argument("--max-history", type=int, default=5)
    token_metrics.set_defaults(func=command_token_metrics)

    log_token_metrics = subparsers.add_parser("log-token-metrics")
    log_token_metrics.add_argument("--log-file", required=True)
    log_token_metrics.add_argument("--history-file", required=True)
    log_token_metrics.add_argument("--label", default="live-log")
    log_token_metrics.add_argument("--max-history", type=int, default=5)
    log_token_metrics.add_argument("--tail-lines", type=int, default=400)
    log_token_metrics.set_defaults(func=command_log_token_metrics)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
