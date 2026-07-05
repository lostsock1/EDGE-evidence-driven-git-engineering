#!/usr/bin/env bash
# edge-pr-gate.sh — EDGE GitHub PR gate: periodic repo sweep + operator-approved
# agent-executed merges and branch hygiene.
#
# Part of the "EDGE — Evidence-Driven Git Engineering" template.
#
# WHAT IT DOES
#   Every heartbeat tick (default: a 6h task in the research agent's
#   HEARTBEAT.md) the agent runs `sweep`. For every configured project this:
#     - lists open PRs and their CI verdict (green / red / pending)
#     - lists every non-trunk branch and classifies it (active PR head,
#       merged/closed-PR leftover, orphan with/without unique commits)
#     - turns actionable items into single-use pending ACTIONS (merge a green
#       PR, prune a stale branch) stored in a state file
#     - posts ONE approval message per project to its own chat thread, with an
#       inline button per action (callback value `eg:<id>`) — so the operator
#       approves from the phone with one tap (or a 👍/✅ reaction + "approve")
#   When the operator taps a button, the channel delivers the callback value to
#   the agent as text; the agent then runs `act <id>`, which RE-VERIFIES the
#   preconditions (PR still open + checks still green; branch still stale) and
#   only then executes via gh, posts the outcome back to the thread, and marks
#   the action done. Trunks stay clean: merges use --delete-branch and prunes
#   delete stale remote branches, converging every project to trunk-only.
#
# THE HUMAN GATE IS UNCHANGED IN SPIRIT: nothing merges without an explicit
# operator approval — the approval surface just moves from the GitHub UI to a
# button in the project thread. Actions are single-use, minted only by sweep
# from observed repo state, re-verified at execution time, and the agent never
# runs `gh pr merge` / branch deletion outside `act`.
#
# MODES
#   sweep [--dry-run]   scan all projects, mint/reconcile actions, post approval
#                       buttons (dry-run prints payloads instead of sending).
#                       Prints a per-project summary; last line is ALL_CLEAN
#                       when nothing needs attention anywhere.
#   act <id>            execute one pending action after operator approval
#   pending [label]     list pending actions (optionally one project)
#   status              state summary: pending actions + recent results
#
# CONFIGURATION
#   Projects = every *.env file in $RDD_GATE_CONFIG_DIR (default
#   ~/.config/edge-rdd) that defines RDD_REPO_DIR. The same files the dispatch
#   wrapper (edge-coder-run.sh) uses — no second registry to drift.
#   Per-file keys used here: RDD_REPO_DIR, RDD_MAIN_BRANCH, RDD_TG_CHANNEL,
#   RDD_TG_TARGET, RDD_TG_THREAD, RDD_OPENCLAW.
#   Gate knobs (environment, with defaults):
#     RDD_GATE_CONFIG_DIR    ~/.config/edge-rdd
#     RDD_GATE_STATE_DIR     ~/.local/state/edge-rdd/pr-gate
#     RDD_GATE_LOG           $RDD_GATE_STATE_DIR/gate.log
#     RDD_GATE_MERGE_METHOD  squash   (squash|merge|rebase)
#     RDD_GATE_REASK_HOURS   24       (re-post an unchanged ask after this)
#     RDD_GATE_MAX_BUTTONS   6        (per project message; rest listed as text)
#     RDD_GATE_PATH_PREPEND  prepended to PATH (gh under systemd-spawned shells)
#
# SAFETY RAILS
#   - trunk (RDD_MAIN_BRANCH) is never merged from, deleted, or pruned
#   - merge requires: PR open, not draft, zero failing AND zero pending checks
#   - prune requires: branch is not trunk and not the head of any open PR
#   - action ids are single-use; unknown/consumed ids are refused with the
#     current pending list
#   - every gh call has a hard timeout; state writes are flock-serialized
#
# Usage: edge-pr-gate.sh sweep [--dry-run] | act <id> | pending [label] | status

set -uo pipefail

