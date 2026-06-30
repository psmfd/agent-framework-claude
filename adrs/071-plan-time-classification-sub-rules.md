# ADR-071: Plan-time classification sub-rules for follow-up scope and documentation impact

**Status:** Accepted
**Date:** 2026-06-16

## Context and Problem Statement

`plan-before-code.md` requires an approved plan before any code change, but it does not force two recurring kinds of surfaced scope to be captured at plan time: follow-up work that will not land in the current PR, and the documentation surfaces a change implies. Both routinely slip — follow-ups get mentioned in chat and lost, and doc-sync updates get discovered at PR-review time or caught late by `validate.sh`. The `post-implementation-review.md` per-task gate catches doc drift, but only after implementation, by which point the work is already framed as "the code change."

## Considered Options

* **Option A** — Do nothing; rely on `plan-before-code.md` plus the `post-implementation-review.md` per-task gate. Leaves both classes of scope to be caught late or not at all.
* **Option B** — Expand `plan-before-code.md` inline with issue-filing and doc-impact requirements. Overloads one rule and buries two distinct forcing functions in its body.
* **Option C** — Two new sibling sub-rules of `plan-before-code.md` — `file-issues-first.md` (issue-tracker axis) and `documentation-in-plan.md` (doc-sync axis) — each applying the same three-way classification (in-scope / out-of-scope-but-tracked / not-a-thing) at plan time, ported from a sibling repo and adapted to this repo.

## Decision Outcome

Chosen option: **Option C**, recorded as one ADR because the two rules are a single coherent design decision — front-load both axes to plan time using the same classification shape. `file-issues-first.md` requires follow-up scope to be filed as plan step 1 before any edit; `documentation-in-plan.md` requires the plan to enumerate and classify every documentation surface the change implies, including ADR-eligibility, before approval. Both reference `post-implementation-review.md`'s Documentation Sync Map as the single source of truth rather than restating it, and `plan-before-code.md` gains a back-reference to both (mirrored in its Copilot instruction).

The ports drop a sibling repo-specific material that does not apply here: the `artifact_review` / ADR-0006/0007 exemption is re-expressed as the `.review/` artifact-handoff channel (ADR-064); the `documentation-in-plan` worked example is rebuilt around a real agent-framework skill addition and its doc-sync pairs; foreign issue/PR references are removed; and the source rules' self-certified "exempt from adr-required under the pattern-following carve-out" preamble is dropped — that carve-out names only skills and agents, and `adr-required.md`'s "Adding a new development convention or rule" trigger governs new rules, so this ADR is the required record.

### Tradeoffs

* Good: surfaced follow-up scope and doc impact become explicit, classified plan artifacts the user approves, instead of late discoveries.
* Good: both rules reuse the existing Documentation Sync Map and compose with `post-implementation-review.md` (plan-time pre-flight + execution-time gate) with no duplicated matrix.
* Bad: more plan-time overhead on every multi-file task, and two more rules to keep mirrored across the rule and Copilot instruction.

## More Information

* Issues #196 (file-issues-first) and #197 (documentation-in-plan); Phase C of epic #181. Source: a sibling repo `agent/rules/file-issues-first.md` and `documentation-in-plan.md`, adapted to this repo.
* Sub-rules of [plan-before-code.md](../rules/plan-before-code.md); reference [post-implementation-review.md](../rules/post-implementation-review.md) (doc-sync map) and [artifact-handoff.md](../rules/artifact-handoff.md) (ADR-064).
* Not mirrored in the `web/instructions.md` distillate — neither rule is in the closed mirrored-rule set (the `post-implementation-review.md` enumeration).
* Design fan-out: docs-expert (rule prose, worked-example design), ai-crossplatform-expert (mirror parity, distillate scope), code-review-expert (requirement fidelity, ADR ruling, loophole audit).
