import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROL_CENTER_PATH = REPO_ROOT / "launcher" / "windows" / "control-center.ps1"


class WindowsControlCenterLayoutTests(unittest.TestCase):
    def test_control_center_uses_separate_tools_and_benchmark_tabs(self):
        content = CONTROL_CENTER_PATH.read_text(encoding="utf-8")
        self.assertIn('$toolsTab.Text = "Tools"', content)
        self.assertIn('$benchmarkTab.Text = "Benchmark"', content)
        self.assertIn('$launchPrimaryGroup.Text = "Pokretanje"', content)
        self.assertIn('Start llama.cpp server', content)
        self.assertIn('Stop llama.cpp server', content)
        self.assertIn('Run OpenCode', content)
        self.assertIn('Run llama.cpp web', content)
        self.assertIn('Model browser', content)
        self.assertIn('Test throughput', content)
        self.assertIn('System.Windows.Forms.DataVisualization', content)
        self.assertIn('Refresh-BenchmarkChart', content)


if __name__ == "__main__":
    unittest.main()
