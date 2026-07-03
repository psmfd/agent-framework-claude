# ADR-090: PostToolBatch Fan-Out Advisory Nudge

**Status:** Proposed
**Date:** 2026-07-03

## Context and Problem Statement

`rules/research-parallelism.md`'s divergence minimum (3+ parallel agents on
Research tasks) is self-report only for `Agent` invocation counts and fan-out
composition — its Enforcement line names #44 as the tracked gap. ADR-088 (phase 1)
mechanically forced the return contract's *verdict line* via a `SubagentStop`
hook. This is phase 2: the fan-out-*count* half, via a `PostToolBatch` hook that
sees every tool call in a parallel batch. Three doc-verified mechanical facts
constrain the design and make it a materially different problem from phase 1:
(1) no task-classification field exists in the hook input — Research vs.
Implementation vs. Exempt is invisible to the hook; (2) the event fires once per
*batch*, not per turn or task — fan-out spread across turns is not aggregatable;
(3) it fires *after* the batch executed — a block cannot retroactively convert a
lone `Agent` call into a divergence fan-out.

## Considered Options

* **Option A** — Blocking counter: `decision: block` when a batch contains fewer
  than 3 `Agent`/`Task` calls.
* **Option B** — Advisory-only nudge: `hookSpecificOutput.additionalContext` on
  exit 0, uniformly fail-open, never blocks; signal is `Agent`/`Task` count plus
  distinct `subagent_type`, replication-disambiguated by prompt byte-identity;
  the Enforcement line retains an explicit self-report residue.
* **Option C** — Status quo: self-report plus the consumer-side synthesizer
  defaults only.

## Decision Outcome

Chosen option: **Option B**, because the three mechanical facts above make A
untenable and C leaves the visibility gap unaddressed:

1. **Advisory, never blocking.** With no classification field, per-batch-only
   visibility, and post-execution timing, a blocking posture false-positives the
   majority of legitimate batches (Implementation delegation, the Verified
   Single-Fact Lookup exemption, `consensus-by-replication` N-runs, the
   catalog-exhaustion carve-out, and cross-turn fan-out) while halting the
   agentic loop — and still cannot fix an under-fan-out after the fact. The hook
   **only ever exits 0**; the sole variable is whether `additionalContext` is
   populated. This extends ADR-088's fail-open precedent: 088 blocks on a
   *determinate* violation (an absent verdict line is a certain fact), but a
   fan-out counter cannot reach that certainty about a *policy* violation, so it
   never blocks.
2. **Presence signal, never substantive divergence.** The hook asserts diversity-
   signal *presence* — count and distinct `subagent_type` — and treats 3+
   same-`subagent_type` calls sharing byte-identical prompts as the legitimate
   replication shape, not a violation. It never asserts that 3 calls are 3
   *different angles*; cosmetically-diverse-but-substantively-identical prompts
   remain gameable and stay self-report. This is the direct analog of ADR-088's
   "enforce presence, never truthfulness."
3. **Honest scope, explicit self-report residue.** The hook's true capability is
   "nudge toward batching in groups of 3+ when batching is already happening" —
   it cannot enforce sequential/cross-turn fan-out or verify task classification.
   #44's rewrite of `research-parallelism.md`'s Enforcement line MUST retain an
   explicit self-report clause for task-classification accuracy, exemption
   validity, and substantive angle-divergence. An Enforcement line that reads as
   "PostToolBatch enforces the divergence minimum" is itself loophole text.
4. **Uniform fail-open.** jq absent, empty stdin, and malformed JSON all exit 0
   with no nudge; zero / under-3 / 3+ counts are determinate states, and only an
   under-3 count in a batch containing at least one `Agent`/`Task` call emits a
   nudge. Announced override `SKIP_FANOUT_NUDGE=1`. The tool-name matcher accepts
   **both** `Agent` and `Task` (renamed in v2.1.63, alias retained) — matching
   only one silently counts zero.

### Tradeoffs

* Good: closes the visibility half of the gap with zero false-positive-block
  risk; the simplest possible fail posture (always exit 0); zero-maintenance
  (no classification, no agent-catalog coupling); consistent with ADR-088.
* Bad: advisory-only is *notification, not forcing* — qualitatively weaker than
  phase 1; gameable by cosmetic diversity; blind to cross-turn/sequential
  fan-out; depends on the orchestrator heeding the nudge. Two facts need
  empirical confirmation before #44 writes code: the exact wire `tool_name`(s)
  and that `tool_input` exposes `subagent_type`. `additionalContext` as a JSON
  stdout payload is a new hook-output contract for this repo (all prior hooks are
  binary exit-0/exit-2), and `PostToolBatch` has no documented loop-guard, so a
  similarly-shaped batch can be re-nudged on a following turn.

## More Information

* #24 (parent), #44 (implementation — gated on this ADR), #46 (this design issue)
* ADR-088 (phase 1: SubagentStop verdict guard), ADR-084 (deferral record)
* `rules/research-parallelism.md`, `rules/consensus-by-replication.md`,
  `rules/orchestrator-protocol.md`
* Open items handed to #44: whether a persistent allowlist file is warranted
  (likely over-engineering for v1); whether to cross-check a self-declared
  classification token in the turn text to narrow false positives (may exceed
  reliable mechanical inference); empirical verification of the two facts above.
