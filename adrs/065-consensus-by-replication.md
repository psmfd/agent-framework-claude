# ADR-065: Consensus by replication as a second named fan-out shape

**Status:** Accepted
**Date:** 2026-06-02

## Context and Problem Statement

`research-parallelism.md` defines one fan-out shape: divergence — three or more *different* agents approaching a problem from *different* angles, explicitly excluding "the same agent invoked twice." That shape is right for exploration and synthesis, but it has no answer for tasks with a single best answer where the risk is that one agent run is a statistical outlier (design decisions, false-positive validation, binding judgements). For those, independent reasoning over *identical* inputs — running the same agent N times — is the appropriate shape, and the framework had no rule for it.

## Considered Options

* **Option A** — Do nothing; treat all fan-out as divergence. Leaves no convergence shape and contradicts the "same agent twice doesn't count" clause for anyone who tries replication.
* **Option B** — Extend `research-parallelism.md` with a replication mode inline. Overloads one rule with two distinct shapes and muddies its divergence-only invariant.
* **Option C** — A separate `consensus-by-replication.md` rule (the convergence shape) that cross-links research-parallelism, with its own applicability test, aggregation ladder, and anti-patterns.

## Decision Outcome

Chosen option: **Option C**. A new `rules/consensus-by-replication.md` (plus Copilot mirror) defines replication as a distinct, composable fan-out shape: N identical-prompt invocations of the same agent, independent, aggregated by a ladder — unanimous → adopt; majority (strict, of non-`BLOCKED` returns) → adopt with documented dissent; even split → full-stop escalate to the user; singleton-novel → adopt the majority and append the novel point as a credited addendum (additive, never a veto). A binary decision test separates it from divergence (different prompts/angles → divergence; identical prompts seeking convergence → replication), and a cross-link in `research-parallelism.md` clarifies that its "same agent twice doesn't count" clause governs the divergence minimum only and does not prohibit replication.

Two correctness hardenings are baked into the rule. A **variance guard**: N identical prompts at low sampling variance can return near-identical answers, which is a single sample repeated, not consensus — such a run is treated as an N=1 signal and escalated, not reported as agreement. And **verdict integration** with the `research-parallelism` Return Contract: `BLOCKED` returns are dropped from the denominator (escalate if a majority are BLOCKED), `PARTIAL` is provisional, and replicated review agents ladder on the `structured-review-format` `**Verdict:**` line. The platform-specific `tasks:[]` syntax from the source (a sibling repo ADR-0004) is dropped for platform-neutral language (concurrent on Claude Code, sequential on Copilot, with the Copilot CLI network caveat). It is mirrored in the `web/instructions.md` distillate because web-session orchestrators need both shapes.

### Tradeoffs

* Good: gives the framework an explicit, misuse-resistant convergence shape with a deterministic aggregation ladder and a mandatory user-escalation on genuine ties.
* Good: keeps `research-parallelism.md` focused on divergence; the two rules cross-link instead of merging.
* Bad: replication costs N× tokens; the rule must (and does) cap default N and reserve the shape for high-stakes singular answers.
* Bad: another orchestration rule to keep mirrored across the rule, Copilot instruction, and web distillate.

## More Information

* Issue #195; Phase C of epic #181. Source: a sibling repo `consensus-by-replication.md` (its ADR-0004), tool-syntax stripped.
* Complements [ADR-016](016-research-parallelism.md) (divergence) and builds on [ADR-063](063-parallel-agent-return-contract.md) (the `AGENT-VERDICT` return contract the ladder consumes).
* Design fan-out: code-review-expert (ladder rigor, variance guard, loophole audit), docs-expert (rule prose), ai-crossplatform-expert (mirror parity, platform mechanics, distillate placement).
