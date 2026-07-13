import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "github" / "protect-branch.sh"
FAKE = '''#!/usr/bin/env bash
if [[ " $* " == *" -X PUT "* ]]; then
  cat >"$CAPTURE"
  echo '{}'
else
  python3 - "$CAPTURE" <<'PY'
import json, sys
request = json.load(open(sys.argv[1]))
print(json.dumps({
  "required_status_checks": request["required_status_checks"] if request["required_status_checks"]["contexts"] else None,
  "enforce_admins": {"enabled": request["enforce_admins"]},
  "required_pull_request_reviews": request["required_pull_request_reviews"],
  "allow_force_pushes": {"enabled": request["allow_force_pushes"]},
  "allow_deletions": {"enabled": request["allow_deletions"]},
}))
PY
fi
'''


class ProtectBranchTests(unittest.TestCase):
    def test_explicit_empty_checks_stay_empty_and_are_verified(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            gh = root / "gh"; gh.write_text(FAKE); gh.chmod(0o755)
            capture = root / "request.json"
            env = os.environ.copy()
            env.update({"PATH": f"{root}:{env['PATH']}", "OWNER": "owner", "REPO": "repo",
                        "BRANCH": "main", "CHECKS": "", "CAPTURE": str(capture),
                        "EDGE_RDD_CONFIG": str(root / "missing.env")})
            result = subprocess.run([str(SCRIPT)], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('"contexts": []', capture.read_text())
            self.assertIn("Verified protection posture with required checks: []", result.stdout)


if __name__ == "__main__":
    unittest.main()
