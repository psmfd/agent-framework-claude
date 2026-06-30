---
description: Sub-rule of plan-before-code — enumerate the documentation surfaces a change implies and classify each before any file modification
---

# Documentation in Plan

When forming an implementation plan, **the plan must enumerate every documentation surface the change implies and classify each one** before any code or configuration changes. This is a sub-rule of [plan-before-code.md](plan-before-code.md) and a sibling of [file-issues-first.md](file-issues-first.md) — the same plan-time, three-way classification applied to the doc-sync axis instead of the issue-tracker axis.

## When This Rule Applies

- Implementation tasks touching any surface in the Documentation Sync Map in [CONTRIBUTING.md](../CONTRIBUTING.md) (agents, rules, hooks, scripts, ADRs).
- Tasks that introduce, modify, or remove a convention, pattern, or architectural decision. ADR-eligibility is a plan-time classification under this rule, not a discovery during implementation.
- User-facing surfaces the change implies beyond the canonical map: README sections, AGENTS.md tables, `web/instructions.md` entries, cross-rule links.
- Research tasks whose recommendations imply a documentation change.

## Classification

For every documentation surface the change implies, the plan assigns exactly one:

| Classification | Action |
|---|---|
| **In-scope** | Updated in this task — an explicit plan step or doc-impact bullet in the plan presented for approval. |
| **Out-of-scope but tracked** | Filed as a follow-up issue at plan time per [file-issues-first.md](file-issues-first.md) (plan step 1), referenced by issue number. |
| **Not-a-thing** | Explicitly dropped with surface-specific reasoning, recorded in the plan or Agent Efficacy Report. |

The forcing function is the classification itself. A silently deferred surface — no plan step, no issue, no rejection note — is a protocol violation.

## What to Enumerate

The plan walks the Documentation Sync Map in [CONTRIBUTING.md](../CONTRIBUTING.md) and classifies each row the change touches. The map is the single source of truth — this rule references it rather than restating it, so adding a doc-sync pair is a one-line edit to the map and this rule keeps working unchanged.

Beyond the map, classify:

- **ADR-eligibility** — per [adr-required.md](adr-required.md). Either an ADR-drafting plan step (in-scope), an ADR follow-up issue (out-of-scope-but-tracked), or an explicit pattern-following / trivial classification (not-a-thing). The third path is the most common; the explicit classification is the discipline.
- **README impact** — the Current Agents/Rules lists, the directory tree (not auto-checked by `validate.sh`), and the architecture/workflow sections.
- **`web/instructions.md`** — the Agent Catalog and the mirrored-rule distillate, when the change touches an agent or a distilled rule.

## Mechanics

- The doc-impact analysis is part of the plan presented for approval per [plan-before-code.md](plan-before-code.md); the user approves the classifications when approving the plan.
- Where a surface is out-of-scope-but-tracked, the issue-filing is plan step 1 per [file-issues-first.md](file-issues-first.md). The two rules compose: file-issues-first says *file before code*; this rule says *classify before approval*.
- Present the doc-impact as a small table (surface | classification | reason) when more than two surfaces are affected, otherwise as a bulleted list.
- Record the doc-impact analysis in the PR body for traceability — a reader of the merged PR can verify every classified surface was touched, tracked, or explicitly rejected. The per-task gate in [post-implementation-review.md](post-implementation-review.md) remains the execution-time check that in-scope updates actually landed.

## Exemptions

- **Trivial single-line fixes or typo corrections** that touch no doc-sync pair.
- **Subagents executing a parent's already-approved plan** — the parent owned the doc-impact analysis.
- **`.review/` artifact-handoff findings** per [artifact-handoff.md](artifact-handoff.md) (ADR-064) — a finding that rises to a doc update enters this rule when the orchestrator turns it into a plan.
- **Documentation-only edits where the doc-impact is the entire change** — the plan states what changes and where, but no separate classification is required.

## Worked Example

Adding a new agent, `foobar-expert`, following the established monolithic single-file pattern. The plan's doc-impact section:

| Surface | Classification | Reason |
|---|---|---|
| `agents/foobar-expert.md` | in-scope | the agent itself (frontmatter + full expertise inline) |
| `README.md` Current Agents | in-scope | alphabetical agent table row |
| `AGENTS.md` agent catalog table | in-scope | row required; `validate.sh` enforces presence |
| `web/instructions.md` Agent Catalog | in-scope | mirror row; `validate.sh` checks on diff vs `origin/dev` |
| `rules/agent-first-selection.md` routing row | in-scope | routing table row required |
| `README.md` directory tree | in-scope | new file listed (not auto-checked — hand-verify) |
| ADR | not-a-thing | pattern-following addition; the monolithic single-file pattern is established by prior agents |

After the file is written, `validate.sh` is the per-task-gate check that every catalog row, section, and name-consistency requirement passes — closing the loop between this rule's plan-time enumeration and the gate's execution-time enforcement. Omitting any single surface from this list before starting is the failure mode the rule targets: a `validate.sh` failure discovered after the fact rather than a visible gap in the plan.