# gh/python3 often live outside a systemd-spawned PATH (gateway exec). Prepend
# RDD_GATE_PATH_PREPEND, falling back to the default project config's
# RDD_PATH_PREPEND — the dispatch wrapper's own mechanism for the same problem.
GATE_CFG_DIR="${RDD_GATE_CONFIG_DIR:-$HOME/.config/edge-rdd}"
if [ -z "${RDD_GATE_PATH_PREPEND:-}" ] && [ -f "$GATE_CFG_DIR/config.env" ]; then
  RDD_GATE_PATH_PREPEND="$(sed -n 's/^RDD_PATH_PREPEND=//p' "$GATE_CFG_DIR/config.env" | tail -1 | tr -d '"'"'"'')"
fi
[ -n "${RDD_GATE_PATH_PREPEND:-}" ] && export PATH="$RDD_GATE_PATH_PREPEND:$PATH"

command -v gh >/dev/null 2>&1 || { echo "edge-pr-gate: gh CLI not found in PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "edge-pr-gate: python3 not found" >&2; exit 2; }

exec python3 - "$@" <<'PY'
import fcntl, hashlib, json, os, re, secrets, shlex, subprocess, sys, time
from pathlib import Path

HOME = Path.home()
CFG_DIR = Path(os.environ.get("RDD_GATE_CONFIG_DIR", HOME / ".config/edge-rdd"))
STATE_DIR = Path(os.environ.get("RDD_GATE_STATE_DIR", HOME / ".local/state/edge-rdd/pr-gate"))
LOG_FILE = Path(os.environ.get("RDD_GATE_LOG", STATE_DIR / "gate.log"))
MERGE_METHOD = os.environ.get("RDD_GATE_MERGE_METHOD", "squash")
REASK_HOURS = float(os.environ.get("RDD_GATE_REASK_HOURS", "24"))
MAX_BUTTONS = int(os.environ.get("RDD_GATE_MAX_BUTTONS", "6"))
STATE_FILE = STATE_DIR / "state.json"

STATE_DIR.mkdir(parents=True, exist_ok=True)
os.chmod(STATE_DIR, 0o700)


def log(msg):
    with open(LOG_FILE, "a") as f:
        f.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {msg}\n")


def run(cmd, cwd=None, timeout=30):
    """Run a command, return (rc, stdout, stderr). Never raises."""
    try:
        p = subprocess.run(cmd, cwd=cwd, timeout=timeout,
                           capture_output=True, text=True)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s: {' '.join(map(str, cmd))}"
    except Exception as e:  # missing binary etc.
        return 127, "", str(e)


def gh_json(args, timeout=30):
    rc, out, err = run(["gh"] + args, timeout=timeout)
    if rc != 0 or not out:
        return None, err or f"gh {' '.join(args)} rc={rc}"
    try:
        return json.loads(out), None
    except json.JSONDecodeError as e:
        return None, f"bad json from gh: {e}"


# ---- project configs (the wrapper's own env files — single registry) --------

def parse_env_file(path):
    d = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def projects():
    out = []
    for f in sorted(CFG_DIR.glob("*.env")):
        env = parse_env_file(f)
        repo_dir = env.get("RDD_REPO_DIR")
        if not repo_dir:
            continue
        out.append({
            "cfg": str(f),
            "label": Path(repo_dir).name,
            "repo_dir": repo_dir,
            "trunk": env.get("RDD_MAIN_BRANCH", "main"),
            "channel": env.get("RDD_TG_CHANNEL", "telegram"),
            "target": env.get("RDD_TG_TARGET", ""),
            "thread": env.get("RDD_TG_THREAD", ""),
            "openclaw": env.get("RDD_OPENCLAW", str(HOME / ".local/bin/openclaw")),
        })
    return out


# ---- state -------------------------------------------------------------------

def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except json.JSONDecodeError:
            log("WARN state.json corrupt — starting fresh (old file kept as .bad)")
            STATE_FILE.rename(STATE_FILE.with_suffix(".json.bad"))
    return {"actions": {}, "posts": {}}


def save_state(state):
    tmp = STATE_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=1))
    tmp.replace(STATE_FILE)


class Locked:
    def __enter__(self):
        self.fd = open(STATE_DIR / "gate.lock", "w")
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        self.fd.close()


# ---- chat delivery -------------------------------------------------------------

