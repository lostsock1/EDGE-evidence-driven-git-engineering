import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]


class InstallSmokeTests(unittest.TestCase):
    def test_clean_apply_creates_notes_and_shell_safe_project_config(self):
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            source = temp / "template"
            shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns(".git", "rendered", "template.env", "__pycache__"))

            remote = temp / "remote repo"
            remote.mkdir()
            subprocess.run(["git", "init", "-q", str(remote)], check=True)
            subprocess.run(["git", "-C", str(remote), "config", "user.email", "test@example.invalid"], check=True)
            subprocess.run(["git", "-C", str(remote), "config", "user.name", "Test"], check=True)
            (remote / "README.md").write_text("seed\n")
            subprocess.run(["git", "-C", str(remote), "add", "README.md"], check=True)
            subprocess.run(["git", "-C", str(remote), "commit", "-qm", "seed"], check=True)

            home = temp / "home dir"; home.mkdir()
            checkout = home / "projects" / "Demo Project"
            env_text = (source / "template.env.example").read_text()
            replacements = {
                "RDD_PROJECT_NAME=MyProject": "RDD_PROJECT_NAME='Demo Project'",
                "RDD_PROJECT_SLUG=myproject": "RDD_PROJECT_SLUG=demo",
                "RDD_REPO_SLUG=youruser/yourrepo": "RDD_REPO_SLUG=owner/demo",
                "RDD_REPO_URL=https://github.com/youruser/yourrepo": f"RDD_REPO_URL='{remote}'",
                "RDD_REPO_DIR=~/projects/MyProject": f"RDD_REPO_DIR='{checkout}'",
            }
            for old, new in replacements.items():
                env_text = env_text.replace(old, new)
            (source / "template.env").write_text(env_text)

            env = os.environ.copy(); env["HOME"] = str(home)
            result = subprocess.run(["bash", "install.sh", "--apply"], cwd=source, env=env,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            workspace = home / ".openclaw" / "workspace-edge"
            self.assertTrue((workspace / "projects" / "demo" / "notes" / "SUPERIOR_ARCHITECTURE.md").is_file())
            # Every skill behind a chat button must be installed AND symlinked
            # into ~/.openclaw/skills, or the buttons that fire it are dead taps.
            for skill in ("gate", "research", "dispatch"):
                self.assertTrue((workspace / "skills" / skill / "SKILL.md").is_file(),
                                f"{skill} skill not installed")
                self.assertTrue((home / ".openclaw" / "skills" / skill).is_symlink(),
                                f"{skill} skill not symlinked")
            config = workspace / "config" / "edge-rdd" / "demo.env"
            loaded = subprocess.run(
                ["bash", "-c", '. "$1"; printf "%s" "$RDD_REPO_DIR"', "bash", str(config)],
                text=True, capture_output=True, check=True,
            )
            self.assertEqual(loaded.stdout, str(checkout))

    def test_kickoff_resolves_shared_default_project_config(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); home = root / "home"; home.mkdir()
            config_dir = home / ".config" / "edge-rdd"; config_dir.mkdir(parents=True)
            project = root / "project.env"
            project.write_text("RDD_REPO_SLUG=owner/demo\nRDD_REPO_DIR=/missing\n")
            shared = config_dir / "config.env"
            shared.write_text(f"RDD_DEFAULT_PROJECT_CONFIG={project}\n")
            result = subprocess.run(["bash", str(ROOT / "scripts/kickoff.sh"), "--dry-run"],
                                    env={**os.environ, "HOME": str(home)},
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(f"config: {project}", result.stdout)
            self.assertNotIn("config: " + str(shared), result.stdout)


if __name__ == "__main__":
    unittest.main()
