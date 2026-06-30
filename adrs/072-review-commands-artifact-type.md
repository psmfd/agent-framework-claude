# ADR-072: Slash-command artifact type and named parallel-review commands

**Status:** Accepted
**Date:** 2026-06-16

## Context and Problem Statement

The framework defines the divergence fan-out (`research-parallelism.md`) and the review output contract (`structured-review-format.md`) but provides no named, codified way to invoke a multi-reviewer review. Every parallel review is assembled ad-hoc, so it is easy to skip the fan-out and run a single-reviewer pass instead. There is also no merged-output convention that attributes each finding to the reviewer that produced it. Separately, the repo has never distributed a Claude Code slash command, so there is no established artifact type or distribution path for one.

## Considered Options

* **Option A** — Do nothing; keep assembling review fan-outs ad-hoc and rely on `research-parallelism.md` being followed. Leaves the fan-out optional in practice and provides no reviewer attribution.
* **Option B** — Model the review workflow as a skill + agent wrappers (the three-file pattern). A skill/agent cannot be invoked as `/review`; it would be one more agent in the catalog, not a one-keystroke workflow, and would not solve the "fan-out actually fires" problem.
* **Option C** — Introduce a Claude Code `commands/` slash-command artifact type — `commands/review.md` (3-way: code + security + linter) and `commands/full-review.md` (4-way: + checkmarx, with a `cx` pre-flight and fallback) — plus a standalone Copilot `review-agent` wrapper, and add a conditional `Source` column to `structured-review-format.md`.

## Decision Outcome

Chosen option: **Option C**. Slash commands are Claude Code's native mechanism for codifying a repeatable workflow behind one invocation, which is exactly the "make the parallel review fire" requirement. The commands are distributed by symlinking a new top-level `commands/` directory into `~/.claude/commands/` via a `CLAUDE_LINKS` entry in `setup.sh`, and the symlink is registered in `validate.sh`'s `check_symlinks` pairs.

Because Copilot has no slash-command dispatch, the cross-platform counterpart is a deliberate asymmetry: a standalone `copilot/agents/review-agent.agent.md` wrapper (read-only `[read, search, agent]`, no backing `SKILL.md`) that performs the same 3-way fan-out. The 4-way checkmarx leg is Claude-Code-only because the existing `checkmarx-expert` Copilot wrapper is read-only (no `execute`); that pre-existing gap is tracked in #276, not closed here.

The `Source` column added to `structured-review-format.md` is **conditional** — required only when an orchestrator merges more than one reviewer into a single table, omitted for single-reviewer output. The canonical example table stays four-column so solo review agents (which inline that table) are unaffected. The change propagates to the Copilot instruction mirror and to `web/instructions.md` (structured-review-format is in the mirrored-rule distillate).

The commands are ported from a sibling repo `agent/prompts/review.md` and `full-review.md`, with all pi-specific concepts stripped: the `subagent` tool and its JSON `tasks` schema (replaced by native `Agent` invocations), the "Ground-Truth Source Precondition" / `PRECONDITION_FAILURE` return (replaced by the `BLOCKED` Return Contract), the mandatory `Source path:` field (softened to a context recommendation), the `8 tasks / 4 concurrent` cap, and the `agent/rules/` path prefix (repointed to `rules/`).

### Tradeoffs

* Good: a named, one-keystroke invocation makes the divergence review deterministic; reviewer attribution becomes a first-class output column.
* Good: distribution reuses the existing `setup.sh` symlink mechanism with a one-line addition.
* Bad: `validate.sh` has no gate for the new `commands/` artifact type or the `Current Commands` catalog, so they can drift silently — tracked as a follow-up in #275.
* Bad: the Claude/Copilot capability asymmetry (no slash dispatch, no 4-way cx on Copilot) is a permanent platform difference contributors must keep in mind.

## More Information

* Issues #194 (this work), #275 (validate.sh `check_commands` follow-up), #276 (checkmarx Copilot `execute` gap); Phase C of epic #181.
* Source: a sibling repo `agent/prompts/review.md` and `full-review.md`, adapted to this repo's native `Agent` fan-out and Return Contract.
* Touches [research-parallelism.md](../rules/research-parallelism.md) (divergence fan-out), [structured-review-format.md](../rules/structured-review-format.md) (Source column), and [consensus-by-replication.md](../rules/consensus-by-replication.md) (the aggregate verdict is most-severe-wins, not the replication ladder).