def send_message(proj, text, buttons=None, dry=False):
    """buttons: list of (label, callback_value). Returns True on success."""
    if not proj["target"]:
        log(f"NOTE {proj['label']}: no RDD_TG_TARGET — message not sent")
        return False
    cmd = [proj["openclaw"], "message", "send",
           "--channel", proj["channel"], "--target", proj["target"],
           "--message", text]
    if proj["thread"]:
        cmd += ["--thread-id", proj["thread"]]
    if buttons:
        blocks = [{"type": "buttons",
                   "buttons": [{"label": lab,
                                "action": {"type": "callback", "value": val}}]}
                  for lab, val in buttons]
        cmd += ["--presentation", json.dumps({"blocks": blocks})]
    if dry:
        print(f"  DRY-RUN send -> {proj['channel']}:{proj['target']}"
              f"{':' + proj['thread'] if proj['thread'] else ''}")
        print("  " + text.replace("\n", "\n  "))
        for lab, val in (buttons or []):
            print(f"    [button] {lab}  ->  {val}")
        return True
    rc, out, err = run(cmd, timeout=30)
    if rc != 0:
        log(f"SEND FAIL {proj['label']} rc={rc} {err[:200]}")
        return False
    return True


# ---- repo facts ------------------------------------------------------------------

def repo_slug(proj):
    rc, out, err = run(["gh", "repo", "view", "--json", "nameWithOwner",
                        "--jq", ".nameWithOwner"], cwd=proj["repo_dir"], timeout=25)
    return (out, None) if rc == 0 and out else (None, err or "no slug")


def pr_checks_verdict(slug, number):
    """green | red | pending | no-ci"""
    rc, out, err = run(["gh", "pr", "checks", str(number), "-R", slug,
                        "--json", "bucket"], timeout=30)
    if not out:
        return "no-ci"
    try:
        buckets = [c.get("bucket") for c in json.loads(out)]
    except json.JSONDecodeError:
        return "no-ci"
    if not buckets:
        return "no-ci"
    if any(b == "fail" for b in buckets):
        return "red"
    if any(b == "pending" for b in buckets):
        return "pending"
    return "green"


def gather(proj):
    """Return (facts dict, error string or None)."""
    if not Path(proj["repo_dir"], ".git").is_dir():
        return None, f"repo dir {proj['repo_dir']} is not a git repo — skipped"
    slug, err = repo_slug(proj)
    if not slug:
        return None, f"cannot resolve GitHub repo ({err}) — skipped"

    prs, err = gh_json(["pr", "list", "-R", slug, "--state", "open", "--json",
                        "number,title,headRefName,isDraft,url"], timeout=30)
    if prs is None:
        return None, f"gh pr list failed ({err}) — skipped"
    for pr in prs:
        pr["verdict"] = pr_checks_verdict(slug, pr["number"])

    rc, out, err = run(["gh", "api", f"repos/{slug}/branches?per_page=100",
                        "--paginate", "--jq", ".[].name"], timeout=40)
    if rc != 0:
        return None, f"branch list failed ({err[:120]}) — skipped"
    branches = [b for b in out.splitlines() if b]
    open_heads = {pr["headRefName"] for pr in prs}

    stale = []  # (branch, reason)
    for br in branches:
        if br == proj["trunk"] or br in open_heads:
            continue
        assoc, _ = gh_json(["pr", "list", "-R", slug, "--head", br,
                            "--state", "all", "--json", "state"], timeout=25)
        states = {p["state"] for p in (assoc or [])}
        if "MERGED" in states:
            stale.append((br, "PR merged"))
            continue
        if "CLOSED" in states:
            stale.append((br, "PR closed unmerged"))
            continue
        rc, ahead, _ = run(["gh", "api",
                            f"repos/{slug}/compare/{proj['trunk']}...{br}",
                            "--jq", ".ahead_by"], timeout=25)
        if rc == 0 and ahead == "0":
            stale.append((br, "no unique commits"))
        else:
            n = ahead if rc == 0 else "?"
            stale.append((br, f"NO PR, {n} unmerged commit(s) — deleting discards them"))
    return {"slug": slug, "prs": prs, "branches": branches, "stale": stale}, None


# ---- sweep --------------------------------------------------------------------

