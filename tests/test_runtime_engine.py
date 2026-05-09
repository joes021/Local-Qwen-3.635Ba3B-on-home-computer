import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "local_qwen_runtime.py"
DEFAULTS_PATH = REPO_ROOT / "config" / "profiles" / "defaults.json"


def run_runtime_command(*args):
    command = [sys.executable, str(SCRIPT_PATH), *args]
    completed = subprocess.run(command, capture_output=True, text=True)
    return completed.returncode, completed.stdout, completed.stderr


class RuntimeEngineTests(unittest.TestCase):
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
        self.assertGreaterEqual(len(iq2["sources"]), 2)

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


if __name__ == "__main__":
    unittest.main()
