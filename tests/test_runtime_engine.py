import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "local_qwen_runtime.py"
DEFAULTS_PATH = REPO_ROOT / "config" / "profiles" / "defaults.json"

SPEC = importlib.util.spec_from_file_location("local_qwen_runtime", SCRIPT_PATH)
RUNTIME_MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(RUNTIME_MODULE)


def run_runtime_command(*args):
    command = [sys.executable, str(SCRIPT_PATH), *args]
    completed = subprocess.run(command, capture_output=True, text=True)
    return completed.returncode, completed.stdout, completed.stderr


class RuntimeEngineTests(unittest.TestCase):
    def test_semver_tuple_parses_normal_versions(self):
        self.assertEqual(RUNTIME_MODULE._coerce_semver_tuple("2.9.7"), (2, 9, 7))
        self.assertEqual(RUNTIME_MODULE._coerce_semver_tuple("v2.9.6"), (2, 9, 6))

    def test_semver_tuple_rejects_invalid_versions(self):
        self.assertIsNone(RUNTIME_MODULE._coerce_semver_tuple(""))
        self.assertIsNone(RUNTIME_MODULE._coerce_semver_tuple("2.9"))
        self.assertIsNone(RUNTIME_MODULE._coerce_semver_tuple("latest"))

    def test_latest_release_marks_local_build_ahead_of_public_release(self):
        current = RUNTIME_MODULE._coerce_semver_tuple("2.10.4")
        latest = RUNTIME_MODULE._coerce_semver_tuple("2.10.3")

        self.assertGreater(current, latest)

    def test_build_release_asset_urls_returns_versioned_assets(self):
        payload = RUNTIME_MODULE.build_release_asset_urls(
            "joes021/Local-Qwen-3.635Ba3B-on-home-computer",
            "2.10.17",
        )
        self.assertEqual(payload["tagName"], "v2.10.17")
        self.assertTrue(payload["windowsInstallerUrl"].endswith("/Local-Qwen-Setup-2.10.17.exe"))
        self.assertTrue(payload["linuxInstallerUrl"].endswith("/Local-Qwen-Setup-2.10.17.run"))

    def test_recommendation_prefers_iq2_for_6gb_gpu(self):
        code, stdout, stderr = run_runtime_command(
            "recommend",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["recommendedProfile"], "speed")
        self.assertEqual(payload["recommendedModel"]["id"], "qwen36-35b-a3b-IQ2_M.gguf")

    def test_recommendation_prefers_q4_for_24gb_gpu(self):
        code, stdout, stderr = run_runtime_command(
            "recommend",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "24576",
            "--ram-gib",
            "64",
            "--cpu-threads",
            "24",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["recommendedProfile"], "video")
        self.assertEqual(payload["recommendedModel"]["id"], "Qwen3.6-35B-A3B-Q4_K_M.gguf")

    def test_catalog_lists_primary_and_mirrors(self):
        code, stdout, stderr = run_runtime_command(
            "catalog",
            "--defaults",
            str(DEFAULTS_PATH),
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        ids = {item["id"] for item in payload["models"]}
        self.assertIn("qwen36-35b-a3b-IQ2_M.gguf", ids)
        self.assertIn("gemma-3-4b-it-Q4_K_M.gguf", ids)
        iq2 = next(item for item in payload["models"] if item["id"] == "qwen36-35b-a3b-IQ2_M.gguf")
        q4 = next(item for item in payload["models"] if item["id"] == "Qwen3.6-35B-A3B-Q4_K_M.gguf")
        self.assertGreaterEqual(len(iq2["sources"]), 2)
        self.assertTrue(iq2["primaryRecommendation"])
        self.assertFalse(q4["primaryRecommendation"])

    def test_download_candidates_group_models_for_6gb_gpu(self):
        code, stdout, stderr = run_runtime_command(
            "download-candidates",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        recommended_ids = {item["id"] for item in payload["groups"]["recommended"]}
        can_run_ids = {item["id"] for item in payload["groups"]["canRun"]}
        not_recommended_ids = {item["id"] for item in payload["groups"]["notRecommended"]}
        self.assertIn("qwen36-35b-a3b-IQ2_M.gguf", recommended_ids)
        self.assertIn("qwen2.5-coder-7b-instruct-q5_k_m.gguf", recommended_ids)
        self.assertIn("gemma-3-4b-it-Q4_K_M.gguf", can_run_ids | recommended_ids)
        self.assertIn("Qwen3.6-35B-A3B-Q4_K_M.gguf", not_recommended_ids)

    def test_filter_models_returns_verified_coder_models_that_fit_machine(self):
        code, stdout, stderr = run_runtime_command(
            "filter-models",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--verified-only",
            "--coder-only",
            "--fit-only",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        visible_ids = [item["id"] for item in payload["models"]]
        self.assertEqual(visible_ids, ["qwen2.5-coder-7b-instruct-q5_k_m.gguf"])

    def test_resolve_install_model_preserves_existing_complete_model_when_skip_download_is_used(self):
        code, stdout, stderr = run_runtime_command(
            "resolve-install-model",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "4095",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--current-model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--current-model-complete",
            "true",
            "--skip-model-download",
            "true",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["selectedModel"]["id"], "qwen36-35b-a3b-IQ2_M.gguf")
        self.assertEqual(payload["selectionMode"], "preserve-existing")

    def test_resolve_install_model_recovers_to_available_complete_local_model_when_current_is_broken(self):
        code, stdout, stderr = run_runtime_command(
            "resolve-install-model",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "4095",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--current-model-id",
            "gemma-3-4b-it-Q4_K_M.gguf",
            "--current-model-complete",
            "false",
            "--skip-model-download",
            "true",
            "--available-complete-model-ids",
            "qwen36-35b-a3b-IQ2_M.gguf",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["selectedModel"]["id"], "qwen36-35b-a3b-IQ2_M.gguf")
        self.assertEqual(payload["selectionMode"], "reuse-local-complete")

    def test_model_browser_marks_installed_active_and_recommended_models(self):
        code, stdout, stderr = run_runtime_command(
            "model-browser",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--current-model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--installed-model-ids",
            "qwen36-35b-a3b-IQ2_M.gguf,qwen2.5-coder-7b-instruct-q5_k_m.gguf",
            "--installed-model-sizes-json",
            json.dumps({
                "qwen36-35b-a3b-IQ2_M.gguf": 11000000000,
                "qwen2.5-coder-7b-instruct-q5_k_m.gguf": 5600000000,
            }),
            "--free-disk-gib",
            "40",
            "--search",
            "qwen",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        qwen36 = next(item for item in payload["models"] if item["id"] == "qwen36-35b-a3b-IQ2_M.gguf")
        coder = next(item for item in payload["models"] if item["id"] == "qwen2.5-coder-7b-instruct-q5_k_m.gguf")
        self.assertTrue(qwen36["installed"])
        self.assertTrue(qwen36["active"])
        self.assertTrue(qwen36["recommended"])
        self.assertEqual(qwen36["fitGroup"], "recommended")
        self.assertTrue(coder["installed"])
        self.assertFalse(coder["active"])
        self.assertIn("balanced-agentic", qwen36["useCaseBadges"])
        self.assertIn("best-for-coding", coder["useCaseBadges"])
        self.assertEqual(qwen36["speedEstimateLabel"], "brzo")
        self.assertAlmostEqual(qwen36["installedSizeGiB"], round(11000000000 / (1024 ** 3), 2))
        self.assertTrue(qwen36["hasEnoughDisk"])
        self.assertIn("best-starter-model", qwen36["useCaseBadges"])
        self.assertIn("best-coding-model", coder["useCaseBadges"])

    def test_model_browser_marks_quality_model_and_disk_needed(self):
        code, stdout, stderr = run_runtime_command(
            "model-browser",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "24576",
            "--ram-gib",
            "64",
            "--cpu-threads",
            "24",
            "--current-model-id",
            "Qwen3.6-35B-A3B-Q4_K_M.gguf",
            "--installed-model-ids",
            "Qwen3.6-35B-A3B-Q4_K_M.gguf",
            "--installed-model-sizes-json",
            json.dumps({
                "Qwen3.6-35B-A3B-Q4_K_M.gguf": 10000000000,
            }),
            "--free-disk-gib",
            "5",
            "--search",
            "Q4_K_M",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        quality = next(item for item in payload["models"] if item["id"] == "Qwen3.6-35B-A3B-Q4_K_M.gguf")
        self.assertIn("best-quality-model", quality["useCaseBadges"])
        self.assertGreater(quality["diskNeededGiB"], 0)
        self.assertFalse(quality["hasEnoughDisk"])

    def test_model_browser_exposes_qwen3_8b_verified_fallback(self):
        code, stdout, stderr = run_runtime_command(
            "model-browser",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--current-model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--search",
            "Qwen3-8B",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        qwen8 = next(item for item in payload["models"] if item["id"] == "Qwen3-8B-Q4_K_M.gguf")
        self.assertEqual(qwen8["curationLevel"], "verified")
        self.assertEqual(qwen8["family"], "Qwen")
        self.assertGreater(qwen8["approxSizeGiB"], 0)

    def test_model_browser_tolerates_one_mib_gpu_detection_gap_for_minimum_threshold(self):
        code, stdout, stderr = run_runtime_command(
            "model-browser",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "4095",
            "--ram-gib",
            "32",
            "--cpu-threads",
            "24",
            "--current-model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--search",
            "IQ2_M",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        qwen36 = next(item for item in payload["models"] if item["id"] == "qwen36-35b-a3b-IQ2_M.gguf")
        self.assertNotEqual(qwen36["fitGroup"], "notRecommended")

    def test_model_browser_keeps_non_active_installed_model_visible_with_own_size(self):
        code, stdout, stderr = run_runtime_command(
            "model-browser",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--current-model-id",
            "gemma-3-4b-it-Q4_K_M.gguf",
            "--installed-model-ids",
            "qwen2.5-coder-7b-instruct-q5_k_m.gguf",
            "--installed-model-sizes-json",
            json.dumps({
                "qwen2.5-coder-7b-instruct-q5_k_m.gguf": 5600000000,
            }),
            "--free-disk-gib",
            "40",
            "--search",
            "coder",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        coder = next(item for item in payload["models"] if item["id"] == "qwen2.5-coder-7b-instruct-q5_k_m.gguf")
        self.assertTrue(coder["installed"])
        self.assertGreater(coder["installedSizeGiB"], 0)

    def test_model_browser_recovers_from_trailing_brace_in_installed_sizes_json(self):
        code, stdout, stderr = run_runtime_command(
            "model-browser",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "12288",
            "--ram-gib",
            "31",
            "--cpu-threads",
            "32",
            "--current-model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--installed-model-ids",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--installed-model-sizes-json",
            '{"qwen36-35b-a3b-IQ2_M.gguf": 11659235616}}',
            "--free-disk-gib",
            "700",
            "--search",
            "qwen36",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        qwen36 = next(item for item in payload["models"] if item["id"] == "qwen36-35b-a3b-IQ2_M.gguf")
        self.assertGreater(qwen36["installedSizeGiB"], 0)
        self.assertLess(qwen36["diskNeededGiB"], qwen36["approxSizeGiB"])

    def test_tiny_installed_model_size_rounds_up_for_display(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_defaults = pathlib.Path(temp_dir) / "defaults.json"
            defaults = json.loads(DEFAULTS_PATH.read_text(encoding="utf-8"))
            defaults.setdefault("modelChoices", {})["tiny_test"] = {
                "id": "tiny.gguf",
                "label": "Tiny Demo",
                "family": "Custom",
                "agenticScore": 6,
                "opencodeFit": 6,
                "useCase": "agentic-general",
                "filename": "tiny.gguf",
                "minExpectedBytes": 1,
                "approxSizeGiB": 0.01,
                "minimumGpuMiB": 0,
                "recommendedGpuMiB": 0,
                "minimumRamGiB": 1,
                "preferredProfiles": ["speed", "balanced"],
                "qualityTier": "compact",
                "curationLevel": "custom",
                "description": "Tiny demo model.",
                "sources": [],
            }
            temp_defaults.write_text(json.dumps(defaults), encoding="utf-8")
            code, stdout, stderr = run_runtime_command(
                "model-browser",
                "--defaults",
                str(temp_defaults),
                "--gpu-mib",
                "12288",
                "--ram-gib",
                "31",
                "--cpu-threads",
                "32",
                "--current-model-id",
                "qwen36-35b-a3b-IQ2_M.gguf",
                "--installed-model-ids",
                "tiny.gguf",
                "--installed-model-sizes-json",
                json.dumps({"tiny.gguf": 4}),
                "--free-disk-gib",
                "700",
                "--search",
                "tiny",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            tiny = next(item for item in payload["models"] if item["id"] == "tiny.gguf")
            self.assertEqual(tiny["installedSizeGiB"], 0.01)

    def test_installed_custom_model_with_satisfied_min_expected_bytes_shows_zero_needed_disk(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_defaults = pathlib.Path(temp_dir) / "defaults.json"
            defaults = json.loads(DEFAULTS_PATH.read_text(encoding="utf-8"))
            defaults.setdefault("modelChoices", {})["custom_local_demo"] = {
                "key": "local-demo-local",
                "id": "local-demo-local.gguf",
                "label": "Demo Local",
                "family": "Custom",
                "agenticScore": 6,
                "opencodeFit": 6,
                "useCase": "agentic-general",
                "filename": "demo-local.gguf",
                "minExpectedBytes": 123456789,
                "approxSizeGiB": 0.12,
                "minimumGpuMiB": 0,
                "recommendedGpuMiB": 0,
                "minimumRamGiB": 8,
                "preferredProfiles": ["speed", "balanced"],
                "qualityTier": "compact",
                "curationLevel": "custom",
                "description": "Local custom demo.",
                "sources": [],
            }
            temp_defaults.write_text(json.dumps(defaults), encoding="utf-8")
            code, stdout, stderr = run_runtime_command(
                "model-browser",
                "--defaults",
                str(temp_defaults),
                "--gpu-mib",
                "12288",
                "--ram-gib",
                "31",
                "--cpu-threads",
                "32",
                "--current-model-id",
                "qwen36-35b-a3b-IQ2_M.gguf",
                "--installed-model-ids",
                "local-demo-local.gguf",
                "--installed-model-sizes-json",
                json.dumps({"local-demo-local.gguf": 123456789}),
                "--free-disk-gib",
                "700",
                "--search",
                "Demo Local",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            demo = next(item for item in payload["models"] if item["id"] == "local-demo-local.gguf")
            self.assertEqual(demo["diskNeededGiB"], 0.0)

    def test_settings_presets_expose_all_quick_presets(self):
        code, stdout, stderr = run_runtime_command(
            "settings-presets",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        preset_ids = [item["id"] for item in payload["presets"]]
        self.assertEqual(
            preset_ids,
            ["laptop-safe", "coding-fast", "long-context", "best-current-setup"],
        )
        best_current = next(item for item in payload["presets"] if item["id"] == "best-current-setup")
        self.assertEqual(best_current["profile"], "speed")
        self.assertEqual(best_current["contextSize"], 131072)
        self.assertEqual(best_current["maxOutputTokens"], 6144)
        self.assertIn("preporuku", best_current["summary"].lower())

    def test_settings_presets_scale_best_current_setup_for_stronger_hardware(self):
        code, stdout, stderr = run_runtime_command(
            "settings-presets",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "24576",
            "--ram-gib",
            "64",
            "--cpu-threads",
            "24",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        best_current = next(item for item in payload["presets"] if item["id"] == "best-current-setup")
        self.assertEqual(best_current["profile"], "video")
        self.assertEqual(best_current["contextSize"], 262144)
        self.assertEqual(best_current["maxOutputTokens"], 12288)
        self.assertGreaterEqual(best_current["buildSteps"], 140)
        self.assertIn("video", best_current["summary"].lower())

    def test_settings_preset_preview_lists_changed_fields(self):
        code, stdout, stderr = run_runtime_command(
            "settings-preset-preview",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--preset-id",
            "coding-fast",
            "--current-profile",
            "balanced",
            "--current-context",
            "262144",
            "--current-output",
            "8192",
            "--current-build",
            "120",
            "--current-plan",
            "80",
            "--current-general",
            "100",
            "--current-explore",
            "60",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["preset"]["id"], "coding-fast")
        self.assertIn("profile", payload["changedFields"])
        self.assertIn("contextSize", payload["changedFields"])
        self.assertIn("maxOutputTokens", payload["changedFields"])
        self.assertTrue(any("balanced -> speed" in line.lower() for line in payload["compareLines"]))

    def test_model_compare_returns_summary_for_selected_models(self):
        code, stdout, stderr = run_runtime_command(
            "model-compare",
            "--defaults",
            str(DEFAULTS_PATH),
            "--gpu-mib",
            "6144",
            "--ram-gib",
            "16",
            "--cpu-threads",
            "12",
            "--model-ids",
            "qwen36-35b-a3b-IQ2_M.gguf,qwen2.5-coder-7b-instruct-q5_k_m.gguf,gemma-3-4b-it-Q4_K_M.gguf",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(len(payload["models"]), 3)
        self.assertEqual(payload["summary"]["bestForCoding"], "qwen2.5-coder-7b-instruct-q5_k_m.gguf")
        self.assertIn(payload["summary"]["bestForSpeed"], {item["id"] for item in payload["models"]})

    def test_model_compare_keeps_curated_model_when_local_custom_mirror_shares_filename(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_defaults = pathlib.Path(temp_dir) / "defaults.json"
            defaults = json.loads(DEFAULTS_PATH.read_text(encoding="utf-8"))
            defaults.setdefault("modelChoices", {})["local_mirror_qwen36"] = {
                "key": "local-qwen36-35b-a3b-IQ2_M",
                "id": "local-qwen36-35b-a3b-IQ2_M.gguf",
                "label": "Mirror Local",
                "family": "Qwen",
                "agenticScore": 6,
                "opencodeFit": 6,
                "useCase": "agentic-general",
                "filename": "qwen36-35b-a3b-IQ2_M.gguf",
                "minExpectedBytes": 1,
                "approxSizeGiB": 10.86,
                "minimumGpuMiB": 0,
                "recommendedGpuMiB": 0,
                "minimumRamGiB": 8,
                "preferredProfiles": ["speed", "balanced"],
                "qualityTier": "compact",
                "curationLevel": "custom",
                "description": "Lokalni mirror glavnog modela.",
                "customSource": "local-file",
                "sources": [],
            }
            temp_defaults.write_text(json.dumps(defaults), encoding="utf-8")

            code, stdout, stderr = run_runtime_command(
                "model-compare",
                "--defaults",
                str(temp_defaults),
                "--gpu-mib",
                "12288",
                "--ram-gib",
                "31",
                "--cpu-threads",
                "32",
                "--model-ids",
                "qwen36-35b-a3b-IQ2_M.gguf,local-qwen36-35b-a3b-IQ2_M.gguf",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            self.assertEqual([item["id"] for item in payload["models"]], [
                "qwen36-35b-a3b-IQ2_M.gguf",
                "local-qwen36-35b-a3b-IQ2_M.gguf",
            ])
            self.assertEqual(payload["models"][0]["label"], "Qwen 3.6 35B A3B IQ2_M")
            self.assertEqual(payload["models"][1]["label"], "Mirror Local")

    def test_repair_summary_reports_found_fixed_and_manual_counts(self):
        code, stdout, stderr = run_runtime_command(
            "repair-summary",
            "--outcome",
            "partial",
            "--found-json",
            json.dumps(["runtime missing", "model incomplete"]),
            "--fixed-json",
            json.dumps(["runtime restored"]),
            "--manual-json",
            json.dumps(["confirm WDAC policy"]),
            "--notes-json",
            json.dumps(["repair all test"]),
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["outcome"], "partial")
        self.assertEqual(payload["counts"]["found"], 2)
        self.assertEqual(payload["counts"]["fixed"], 1)
        self.assertEqual(payload["counts"]["manual"], 1)
        self.assertIn("rucni korak", payload["nextStep"].lower())

    def test_repair_plan_prioritizes_app_control_before_runtime(self):
        code, stdout, stderr = run_runtime_command(
            "repair-plan",
            "--has-server",
            "false",
            "--has-model",
            "true",
            "--has-runtime",
            "false",
            "--has-opencode-config",
            "true",
            "--has-install-report",
            "true",
            "--lifecycle-state",
            "inactive",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--profile",
            "balanced",
            "--warnings-json",
            json.dumps(["Application Control / WDAC blokira llama-server.exe"]),
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertGreaterEqual(payload["stepCount"], 2)
        self.assertEqual(payload["steps"][0]["id"], "repair-app-control")
        self.assertEqual(payload["steps"][1]["id"], "repair-runtime")

    def test_repair_plan_prefers_start_server_when_stack_is_healthy_but_inactive(self):
        code, stdout, stderr = run_runtime_command(
            "repair-plan",
            "--has-server",
            "false",
            "--has-model",
            "true",
            "--has-runtime",
            "true",
            "--has-opencode-config",
            "true",
            "--has-install-report",
            "true",
            "--lifecycle-state",
            "inactive",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--profile",
            "balanced",
            "--warnings-json",
            "[]",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["stepCount"], 1)
        self.assertEqual(payload["steps"][0]["id"], "start-server")

    def test_agent_audit_marks_open_auto_system_root_as_high_risk(self):
        code, stdout, stderr = run_runtime_command(
            "agent-audit",
            "--security-mode",
            "open",
            "--capability-mode",
            "auto-commands",
            "--working-folder",
            "C:\\",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["riskLevel"], "high")
        self.assertTrue(payload["requiresWarning"])

    def test_agent_audit_marks_strict_read_only_as_low_risk(self):
        code, stdout, stderr = run_runtime_command(
            "agent-audit",
            "--security-mode",
            "strict",
            "--capability-mode",
            "read-only",
            "--working-folder",
            "C:\\Users\\demo\\Desktop",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["riskLevel"], "low")
        self.assertFalse(payload["requiresWarning"])

    def test_onboarding_checklist_marks_missing_server_as_not_ready(self):
        code, stdout, stderr = run_runtime_command(
            "onboarding-checklist",
            "--has-server",
            "false",
            "--has-model",
            "true",
            "--has-opencode-config",
            "true",
            "--profile",
            "balanced",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertFalse(payload["ready"])
        self.assertEqual(payload["steps"][0]["status"], "todo")

    def test_onboarding_checklist_marks_all_ready(self):
        code, stdout, stderr = run_runtime_command(
            "onboarding-checklist",
            "--has-server",
            "true",
            "--has-model",
            "true",
            "--has-opencode-config",
            "true",
            "--profile",
            "balanced",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertTrue(payload["ready"])
        self.assertTrue(all(step["status"] == "done" for step in payload["steps"]))

    def test_next_action_prefers_start_server_when_server_missing(self):
        code, stdout, stderr = run_runtime_command(
            "next-action",
            "--has-server",
            "false",
            "--has-model",
            "true",
            "--has-opencode-config",
            "true",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["actionId"], "start-server")

    def test_next_action_prefers_repair_when_model_missing(self):
        code, stdout, stderr = run_runtime_command(
            "next-action",
            "--has-server",
            "false",
            "--has-model",
            "false",
            "--has-opencode-config",
            "true",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["actionId"], "repair-install")

    def test_service_status_reports_warming_when_starting_without_health(self):
        code, stdout, stderr = run_runtime_command(
            "service-status",
            "--has-health",
            "false",
            "--lifecycle-state",
            "starting",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["effectiveState"], "warming")

    def test_service_status_reports_active_when_health_is_true(self):
        code, stdout, stderr = run_runtime_command(
            "service-status",
            "--has-health",
            "true",
            "--lifecycle-state",
            "starting",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["effectiveState"], "active")

    def test_service_status_reports_failed_for_timeout(self):
        code, stdout, stderr = run_runtime_command(
            "service-status",
            "--has-health",
            "false",
            "--lifecycle-state",
            "timeout",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["effectiveState"], "failed")

    def test_health_center_marks_missing_runtime_as_attention_and_recommends_runtime_repair(self):
        code, stdout, stderr = run_runtime_command(
            "health-center",
            "--has-server",
            "false",
            "--has-model",
            "true",
            "--has-runtime",
            "false",
            "--has-opencode-config",
            "true",
            "--has-install-report",
            "true",
            "--lifecycle-state",
            "inactive",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--profile",
            "balanced",
            "--warnings-json",
            "[]",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["overallState"], "attention")
        self.assertIn("repair-runtime", [item["id"] for item in payload["recommendedActions"]])

    def test_health_center_marks_fully_healthy_stack(self):
        code, stdout, stderr = run_runtime_command(
            "health-center",
            "--has-server",
            "true",
            "--has-model",
            "true",
            "--has-runtime",
            "true",
            "--has-opencode-config",
            "true",
            "--has-install-report",
            "true",
            "--lifecycle-state",
            "starting",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--profile",
            "balanced",
            "--warnings-json",
            "[]",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["overallState"], "healthy")
        self.assertEqual(payload["service"]["effectiveState"], "active")

    def test_health_center_adds_app_control_repair_when_warning_mentions_wdac(self):
        code, stdout, stderr = run_runtime_command(
            "health-center",
            "--has-server",
            "false",
            "--has-model",
            "true",
            "--has-runtime",
            "true",
            "--has-opencode-config",
            "true",
            "--has-install-report",
            "true",
            "--lifecycle-state",
            "inactive",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--profile",
            "balanced",
            "--warnings-json",
            json.dumps(["Application Control / WDAC blokira llama-server.exe"]),
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertIn("repair-app-control", [item["id"] for item in payload["recommendedActions"]])
        self.assertEqual(payload["primaryAction"]["id"], "repair-app-control")

    def test_health_center_ignores_historical_wdac_warning_when_server_is_active(self):
        code, stdout, stderr = run_runtime_command(
            "health-center",
            "--has-server",
            "true",
            "--has-model",
            "true",
            "--has-runtime",
            "true",
            "--has-opencode-config",
            "true",
            "--has-install-report",
            "true",
            "--lifecycle-state",
            "active",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--profile",
            "balanced",
            "--warnings-json",
            json.dumps(["Application Control / WDAC blokira llama-server.exe"]),
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["overallState"], "healthy")
        self.assertEqual(payload["warnings"], [])
        self.assertNotIn("repair-app-control", [item["id"] for item in payload["recommendedActions"]])

    def test_service_status_reports_inactive_without_health_or_lifecycle(self):
        code, stdout, stderr = run_runtime_command(
            "service-status",
            "--has-health",
            "false",
            "--lifecycle-state",
            "inactive",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["effectiveState"], "inactive")

    def test_token_metrics_records_current_and_history(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            response_path = temp_path / "response.json"
            history_path = temp_path / "history.json"
            response_path.write_text(
                json.dumps(
                    {
                        "_elapsed_ms": 2000,
                        "usage": {
                            "prompt_tokens": 100,
                            "completion_tokens": 50,
                        },
                        "timings": {
                            "prompt_ms": 1000,
                            "predicted_ms": 500,
                        },
                    }
                ),
                encoding="utf-8",
            )

            code, stdout, stderr = run_runtime_command(
                "token-metrics",
                "--response-file",
                str(response_path),
                "--history-file",
                str(history_path),
                "--label",
                "test-prompt",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            self.assertEqual(payload["current"]["promptTokens"], 100)
            self.assertEqual(payload["current"]["completionTokens"], 50)
            self.assertEqual(payload["current"]["promptTokensPerSecond"], 100.0)
            self.assertEqual(payload["current"]["completionTokensPerSecond"], 100.0)
            self.assertEqual(payload["historyCount"], 1)
            self.assertEqual(payload["requestCount"], 1)
            self.assertEqual(payload["activity"]["sources"]["testPrompt"], 1)
            self.assertEqual(payload["activity"]["lastSource"], "testPrompt")
            self.assertEqual(len(payload["activity"]["recentActivities"]), 1)
            self.assertEqual(payload["activity"]["recentActivities"][0]["source"], "testPrompt")
            self.assertEqual(payload["activity"]["recentActivities"][0]["status"], "ok")

    def test_token_metrics_accepts_utf8_bom_response_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            response_path = temp_path / "response-bom.json"
            history_path = temp_path / "history.json"
            response_payload = {
                "_elapsed_ms": 1500,
                "usage": {
                    "prompt_tokens": 60,
                    "completion_tokens": 30,
                },
                "timings": {
                    "prompt_ms": 750,
                    "predicted_ms": 500,
                },
            }
            response_path.write_text(json.dumps(response_payload), encoding="utf-8-sig")

            code, stdout, stderr = run_runtime_command(
                "token-metrics",
                "--response-file",
                str(response_path),
                "--history-file",
                str(history_path),
                "--label",
                "test-prompt",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            self.assertEqual(payload["current"]["promptTokens"], 60)
            self.assertEqual(payload["current"]["completionTokens"], 30)

    def test_log_token_metrics_parses_llama_timing_block_and_dedupes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            log_path = temp_path / "llama.err.log"
            history_path = temp_path / "history.json"
            log_path.write_text(
                "\n".join(
                    [
                        "slot print_timing: id  1 | task 5421 | ",
                        "prompt eval time =    2904.68 ms /    14 tokens (  207.48 ms per token,     4.82 tokens per second)",
                        "       eval time =    7204.15 ms /    16 tokens (  450.26 ms per token,     2.22 tokens per second)",
                        "      total time =   10108.83 ms /    30 tokens",
                        "slot      release: id  1 | task 5421 | stop processing: n_tokens = 29, truncated = 0",
                    ]
                ),
                encoding="utf-8",
            )

            code, stdout, stderr = run_runtime_command(
                "log-token-metrics",
                "--log-file",
                str(log_path),
                "--history-file",
                str(history_path),
                "--label",
                "live-log",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            self.assertEqual(payload["current"]["promptTokens"], 14)
            self.assertEqual(payload["current"]["completionTokens"], 16)
            self.assertEqual(payload["current"]["totalTokens"], 30)
            self.assertEqual(payload["current"]["promptTokensPerSecond"], 4.82)
            self.assertEqual(payload["current"]["completionTokensPerSecond"], 2.22)
            self.assertEqual(payload["current"]["totalTokensPerSecond"], 2.97)
            self.assertEqual(payload["historyCount"], 1)

            code, stdout, stderr = run_runtime_command(
                "log-token-metrics",
                "--log-file",
                str(log_path),
                "--history-file",
                str(history_path),
                "--label",
                "live-log",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            self.assertEqual(payload["historyCount"], 1)

    def test_token_metrics_recent_activities_preserve_order_and_source_types(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            history_path = temp_path / "history.json"

            def write_response(name: str, prompt_tokens: int, completion_tokens: int, prompt_ms: int, completion_ms: int) -> pathlib.Path:
                response_path = temp_path / f"{name}.json"
                response_path.write_text(
                    json.dumps(
                        {
                            "_elapsed_ms": prompt_ms + completion_ms,
                            "usage": {
                                "prompt_tokens": prompt_tokens,
                                "completion_tokens": completion_tokens,
                            },
                            "timings": {
                                "prompt_ms": prompt_ms,
                                "predicted_ms": completion_ms,
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                return response_path

            scenarios = [
                ("test-prompt", "testPrompt"),
                ("opencode-chat", "opencode"),
                ("manual-request", "other"),
            ]

            for index, (label, _) in enumerate(scenarios, start=1):
                response_path = write_response(label, 10 * index, 5 * index, 1000, 500)
                code, stdout, stderr = run_runtime_command(
                    "token-metrics",
                    "--response-file",
                    str(response_path),
                    "--history-file",
                    str(history_path),
                    "--label",
                    label,
                )
                self.assertEqual(code, 0, msg=stderr)

            payload = json.loads(stdout)
            self.assertEqual(payload["requestCount"], 3)
            self.assertEqual(payload["activity"]["lastSource"], "other")
            self.assertEqual(
                [item["source"] for item in payload["activity"]["recentActivities"]],
                ["other", "opencode", "testPrompt"],
            )
            self.assertEqual(
                [item["label"] for item in payload["activity"]["recentActivities"]],
                ["manual-request", "opencode-chat", "test-prompt"],
            )
            self.assertEqual(payload["activity"]["sourceBreakdown"]["testPrompt"]["count"], 1)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["opencode"]["count"], 1)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["other"]["count"], 1)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["other"]["lastLabel"], "manual-request")
            self.assertEqual(payload["activity"]["sourceBreakdown"]["testPrompt"]["averageTotalMs"], 1500.0)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["opencode"]["averageTotalMs"], 1500.0)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["other"]["averageTotalMs"], 1500.0)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["testPrompt"]["averageTotalTokensPerSecond"], 10.0)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["opencode"]["averageTotalTokensPerSecond"], 20.0)
            self.assertEqual(payload["activity"]["sourceBreakdown"]["other"]["averageTotalTokensPerSecond"], 30.0)

    def test_token_metrics_recent_activities_keep_last_ten_items(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            history_path = temp_path / "history.json"

            for index in range(12):
                response_path = temp_path / f"recent-{index}.json"
                response_path.write_text(
                    json.dumps(
                        {
                            "_elapsed_ms": 1200 + index,
                            "usage": {
                                "prompt_tokens": 100 + index,
                                "completion_tokens": 20 + index,
                            },
                            "timings": {
                                "prompt_ms": 700,
                                "predicted_ms": 500,
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                code, stdout, stderr = run_runtime_command(
                    "token-metrics",
                    "--response-file",
                    str(response_path),
                    "--history-file",
                    str(history_path),
                    "--label",
                    f"manual-{index}",
                )
                self.assertEqual(code, 0, msg=stderr)

            payload = json.loads(stdout)
            recent_labels = [item["label"] for item in payload["activity"]["recentActivities"]]
            self.assertEqual(len(recent_labels), 10)
            self.assertEqual(recent_labels[0], "manual-11")
            self.assertEqual(recent_labels[-1], "manual-2")

    def test_token_metrics_stability_marks_fast_history_as_stable(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            history_path = temp_path / "history.json"

            for index in range(4):
                response_path = temp_path / f"fast-{index}.json"
                response_path.write_text(
                    json.dumps(
                        {
                            "_elapsed_ms": 1200 + index * 50,
                            "usage": {
                                "prompt_tokens": 80,
                                "completion_tokens": 40,
                            },
                            "timings": {
                                "prompt_ms": 700,
                                "predicted_ms": 500 + index * 50,
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                code, stdout, stderr = run_runtime_command(
                    "token-metrics",
                    "--response-file",
                    str(response_path),
                    "--history-file",
                    str(history_path),
                    "--label",
                    "opencode-fast",
                )
                self.assertEqual(code, 0, msg=stderr)

            payload = json.loads(stdout)
            self.assertEqual(payload["activity"]["stability"]["level"], "stable")
            self.assertGreaterEqual(payload["activity"]["stability"]["score"], 80)

    def test_token_metrics_stability_marks_slow_history_as_risky(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            history_path = temp_path / "history.json"

            for index in range(4):
                response_path = temp_path / f"slow-{index}.json"
                response_path.write_text(
                    json.dumps(
                        {
                            "_elapsed_ms": 9000 + index * 2000,
                            "usage": {
                                "prompt_tokens": 40,
                                "completion_tokens": 20,
                            },
                            "timings": {
                                "prompt_ms": 3000 + index * 500,
                                "predicted_ms": 6000 + index * 1500,
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                code, stdout, stderr = run_runtime_command(
                    "token-metrics",
                    "--response-file",
                    str(response_path),
                    "--history-file",
                    str(history_path),
                    "--label",
                    "manual-slow",
                )
                self.assertEqual(code, 0, msg=stderr)

            payload = json.loads(stdout)
            self.assertEqual(payload["activity"]["stability"]["level"], "risky")
            self.assertLessEqual(payload["activity"]["stability"]["score"], 39)

    def test_token_metrics_trend_detects_faster_throughput_and_lower_latency(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            history_path = temp_path / "history.json"
            samples = [
                (60, 30, 1800, 1200),
                (80, 40, 1500, 900),
                (100, 50, 1200, 700),
                (120, 60, 1000, 500),
            ]

            for index, (prompt_tokens, completion_tokens, prompt_ms, completion_ms) in enumerate(samples):
                response_path = temp_path / f"trend-fast-{index}.json"
                response_path.write_text(
                    json.dumps(
                        {
                            "_elapsed_ms": prompt_ms + completion_ms,
                            "usage": {
                                "prompt_tokens": prompt_tokens,
                                "completion_tokens": completion_tokens,
                            },
                            "timings": {
                                "prompt_ms": prompt_ms,
                                "predicted_ms": completion_ms,
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                code, stdout, stderr = run_runtime_command(
                    "token-metrics",
                    "--response-file",
                    str(response_path),
                    "--history-file",
                    str(history_path),
                    "--label",
                    "opencode-trend-fast",
                )
                self.assertEqual(code, 0, msg=stderr)

            payload = json.loads(stdout)
            self.assertEqual(payload["activity"]["throughputTrend"]["direction"], "up")
            self.assertEqual(payload["activity"]["latencyTrend"]["direction"], "down")
            self.assertEqual(payload["activity"]["throughputTrend"]["signal"], "^")
            self.assertEqual(payload["activity"]["latencyTrend"]["signal"], "v")

    def test_token_metrics_trend_detects_falling_throughput_and_higher_latency(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            history_path = temp_path / "history.json"
            samples = [
                (120, 60, 900, 500),
                (100, 50, 1200, 700),
                (80, 40, 1500, 900),
                (60, 30, 1800, 1200),
            ]

            for index, (prompt_tokens, completion_tokens, prompt_ms, completion_ms) in enumerate(samples):
                response_path = temp_path / f"trend-slow-{index}.json"
                response_path.write_text(
                    json.dumps(
                        {
                            "_elapsed_ms": prompt_ms + completion_ms,
                            "usage": {
                                "prompt_tokens": prompt_tokens,
                                "completion_tokens": completion_tokens,
                            },
                            "timings": {
                                "prompt_ms": prompt_ms,
                                "predicted_ms": completion_ms,
                            },
                        }
                    ),
                    encoding="utf-8",
                )
                code, stdout, stderr = run_runtime_command(
                    "token-metrics",
                    "--response-file",
                    str(response_path),
                    "--history-file",
                    str(history_path),
                    "--label",
                    "manual-trend-slow",
                )
                self.assertEqual(code, 0, msg=stderr)

            payload = json.loads(stdout)
            self.assertEqual(payload["activity"]["throughputTrend"]["direction"], "down")
            self.assertEqual(payload["activity"]["latencyTrend"]["direction"], "up")
            self.assertEqual(payload["activity"]["throughputTrend"]["signal"], "v")
            self.assertEqual(payload["activity"]["latencyTrend"]["signal"], "^")

    def test_token_metrics_warming_state_uses_ascii_label(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = pathlib.Path(temp_dir)
            history_path = temp_path / "history.json"
            response_path = temp_path / "warming.json"
            response_path.write_text(
                json.dumps(
                    {
                        "_elapsed_ms": 900,
                        "usage": {
                            "prompt_tokens": 12,
                            "completion_tokens": 10,
                        },
                        "timings": {
                            "prompt_ms": 400,
                            "predicted_ms": 300,
                        },
                    }
                ),
                encoding="utf-8",
            )
            code, stdout, stderr = run_runtime_command(
                "token-metrics",
                "--response-file",
                str(response_path),
                "--history-file",
                str(history_path),
                "--label",
                "warming-check",
            )
            self.assertEqual(code, 0, msg=stderr)
            payload = json.loads(stdout)
            self.assertEqual(payload["activity"]["stability"]["level"], "warming")
            self.assertEqual(payload["activity"]["stability"]["label"], "zagreva se")

    def test_repair_summary_accepts_unit_separator_encoded_lists(self):
        code, stdout, stderr = run_runtime_command(
            "repair-summary",
            "--outcome",
            "completed",
            "--found-json",
            "Prva stavka\x1fDruga stavka",
            "--fixed-json",
            "Popravljeno A\x1fPopravljeno B",
            "--manual-json",
            "",
            "--notes-json",
            "Napomena",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["found"], ["Prva stavka", "Druga stavka"])
        self.assertEqual(payload["fixed"], ["Popravljeno A", "Popravljeno B"])
        self.assertEqual(payload["notes"], ["Napomena"])

    def test_health_center_accepts_unit_separator_encoded_warnings(self):
        code, stdout, stderr = run_runtime_command(
            "health-center",
            "--has-server",
            "false",
            "--has-model",
            "true",
            "--has-runtime",
            "true",
            "--has-opencode-config",
            "true",
            "--has-install-report",
            "true",
            "--warnings-json",
            "WDAC warning\x1fApp Control warning",
            "--lifecycle-state",
            "inactive",
            "--model-id",
            "qwen36-35b-a3b-IQ2_M.gguf",
            "--profile",
            "balanced",
        )
        self.assertEqual(code, 0, msg=stderr)
        payload = json.loads(stdout)
        warning_titles = [item["title"] for item in payload["warnings"]]
        self.assertTrue(any("WDAC" in title for title in warning_titles))
        self.assertTrue(any("App Control" in title for title in warning_titles))


if __name__ == "__main__":
    unittest.main()
