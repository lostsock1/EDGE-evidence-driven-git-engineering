import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "edge-coder-run.sh"


class DispatchConfigTests(unittest.TestCase):
    def run_dispatch(self, shared, project, effort=None):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            repo = root / "repo"; subprocess.run(["git", "init", "-q", str(repo)], check=True)
            shared_path = root / "config.env"
            project_path = root / "project.env"
            shared_path.write_text(shared.replace("$REPO", str(repo)))
            project_path.write_text(project.replace("$REPO", str(repo)))
            env = os.environ.copy()
            env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared_path),
                        "EDGE_RDD_CONFIG": str(project_path)})
            if effort:
                env["EDGE_CODER_EFFORT"] = effort
            return subprocess.run([str(SCRIPT), "--fg", "test task"], env=env, text=True, capture_output=True)

    def test_selected_project_cannot_inherit_shared_repo_identity(self):
        shared = 'RDD_REPO_DIR=$REPO\nRDD_MODELS="a b"\nRDD_TIMEOUTS_BG="1 1"\nRDD_TIMEOUTS_FG="1 1"\n'
        result = self.run_dispatch(shared, "RDD_PROJECT_SLUG=other\n")
        self.assertEqual(result.returncode, 2)
        self.assertIn("has no RDD_REPO_DIR", result.stderr)

    def test_timeout_arrays_must_align_with_models(self):
        shared = 'RDD_MODELS="a b"\nRDD_TIMEOUTS_BG="1 1"\nRDD_TIMEOUTS_FG="1"\n'
        result = self.run_dispatch(shared, "RDD_REPO_DIR=$REPO\n")
        self.assertEqual(result.returncode, 2)
        self.assertIn("RDD_TIMEOUTS_FG has 1 value", result.stderr)

    def test_max_requires_explicit_aligned_variant_map(self):
        shared = 'RDD_MODELS="a b"\nRDD_TIMEOUTS_BG="1 1"\nRDD_TIMEOUTS_FG="1 1"\nRDD_VARIANT_POLICY=auto\n'
        result = self.run_dispatch(shared, "RDD_REPO_DIR=$REPO\n", effort="max")
        self.assertEqual(result.returncode, 2)
        self.assertIn("effort=max requires an explicit RDD_VARIANTS_MAX", result.stderr)

    def run_with_fake_opencode(self, project_extra=""):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            repo = root / "repo"; subprocess.run(["git", "init", "-q", str(repo)], check=True)
            fake = root / "opencode"
            fake.write_text(r'''#!/usr/bin/env bash
if [[ "$*" == *"say hello"* ]]; then
  printf '%s\n' '{"type":"text","text":"hello"}'
  exit 0
fi
printf '%s\n' '{"type":"text","text":"=== LOOP STATUS ===\nREVIEWER: Pass — fake\n=== END ==="}'
exit 7
''')
            fake.chmod(0o755)
            shared = root / "config.env"
            shared.write_text(
                f'RDD_OPENCODE={fake}\nRDD_MODELS="fake/model"\n'
                'RDD_TIMEOUTS_BG="5"\nRDD_TIMEOUTS_FG="5"\n'
                f'RDD_LOG={root}/run.log\nRDD_RUNS_DIR={root}/runs\nRDD_LOCKDIR={root}/locks\n'
            )
            project = root / "project.env"
            project.write_text(f'RDD_REPO_DIR={repo}\n{project_extra}')
            env = os.environ.copy()
            env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared),
                        "EDGE_RDD_CONFIG": str(project)})
            return subprocess.run([str(SCRIPT), "--fg", "test task"], env=env,
                                  text=True, capture_output=True)

    def test_nonzero_opencode_exit_is_failure_even_with_text_event(self):
        result = self.run_with_fake_opencode()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("all 1 model tiers failed", result.stderr)

    def test_project_file_cannot_override_shared_runtime_policy(self):
        result = self.run_with_fake_opencode('RDD_MODELS="evil/one evil/two"\nRDD_TIMEOUTS_FG="1 1"\n')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn("arrays must be index-aligned", result.stderr)


if __name__ == "__main__":
    unittest.main()