def desired_actions(proj, facts):
    """key -> action template. Only things an operator can approve."""
    out = {}
    for pr in facts["prs"]:
        if pr["isDraft"] or pr["verdict"] not in ("green", "no-ci"):
            continue
        key = f"merge:{pr['number']}"
        note = "" if pr["verdict"] == "green" else " (repo has no CI checks)"
        out[key] = {
            "kind": "merge", "pr": pr["number"], "branch": pr["headRefName"],
            "title": pr["title"][:60], "url": pr["url"],
            "desc": f"merge PR #{pr['number']} “{pr['title'][:48]}” into "
                    f"{proj['trunk']}{note}, then delete {pr['headRefName']}",
            "button": f"✅ Merge PR #{pr['number']}: {pr['title'][:28]}",
        }
    for br, reason in facts["stale"]:
        key = f"prune:{br}"
        warn = "⚠️ " if "unmerged commit" in reason else "\U0001f9f9 "
        out[key] = {
            "kind": "prune", "branch": br, "reason": reason,
            "desc": f"delete branch {br} ({reason})",
            "button": f"{warn}Delete {br[:34]} ({reason[:24]})",
        }
    return out


def sweep(dry=False):
    now = time.time()
    all_clean = True
    with Locked():
        state = load_state()
        for proj in projects():
            label = proj["label"]
            print(f"project {label} (cfg {Path(proj['cfg']).name}, trunk {proj['trunk']})")
            facts, err = gather(proj)
            if err:
                print(f"  !! {err}")
                all_clean = False
                continue

            # info lines
            red = [p for p in facts["prs"] if p["verdict"] == "red"]
            pend = [p for p in facts["prs"] if p["verdict"] == "pending"]
            drafts = [p for p in facts["prs"] if p["isDraft"]]
            print(f"  repo {facts['slug']}: {len(facts['branches'])} branch(es), "
                  f"{len(facts['prs'])} open PR(s)")
            for p in red:
                print(f"  ❌ PR #{p['number']} CI RED — {p['title'][:60]} {p['url']}")
            for p in pend:
                print(f"  ⏳ PR #{p['number']} CI pending — {p['title'][:60]}")
            for p in drafts:
                print(f"  \U0001f4dd PR #{p['number']} draft — {p['title'][:60]}")

            desired = desired_actions(proj, facts)

            # reconcile pending actions for this project
            existing = {a["key"]: (aid, a) for aid, a in state["actions"].items()
                        if a["label"] == label and a["status"] == "pending"}
            for key, (aid, a) in existing.items():
                if key not in desired:
                    a["status"] = "superseded"
                    a["result"] = "repo state changed before approval"
            actions = []  # (id, action)
            for key, tpl in desired.items():
                if key in existing and existing[key][1]["status"] == "pending":
                    actions.append((existing[key][0], existing[key][1]))
                    continue
                aid = secrets.token_hex(6)
                a = {"key": key, "label": label, "cfg": proj["cfg"],
                     "repo": facts["slug"], "trunk": proj["trunk"],
                     "status": "pending", "created": now, **tpl}
                state["actions"][aid] = a
                actions.append((aid, a))

            if not actions:
                if red or pend:
                    all_clean = False
                    print("  no approvals needed (red/pending PRs ride the coder loop)")
                else:
                    print("  clean ✓ (trunk-only or only active PR work)")
                state["posts"].setdefault(label, {})["fingerprint"] = ""
                continue

            all_clean = False
            fp = hashlib.sha1(json.dumps(sorted(desired.keys())).encode()).hexdigest()
            post = state["posts"].get(label, {})
            fresh = post.get("fingerprint") != fp
            aged = now - post.get("ts", 0) >= REASK_HOURS * 3600
            snoozed = now < post.get("snoozed_until", 0)
            for aid, a in actions:
                print(f"  pending eg:{aid}  {a['desc']}")
            if snoozed and not fresh:
                print(f"  (snoozed until {time.strftime('%H:%M', time.localtime(post['snoozed_until']))} — not re-posting)")
                continue
            if not (fresh or aged):
                h = (now - post.get("ts", now)) / 3600
                print(f"  (asked {h:.1f}h ago, unchanged — not re-posting; re-ask after {REASK_HOURS:.0f}h)")
                continue

            lines = [f"\U0001f6a6 {label} needs your call — {facts['slug']} (trunk {proj['trunk']})"]
            for p in red:
                lines.append(f"❌ PR #{p['number']} CI RED: {p['title'][:50]}")
            for p in pend:
                lines.append(f"⏳ PR #{p['number']} CI pending: {p['title'][:50]}")
            lines.append("Tap to approve — I execute and confirm. "
                         "(Or reply “approve” / react \U0001f44d to approve a single pending item.)")
            buttons = [(a["button"], f"eg:{aid}") for aid, a in actions[:MAX_BUTTONS]]
            overflow = actions[MAX_BUTTONS:]
            if overflow:
                lines.append(f"+{len(overflow)} more pending — say “pending” to list them.")
            for sid, sa in state["actions"].items():
                if sa["label"] == label and sa["kind"] == "snooze" and sa["status"] == "pending":
                    sa["status"] = "superseded"
                    sa["result"] = "newer gate ask posted"
            snooze_id = secrets.token_hex(6)
            state["actions"][snooze_id] = {
                "key": f"snooze:{int(now)}", "label": label, "cfg": proj["cfg"],
                "repo": facts["slug"], "trunk": proj["trunk"], "kind": "snooze",
                "desc": f"snooze {label} gate asks for {REASK_HOURS:.0f}h",
                "button": "⏸ Not now (snooze 24h)",
                "status": "pending", "created": now,
            }
            buttons.append(("⏸ Not now (snooze 24h)", f"eg:{snooze_id}"))
            ok = send_message(proj, "\n".join(lines), buttons, dry=dry)
            if ok and not dry:
                state["posts"][label] = {"fingerprint": fp, "ts": now,
                                         "snoozed_until": post.get("snoozed_until", 0)}
                print(f"  posted approval message ({len(buttons)} buttons) to "
                      f"{proj['channel']} thread {proj['thread'] or '-'}")
                log(f"POSTED {label} {len(actions)} action(s) fp={fp[:8]}")
        if not dry:
            save_state(state)
    if all_clean:
        print("ALL_CLEAN")


