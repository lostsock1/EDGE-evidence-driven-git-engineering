#!/usr/bin/env bash
# kickoff.sh — first-boot handshake for a new EDGE-RDD project thread.
#
# Run ONCE per project, after install.sh --apply, the openclaw.json merge, the
# repo docs seed, CI, and branch protection. It:
#   1. PREFLIGHTS the GitHub connection — the loop expects a live repo, and a
#      kickoff into a thread whose repo isn't wired just strands the agent.
#   2. Renders messages/kickoff.md + messages/palette.md with your RDD_* values.
#   3. Posts both into the project thread. PIN the palette message manually.
#
# Usage:
#   bash scripts/kickoff.sh              # uses ~/.config/edge-rdd/config.env
#   EDGE_RDD_CONFIG=~/.config/edge-rdd/<project>.env bash scripts/kickoff.sh
#   bash scripts/kickoff.sh --dry-run    # print instead of send; preflight
#                                        # failures downgrade to warnings
#
# Deliberately NOT part of install.sh: installs run half-configured and re-run
# on updates — an auto-fired kickoff would double-post or post into a dead
# thread. Sending is a one-time, human-initiated act.

set -uo pipefail
cd "$(dirname "$0")/.."

CONFIG="${EDGE_RDD_CONFIG:-$HOME/.config/edge-rdd/config.env}"
if [ ! -f "$CONFIG" ]; then
  echo "kickoff: config not found: $CONFIG — run install.sh --apply first (or set EDGE_RDD_CONFIG)" >&2
  exit 2
fi
# shellcheck disable=SC1090
. "$CONFIG"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
WARNINGS=0
warn() { echo "WARN: $*"; WARNINGS=$((WARNINGS+1)); }
fail() { # hard stop normally; warning in --dry-run
  if [ "$DRY" = 1 ]; then warn "$*"; else echo "FAIL: $* " >&2; exit 1; fi
}

MAIN="${RDD_MAIN_BRANCH:-main}"
DOCS="${RDD_DOCS_DIR:-docs/agent}"

echo "=== kickoff preflight (config: $CONFIG) ==="

# --- GitHub connection is EXPECTED, not optional ------------------------------
command -v gh >/dev/null 2>&1 || fail "gh CLI not installed"
if command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 || fail "gh not authenticated — run: gh auth login"
  [ -n "${RDD_REPO_SLUG:-}" ] || fail "RDD_REPO_SLUG unset in config"
  if [ -n "${RDD_REPO_SLUG:-}" ]; then
    timeout 30 gh repo view "$RDD_REPO_SLUG" --json name >/dev/null 2>&1 \
      || fail "GitHub repo $RDD_REPO_SLUG not reachable — create it (gh repo create) before kicking off"
    timeout 30 gh api "repos/$RDD_REPO_SLUG/branches/$MAIN/protection" >/dev/null 2>&1 \
      || warn "trunk '$MAIN' is NOT branch-protected — the human merge gate is mechanical only with protection ON (run github/protect-branch.sh)"
  fi
fi
if [ -d "${RDD_REPO_DIR:-/nonexistent}/.git" ]; then
  origin_url="$(git -C "$RDD_REPO_DIR" remote get-url origin 2>/dev/null || true)"
  case "$origin_url" in
    *"${RDD_REPO_SLUG:-__unset__}"*) : ;;
    *) fail "clone origin ($origin_url) does not match RDD_REPO_SLUG (${RDD_REPO_SLUG:-unset})" ;;
  esac
  git -C "$RDD_REPO_DIR" show-ref --verify --quiet "refs/remotes/origin/$MAIN" \
    || warn "origin/$MAIN not found in the clone — git fetch, or check RDD_MAIN_BRANCH"
  [ -f "$RDD_REPO_DIR/$DOCS/PROJECT_STATE.md" ] \
    || warn "handoff docs not seeded ($DOCS/PROJECT_STATE.md missing) — commit project-repo/docs/agent/ into the repo first"
else
  fail "local clone missing or not a git repo: ${RDD_REPO_DIR:-unset} — the wrapper refuses to dispatch without it"
fi

# --- chat surface ---------------------------------------------------------------
[ -n "${RDD_TG_TARGET:-}" ] || fail "RDD_TG_TARGET unset — no thread to kick off"
OCLI="${RDD_OPENCLAW:-$HOME/.local/bin/openclaw}"
[ -x "$OCLI" ] || fail "openclaw CLI not found at $OCLI"

echo "preflight done ($WARNINGS warning(s))."

# --- render the two messages from the config's RDD_* values ----------------------
render() { # render <template-file>  -> stdout, {{KEY}} <- RDD_KEY from config
  python3 - "$1" "$CONFIG" <<'PY'
import re, sys
path, cfg = sys.argv[1], sys.argv[2]
tok = {}
for line in open(cfg):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    k, v = k.strip(), v.strip().strip('"').strip("'")
    if k.startswith("RDD_"):
        tok[k[4:]] = v
text = open(path).read()
out = re.sub(r"\{\{([A-Z0-9_]+)\}\}", lambda m: tok.get(m.group(1), m.group(0)), text)
leftover = sorted(set(re.findall(r"\{\{[A-Z0-9_]+\}\}", out)))
if leftover:
    print(f"WARN unresolved tokens: {', '.join(leftover)}", file=sys.stderr)
sys.stdout.write(out)
PY
}

KICKOFF="$(render messages/kickoff.md)"
PALETTE="$(render messages/palette.md)"

send_msg() { # send_msg "<body>"
  local body="$1"
  if [ "$DRY" = 1 ]; then
    printf -- '--- DRY-RUN message >>>\n%s\n<<< end ---\n' "$body"
    return 0
  fi
  local -a th=()
  [ -n "${RDD_TG_THREAD:-}" ] && th=(--thread-id "$RDD_TG_THREAD")
  timeout 30 "$OCLI" message send --channel "${RDD_TG_CHANNEL:-telegram}" \
    --target "$RDD_TG_TARGET" "${th[@]}" --message "$body"
}

send_msg "$KICKOFF"
send_msg "$PALETTE"

if [ "$DRY" = 1 ]; then
  echo "dry run complete — nothing sent."
else
  echo ""
  echo "Kickoff + command palette sent to ${RDD_TG_TARGET}${RDD_TG_THREAD:+ / topic $RDD_TG_THREAD}."
  echo "NOW: pin the palette message in the thread (long-press → Pin)."
  echo "The agent will read its charter and propose the first work order — reply 'go' to dispatch."
fi
