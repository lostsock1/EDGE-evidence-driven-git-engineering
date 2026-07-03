# Research Transfer

This file is the narrow bridge from EDGE research into the implementation branch. It is not a research notebook. It contains only findings that coding agents need in order to build the project correctly. Use `KNOWLEDGE_STAGING.md` for the full raw → extracted → candidate → proposed → accepted → tasked → verified/default pipeline.

For the reverse direction — coding agents asking EDGE for research or reporting that a proposal did not survive implementation reality — use `EDGE_COLLABORATION.md`.

## Promotion criteria

Promote an EDGE finding here only after it passes the staging rules in `KNOWLEDGE_STAGING.md` and changes one of these execution surfaces:

- architecture decision or ADR status
- phase gate, entry condition, exit condition, or stop condition
- implementation task or task ordering
- API contract or schema
- security, privacy, or audit requirement
- evaluation dataset, metric, threshold, or fixture
- dependency pin or runtime support policy
- deployment/packaging target
- explicit coding-agent instruction

Everything else stays in EDGE's private knowledge base.

## Transfer record template

```md
### YYYY-MM-DD — Short finding title

**Status:** proposed | accepted | rejected | superseded
**Source in EDGE:** path or session reference
**Impacted repo docs:** list active docs to update
**Coding-agent impact:** one paragraph describing what implementers must do differently
**Required doc updates:** checklist
**Required tests/evals:** checklist or `none`
**Stop/replan trigger:** what invalidates the finding
```

## Replacement proposal template

Use this stricter template when EDGE proposes replacing a current mechanism. A replacement proposal is not accepted until the stable contract, migration, gates, and rollback path are clear.

```md
### YYYY-MM-DD — Replace <slot>: <current> -> <candidate>

**Status:** proposed | accepted | rejected | superseded
**Replacement slot:** <name the subsystem slot>
**Source in EDGE:** path, experiment, watchlist item, or session reference

**Current baseline:** what the code/docs currently use
**Candidate replacement:** what EDGE recommends
**Why now:** failure, bottleneck, quality opportunity, security issue, or product requirement

**Stable contract that must not break:** APIs, schemas, security behavior, eval comparability, user-facing guarantees
**Implementation impact:** files/components likely affected and sequencing impact
**Migration/rollback:** how existing data/config/users recover or revert
**Required tests/evals/security gates:** exact checks needed before default-enabling
**ADR/doc updates required:** active docs and ADRs to update before coding
**Stop/replan trigger:** what evidence rejects or pauses the replacement
```

## Active transfers

None yet.
