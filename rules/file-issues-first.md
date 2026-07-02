---
description: Sub-rule of plan-before-code — when planning surfaces out-of-scope work, file it as an issue as plan step 1 before any code change
---

# File Issues First

**Enforcement:** self-report only

When forming an implementation plan, if a work item surfaces that should exist as an issue — in this repo or any other — **filing that issue is the first step executed in the plan**, before any code or configuration changes. This is a sub-rule of [plan-before-code.md](plan-before-code.md): it governs how plans capture follow-up scope that will not land in the current PR.

## When This Rule Applies

- Implementation tasks where planning identifies scope that will not land in the current PR.
- Research tasks whose recommendations include actionable follow-ups (upstream feature requests, ADR-drafting issues, deprecation issues).
- Cross-domain concerns a subagent surfaces and the orchestrator decides are real and out-of-scope.
- Bugs and tech debt observed in passing while working on something else.

## Classification

Every surfaced item gets exactly one classification at planning time:

| Classification | Action |
|---|---|
| **In-scope** | Do it now as part of the current task — a plan step, no issue needed. |
| **Out-of-scope but tracked** | File an issue as plan step 1 (or steps 1..N). Later plan steps reference the resulting issue numbers. |
| **Not-a-thing** | Explicitly drop with reasoning, recorded in the plan or Agent Efficacy Report so future readers see it was considered, not missed. |

The forcing function is the classification itself. Silently deferred scope — no issue, no rejection note — is a protocol violation.

## Mechanics

- Issue-filing happens **before** any edit, write, branch creation, or commit — it is plan step 1. Plan approval per [plan-before-code.md](plan-before-code.md) still gates execution: the plan presented for approval includes the filing steps with proposed titles, labels, and target repos.
- Cross-repo items use `gh issue create --repo <owner>/<repo>`; surface the resulting URL in the plan. Delegate `gh` specifics to `gh-cli-expert` per agent-first selection.
- Later plan steps, commit messages, and the PR body reference the filed issues as stable handles ("defer X to #NNN", "unblocks #MMM"). Back-link every issue filed under this rule from the current work — an issue filed but never referenced defeats the cross-linking rationale.
- File with enough body to act on later: the problem, the proposed direction, and links to the work that surfaced it. A bare title is a deferred archaeology assignment, not a tracked item.

## Exemptions

- **Micro-todos within the current PR's scope** — a small follow-up edit in the same commit is a plan step, not an issue. The bar is "will this leave the current PR open as work?"
- **`.review/` artifact-handoff findings** — review artifacts persisted to `.review/` per [artifact-handoff.md](artifact-handoff.md) (ADR-064) use the artifact channel, not the issue tracker. A finding that rises to its own work item still goes through this rule and gets filed.
- **Subagent observations the orchestrator judges not real** are the "Not-a-thing" branch above, not a separate exemption — document the rejection; do not file.
