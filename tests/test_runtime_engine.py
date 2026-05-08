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


if __name__ == "__main__":
    unittest.main()
