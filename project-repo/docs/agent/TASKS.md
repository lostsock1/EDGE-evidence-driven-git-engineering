# Tasks

> The work-order ledger. Coding agents act ONLY on items here (or in an ADR /
> `RESEARCH_TRANSFER.md` "Active transfers"). Chat is never a work order.

## Legend

- `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked (see note)
- IDs: `<milestone><letter>` (e.g. `M1a`) — stable, never reused.

## Rules for coding agents

1. A task is actionable only when it has: an ID, acceptance criteria, an
   out-of-scope list, and (for perf/quality claims) a **frozen decision rule**
   referencing `QUALITY_GATES.md`.
2. Work the smallest safe increment; one task per dispatch.
3. Land via `{{BRANCH_PREFIX}}/*` branch + PR to `{{MAIN_BRANCH}}`; a human merges.
4. On completion, tick the box **in the same PR** and update `PROJECT_STATE.md`.
5. Blocked? Mark `[!]`, file the research-request, and stop — do not improvise.

## Current milestone: M1 — <name>

<!-- EXAMPLE work order — copy this shape:

### M1a — Wire real ingestion path
- [ ] **Goal:** replace the fixture loader with the production ingestion call.
- **Acceptance:** end-to-end test uploads a real file and retrieves it; CI green.
- **Out of scope:** parser swaps, schema changes.
- **Expected file surface:** `src/ingest/*`, `tests/ingest/*`.
- **Decision rule:** n/a (functional).
-->

## Backlog

<!-- Promoted-but-not-yet-scheduled items, each linking its transfer record. -->

## Parked / blocked

<!-- `[!]` items with the blocking CM-id and date. -->

## Completed summary

<!-- One line per finished milestone — details live in git history. -->
