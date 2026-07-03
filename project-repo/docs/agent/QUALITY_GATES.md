# Quality Gates

> The invariants and measurement rules every change must honor. The reviewer
> fails PRs against this file; the coder checks it before writing code.

## Universal gates (every PR)

- CI green on all required checks; branch up to date with `{{MAIN_BRANCH}}`.
- No secrets in the diff (credential scan before push).
- Tests accompany behavior changes; the risky path has coverage.
- Errors are user-actionable, not raw tracebacks.
- Docs truthful: `PROJECT_STATE.md`/`TASKS.md` updated in the same PR.

## Project invariants

<!-- ADAPT: the non-negotiables of YOUR system, e.g.:
- authz enforced server-side at every layer a request crosses
- client never more privileged than the public API
- offline tier makes no non-loopback egress
- model/dependency freeze: swaps are research decisions, never coding findings
-->

## Frozen decision rules

For any performance or quality claim:

1. **Freeze the gate before measuring** — metric, dataset/fixture, threshold,
   and pass/fail condition are written into the work order first.
2. **Measure once, report honestly** — a failed gate is a recorded negative
   result, not a prompt to re-tune the threshold.
3. **Gate-design errors are findings** — if the gate measured the wrong thing,
   amend it through a new proposal in `RESEARCH_TRANSFER.md` and re-measure.

## Current thresholds

<!-- Table of live numeric gates: metric · threshold · fixture · frozen-on date. -->

## Evidence rule

A gate result without reproducible evidence (test name, eval report path, CI
run link) does not count as passed.