# ---- act ------------------------------------------------------------------------

def find_proj(action):
    for p in projects():
        if p["cfg"] == action["cfg"] or p["label"] == action["label"]:
            return p
    return None


def act(aid):
    aid = aid.strip().removeprefix("eg:")
    with Locked():
        state = load_state()
        a = state["actions"].get(aid)
        if not a:
            print(f"FAILED unknown action id '{aid}'. Current pending:")
            _pending(state)
            sys.exit(4)
        if a["status"] != "pending":
            print(f"REFUSED action eg:{aid} is already {a['status']}"
                  f" ({a.get('result', '')}) — actions are single-use.")
            sys.exit(4)
        proj = find_proj(a)
        if not proj:
            print(f"FAILED project config for {a['label']} no longer exists")
            sys.exit(4)

        outcome, ok = execute(a, proj)
        a["status"] = "done" if ok else "failed"
        a["result"] = outcome
        a["acted"] = time.time()
        if a["kind"] == "snooze" and ok:
            state["posts"].setdefault(a["label"], {})["snoozed_until"] = \
                time.time() + REASK_HOURS * 3600
        save_state(state)
    log(f"ACT eg:{aid} {a['kind']} {a['label']} -> {a['status']}: {outcome[:160]}")
    prefix = "DONE" if ok else "FAILED"
    print(f"{prefix} {outcome}")
    if a["kind"] != "snooze":
        icon = "✅" if ok else "❌"
        send_message(proj, f"{icon} gate: {outcome}")
    sys.exit(0 if ok else 5)


