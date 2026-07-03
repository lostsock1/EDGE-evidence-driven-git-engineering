# Project State

> The single always-current snapshot coding agents read FIRST. Keep it short,
> truthful, and updated with every landed change. A stale PROJECT_STATE.md is
> a bug — file a work order to fix it.

## Current status

<!-- 3-6 bullets: what phase the project is in, what works today, what is in
     flight, the last landed PR. Date every claim. -->

- YYYY-MM-DD — project initialized from the EDGE-RDD template.

## Active source-of-truth docs

| Doc | Purpose |
|---|---|
| `PROJECT_STATE.md` | this snapshot |
| `TASKS.md` | work orders and milestone ladder |
| `QUALITY_GATES.md` | invariants + frozen decision rules |
| `KNOWLEDGE_STAGING.md` | research → repo pipeline and status ladder |
| `RESEARCH_TRANSFER.md` | promoted, implementation-changing findings |
| `EDGE_COLLABORATION.md` | two-way research/implementation channel |

## Product goal

<!-- One paragraph: what is being built and for whom. -->

## Built foundation

<!-- Per subsystem: what exists and is trusted. -->

## Active gap

<!-- What is missing between the foundation and the current milestone. -->

## Current constraints

<!-- Hardware, budget, model freeze, deployment tier, compliance — anything a
     coding agent must not violate. -->

## Risk register

<!-- Known risks with one-line mitigation each. -->

## Stop conditions for coding agents

Coding agents STOP and file a research-request (see `EDGE_COLLABORATION.md`) instead of improvising when:

- a promoted item conflicts with an active doc
- the task requires an architecture/stack/model decision
- a gate in `QUALITY_GATES.md` cannot be satisfied without changing the gate
- the fix implies rewriting a subsystem not named in the work order

## Update protocol

Update this file in the same PR as the change it describes. Newest facts on top of each section; prune anything no longer true rather than appending contradictions.
