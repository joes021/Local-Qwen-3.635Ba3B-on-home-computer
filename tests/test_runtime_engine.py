import json
import pathlib
import subprocess
import sys
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
        iq2 = next(item for item in payload["models"] if item["id"] == "qwen36-35b-a3b-IQ2_M.gguf")
        self.assertGreaterEqual(len(iq2["sources"]), 2)


if __name__ == "__main__":
    unittest.main()
