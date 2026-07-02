# ADR-084: Protocol determinism amendments and the Enforcement-line convention

**Status:** Accepted
**Date:** 2026-07-02

## Context and Problem Statement

A requirement-fidelity review of the orchestration protocol (issue #13) found it
well-specified on *what must happen* but under-specified on *how outcomes
reproduce*: the default divergence path claimed "deterministic aggregation" while
defining no synthesis algorithm; the two verdict taxonomies (`AGENT-VERDICT` vs.
the review `**Verdict:**` scale) interacted ambiguously in the replication
ladder's BLOCKED-drop step; N=3 with one drop sailed to "Unanimous" on a sample
of 2; the Variance Guard and Singleton-novel branches turned on subjective
phrases; no rule defined recovery for a crashed subagent or an unresolvable
`subagent_type`; and identical "protocol violation" language covered
hook-enforced and purely self-reported mandates, with no way for a reader to
tell which was which.

## Considered Options

* **Option A** — procedural amendments to the five rules + a repo-wide
  `Enforcement:` line + a canonical fan-out/aggregation table in
  `orchestrator-protocol.md` + a four-criteria single-fact-lookup exemption
* **Option B** — as A, but the aggregation table in a new `rules/` file, and the
  enforcement metadata in rule frontmatter
* **Option C** — soften the determinism claims instead of adding procedure
* **Option D** — status quo

## Decision Outcome

Chosen option: **Option A**.

* **Synthesis procedure (divergence):** a required per-agent claims table
  (agent / claim / verdict / basis; "unstated" is never invented) built before
  prose synthesis. Option C was rejected: the sibling replication shape proves a
  procedural algorithm is feasible; retreating from the claim would hide the
  gap, not close it.
* **Verdict taxonomy closure:** a new `UNABLE_TO_REVIEW` review verdict
  (genuinely-impossible-to-review only — size, complexity, uncertainty, and
  disagreement are explicitly not valid reasons) plus a fail-closed default:
  a review response with no `**Verdict:**` line is `NEEDS_CHANGES`, deliberately
  stricter than the research-agent `PARTIAL` default because an unverifiable
  review is not evidence a diff is safe. `commands/review.md` (the
  most-severe-wins consumer) was amended in the same change — the PR-#230-class
  parallel-artifact lesson.
* **Effective-N escalation:** the ladder now computes effective N after dropping
  `BLOCKED`/`UNABLE_TO_REVIEW`/missing-verdict responses and escalates when more
  than half of N dropped OR effective N < 3 (an OR, not an ELSE).
* **Objective ladder tests:** Variance Guard — verdicts match AND the executive
  summaries are information-equivalent (swappable without loss); Singleton
  novel — material means the concern changes the recommended action.
* **Failure recovery:** a crashed/empty-output subagent is aggregated as
  `BLOCKED`, recorded verbatim in the Efficacy Report, never silently dropped or
  backfilled; an unresolvable `subagent_type` falls back to a general-purpose
  agent carrying the identical brief plus a filed catalog-drift issue — for
  genuine absence only, never routing friction.
* **`Enforcement:` line:** every `rules/*.md` carries a single bold-label line
  immediately after its H1 naming the actual gating mechanism(s) from a closed
  vocabulary (`PreToolUse hook <name>` / `pre-commit hook <name>` /
  `pre-push hook <name>` / `validate.sh <check>` / `CI <workflow>.yml` /
  `GitHub Ruleset <name>` / `self-report only`, `;`-separated). Body placement
  beat frontmatter (Option B): no schema change, visible where agents read, and
  greppable (`^\*\*Enforcement:\*\*`) for the mechanical presence check tracked
  as #23. Named mechanisms beat a closed abstract enum because multi-layer rules
  (secrets-guard, gh-identity-guard) genuinely have several, and naming them is
  what makes the line actionable. `self-report only` documents reality without
  diminishing a rule's mandatory status; the audit itself surfaced #25
  (no-mcp-servers had no mechanical check).
* **Aggregation table home:** `orchestrator-protocol.md` (the existing unifier)
  rather than a new rule file — a new file would add an ADR, a README H3, and a
  web-mirror entry for a table that only cross-references existing rules.
* **Verified single-fact lookup exemption:** four conjunctive, objectively
  checkable criteria (single named source; zero synthesis with a
  would-three-agents-agree decision test; not itself a
  decision/recommendation; bounded blast radius excluding
  security/compliance/binding paths). Adversarially tested against every
  rationalization the protocol already prohibits — each fails at least one
  criterion on its face.

Mechanical enforcement is deliberately split out (#23 validate check, #24
SubagentStop verdict guard + PostToolBatch fan-out check) to keep this change
documentation-only.

### Tradeoffs

* Good: the protocol's aggregation paths become procedures instead of vibes;
  enforcement reality is visible per rule; the trivial-lookup gap closes without
  reopening the "this seems simple" loophole; mirrors (web distillate,
  AGENTS.md) were amended in the same change.
* Bad: the five rules grow (always-loaded token cost — partially offset later by
  the #14 AGENTS.md dedupe); the claims table adds a per-fan-out authoring step;
  "does the action change" remains an LLM judgment, the ceiling of objectivity
  achievable without similarity tooling.

## More Information

Issue #13 (this batch); #23/#24/#25 (mechanical follow-ups); ADR-063 (return
contract), ADR-083 (gate testing); `rules/orchestrator-protocol.md` Fan-Out
Shapes table.