def execute(a, proj):
    slug, trunk = a["repo"], a["trunk"]
    if a["kind"] == "snooze":
        return f"{a['label']}: gate asks snoozed for {REASK_HOURS:.0f}h", True

    if a["kind"] == "merge":
        pr, err = gh_json(["pr", "view", str(a["pr"]), "-R", slug, "--json",
                           "state,isDraft,headRefName,title,url"], timeout=25)
        if pr is None:
            return f"could not re-verify PR #{a['pr']} ({err})", False
        if pr["state"] != "OPEN" or pr["isDraft"]:
            return f"PR #{a['pr']} is {pr['state']}{' (draft)' if pr['isDraft'] else ''} — not merging", False
        verdict = pr_checks_verdict(slug, a["pr"])
        if verdict not in ("green", "no-ci"):
            return f"PR #{a['pr']} checks are {verdict} now (were green at ask time) — not merging", False
        rc, out, err = run(["gh", "pr", "merge", str(a["pr"]), "-R", slug,
                            f"--{MERGE_METHOD}", "--delete-branch"],
                           cwd=proj["repo_dir"], timeout=60)
        if rc != 0:
            return f"merge of PR #{a['pr']} failed: {(err or out)[:200]}", False
        sync_local(proj)
        return (f"{a['label']}: merged PR #{a['pr']} “{pr['title'][:48]}” into "
                f"{trunk} ({MERGE_METHOD}) and deleted {pr['headRefName']} — {pr['url']}"), True

    if a["kind"] == "prune":
        br = a["branch"]
        if br == trunk:
            return f"refusing to delete trunk {trunk}", False
        heads, _ = gh_json(["pr", "list", "-R", slug, "--head", br,
                            "--state", "open", "--json", "number"], timeout=25)
        if heads:
            return f"branch {br} is now head of open PR #{heads[0]['number']} — not deleting", False
        rc, out, err = run(["gh", "api", "-X", "DELETE",
                            f"repos/{slug}/git/refs/heads/{br}"], timeout=25)
        if rc != 0:
            return f"delete of {br} failed: {(err or out)[:200]}", False
        sync_local(proj)
        return f"{a['label']}: deleted stale branch {br} ({a.get('reason', '')})", True

    return f"unknown action kind {a['kind']}", False


def sync_local(proj):
    """Best-effort: keep the coder's clone converged on the fresh trunk."""
    d = proj["repo_dir"]
    run(["git", "-C", d, "fetch", "--prune", "origin"], timeout=40)
    rc, cur, _ = run(["git", "-C", d, "rev-parse", "--abbrev-ref", "HEAD"], timeout=10)
    rc2, dirty, _ = run(["git", "-C", d, "status", "--porcelain"], timeout=10)
    if rc == 0 and cur == proj["trunk"] and rc2 == 0 and not dirty:
        run(["git", "-C", d, "pull", "--ff-only"], timeout=40)


# ---- pending / status ---------------------------------------------------------------

def _pending(state, label=None):
    rows = [(aid, a) for aid, a in state["actions"].items()
            if a["status"] == "pending" and a["kind"] != "snooze"
            and (label is None or a["label"].lower() == label.lower())]
    if not rows:
        print("no pending actions" + (f" for {label}" if label else ""))
        return
    for aid, a in sorted(rows, key=lambda r: r[1]["created"]):
        age = (time.time() - a["created"]) / 3600
        print(f"PENDING eg:{aid}  [{a['label']}] {a['desc']}  ({age:.1f}h old)")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__ or "usage: edge-pr-gate.sh sweep [--dry-run] | act <id> | pending [label] | status")
        sys.exit(2)
    mode, rest = args[0], args[1:]
    if mode == "sweep":
        sweep(dry="--dry-run" in rest or os.environ.get("EDGE_GATE_DRYRUN") == "1")
    elif mode == "act":
        if not rest:
            print("usage: edge-pr-gate.sh act <id>")
            sys.exit(2)
        act(rest[0])
    elif mode == "pending":
        _pending(load_state(), rest[0] if rest else None)
    elif mode == "status":
        state = load_state()
        _pending(state)
        done = [(aid, a) for aid, a in state["actions"].items()
                if a["status"] in ("done", "failed")]
        for aid, a in sorted(done, key=lambda r: r[1].get("acted", 0))[-8:]:
            print(f"{a['status'].upper()} eg:{aid}  [{a['label']}] {a.get('result', '')[:100]}")
    else:
        print(f"unknown mode '{mode}' — sweep | act <id> | pending [label] | status")
        sys.exit(2)


main()
PY
