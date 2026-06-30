# ADR-045: Per-Task Review Gate Within Multi-Task PRs

**Status:** Accepted
**Date:** 2026-04-27

## Context and Problem Statement

The existing post-implementation review rule (`rules/post-implementation-review.md`) fires once, before commit/PR open. When a PR delivers multiple work items (Story with several Tasks, or a feature with several discrete deliverables), the single PR-level gate produces two failure modes: (1) review work is batched and rushed at the end, increasing the chance that a defect introduced in task 1 is masked by churn from tasks 2-N; (2) work-item state transitions (ADO Task → Closed, GitHub Issue → Closed) are deferred to post-merge, breaking the standing instruction that work-item state must track delivery progress in real time. The convention also lacks an explicit coupling between review completion and ticket-state transitions, leaving "task done" ambiguous.

## Considered Options

* **Option A** — PR-level gate only (status quo) — one review pass before PR open, all task closures happen post-merge
* **Option B** — Task-level gate only — every task gets a full gate; no separate PR-level pass before merge
* **Option C** — Hybrid: per-task gate as primary checkpoint (run review + doc sync + close ticket before starting next task), plus a thin pre-PR aggregate pass

## Decision Outcome

Chosen option: **Option C**, because the per-task gate catches issues at the smallest reversible unit and keeps work-item state honest, while the pre-PR pass catches cross-task interactions (file conflicts, doc-sync pairs touched by multiple tasks, README aggregation) that can only be evaluated against the full diff. Option A leaves real-time work-item state and granular review on the table. Option B misses cross-task drift because no agent re-evaluates the merged diff as a whole.

### Tradeoffs

* Good: defects are caught at the smallest reversible unit, before subsequent task work obscures them
* Good: work-item state transitions track delivery in real time, satisfying the standing "update work item states as we go along" instruction
* Good: documentation sync is enforced per task, not deferred to a single end-of-PR sweep
* Good: a separate pre-PR pass still catches cross-task drift (e.g., two tasks both touching README that conflict)
* Bad: small overhead per task — each task carries a review checkpoint instead of one batched pass
* Bad: rule and PR template grow slightly more verbose to encode the two-tier gate

## More Information

* Updates `rules/post-implementation-review.md` and `copilot/instructions/post-implementation-review.instructions.md`
* Updates `.github/PULL_REQUEST_TEMPLATE.md` "All PRs" checklist with the per-task gate item
* Updates `CONTRIBUTING.md` "PR Review" section with a per-task gate subsection
* Builds on ADR-039 (documentation sync enforcement) — per-task gate is the runtime checkpoint that ensures sync pairs are updated alongside the change that necessitates them
