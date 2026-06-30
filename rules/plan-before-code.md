---
description: 'Require an approved implementation plan before any code changes are made'
---

# No Code Changes Without an Approved Plan

Before writing, editing, or deleting any code:

- **Create an implementation plan** and present it to the user for review.
- The plan must include: what files will be changed, what the changes are, and why.
- **Wait for explicit user approval** before making any code modifications.
- If the user requests changes to the plan, revise and re-present for approval.
- Trivial clarifications or questions do not require a plan — only actions that modify code.
- Reading, searching, and exploring code to inform the plan is always permitted without approval.
- **Sub-agent exception:** when a parent agent or orchestrator has already received plan approval and delegates implementation to a sub-agent, the sub-agent should proceed directly with implementation. Do not re-present the plan for approval — the parent's approval covers delegated work.

## Related Sub-Rules

Two sub-rules extend the plan-time discipline — each classifies surfaced scope (in-scope / out-of-scope-but-tracked / not-a-thing) before any file modification:

- [file-issues-first.md](file-issues-first.md) — follow-up scope that will not land in the current PR is filed as an issue as plan step 1.
- [documentation-in-plan.md](documentation-in-plan.md) — the plan enumerates and classifies every documentation surface the change implies, including ADR-eligibility.
