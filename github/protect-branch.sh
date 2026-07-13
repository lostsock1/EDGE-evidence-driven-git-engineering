#!/usr/bin/env bash
# protect-branch.sh — apply the EDGE branch-protection posture to the trunk.
#
# The human merge gate is MECHANICAL, not behavioral: agents cannot push to the
# trunk even if a prompt goes wrong, because GitHub rejects it. PRs require
# green required checks + an up-to-date branch; 0 approvals (the operator IS
# the merge button); no force pushes; no deletions; admins included. Empty
# checks require ALLOW_EMPTY_CHECKS=1 and do not provide CI enforcement.
#
# Usage:
#   OWNER=you REPO=yourrepo BRANCH=main CHECKS="tests,lint" ./protect-branch.sh
# Or with ~/.config/edge-rdd/config.env present, just: ./protect-branch.sh
#
# Requires: gh (authed with admin on the repo), python3.

set -euo pipefail

CONFIG="${EDGE_RDD_CONFIG:-$HOME/.config/edge-rdd/config.env}"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

OWNER="${OWNER:-${RDD_REPO_SLUG%%/*}}"
REPO="${REPO:-${RDD_REPO_SLUG##*/}}"
BRANCH="${BRANCH:-${RDD_MAIN_BRANCH:-main}}"
if [[ -v CHECKS ]]; then
  CHECKS_VALUE="$CHECKS"
elif [[ -v RDD_REQUIRED_CHECKS ]]; then
  CHECKS_VALUE="$RDD_REQUIRED_CHECKS"
else
  CHECKS_VALUE="tests,lint"
fi

if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  echo "protect-branch: set OWNER/REPO (or RDD_REPO_SLUG in config.env)" >&2
  exit 2
fi
if [ -z "${CHECKS_VALUE//[[:space:],]/}" ] && [ "${ALLOW_EMPTY_CHECKS:-0}" != 1 ]; then
  echo "protect-branch: refusing zero required CI contexts; set ALLOW_EMPTY_CHECKS=1 only for a repo that intentionally has no CI (chat gate will remain non-actionable)" >&2
  exit 2
fi

# Build the contexts JSON array from the comma-separated list, trimming spaces.
CONTEXTS_JSON="$(python3 - "$CHECKS_VALUE" <<'PY'
import json, sys
print(json.dumps([c.strip() for c in sys.argv[1].split(",") if c.strip()]))
PY
)"

echo "Protecting $OWNER/$REPO@$BRANCH with required checks: $CONTEXTS_JSON"

gh api -X PUT "repos/$OWNER/$REPO/branches/$BRANCH/protection" --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": $CONTEXTS_JSON
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

ACTUAL_PROTECTION="$(gh api "repos/$OWNER/$REPO/branches/$BRANCH/protection")"
python3 - "$CONTEXTS_JSON" "$ACTUAL_PROTECTION" <<'PY'
import json, sys
expected = sorted(json.loads(sys.argv[1]))
actual = json.loads(sys.argv[2])

def enabled(name):
    value = actual.get(name)
    return value is True or (isinstance(value, dict) and value.get("enabled") is True)

errors = []
checks = actual.get("required_status_checks")
contexts = sorted((checks or {}).get("contexts") or [])
if contexts != expected:
    errors.append(f"contexts expected {expected!r}, got {contexts!r}")
# GitHub normalizes an explicit empty context list to null. Strictness is only
# meaningful/verifiable when at least one required check exists.
if expected and (not checks or checks.get("strict") is not True):
    errors.append("required_status_checks.strict is not true")
if not enabled("enforce_admins"):
    errors.append("enforce_admins is not enabled")
reviews = actual.get("required_pull_request_reviews") or {}
if reviews.get("required_approving_review_count") != 0:
    errors.append("required approving review count is not 0")
for setting in ("allow_force_pushes", "allow_deletions"):
    value = actual.get(setting)
    is_enabled = value is True or (isinstance(value, dict) and value.get("enabled") is True)
    if is_enabled:
        errors.append(f"{setting} is enabled")
if errors:
    print("protect-branch: verification failed: " + "; ".join(errors), file=sys.stderr)
    raise SystemExit(1)
if not contexts:
    print("WARNING: protection verified with zero CI contexts; GitHub does not enforce green checks and the EDGE chat gate must remain non-actionable")
else:
    print("Done. Verified protection posture with required checks: " + json.dumps(contexts, separators=(",", ":")))
PY
