# ADR-074: Monolithic single-file agent pattern

**Status:** Accepted
**Date:** 2026-06-29

## Context and Problem Statement

This repository is the Claude-only successor to the cross-platform agent framework
(see [ADR-076](076-claude-only-successor-genesis.md)). The predecessor used a
three-file pattern ([ADR-004](004-three-file-pattern.md)): a shared `SKILL.md`
source of truth ([ADR-001](001-skills-first-architecture.md)), a Claude Code agent
wrapper, and a GitHub Copilot wrapper. That split existed primarily as a
cross-platform DRY device — one source generating two platform wrappers. With
Copilot removed, the `SKILL.md`/wrapper split is two files maintained in sync for
no remaining benefit: every expert is consumed exclusively as a **subagent** via
the orchestrator's fan-out ([ADR-013](013-agent-first-selection.md),
[ADR-016](016-research-parallelism.md)), never invoked directly as a main-context
skill. For a subagent, the agent file body *is* the system prompt; a separate
`SKILL.md` is vestigial.

## Considered Options

* **Monolithic single-file agent** — one `agents/<name>.md` per expert containing
  full expertise inline; no `skills/` directory, no wrapper.
* **Two-file pattern** — keep `SKILL.md` as source of truth plus a thin Claude
  wrapper (the three-file pattern minus the Copilot file).
* **Status quo (three-file)** — retain the Copilot wrapper. Rejected outright:
  this is a Claude-only framework.

## Decision Outcome

Chosen option: **Monolithic single-file agent**, because the expert content is only
ever loaded as a subagent system prompt, where a one-file agent is the native form.
It eliminates the SKILL↔wrapper sync burden, removes an entire `skills/` layer and
its validation machinery, and collapses the documentation-sync surface. The
framework's shape becomes cleanly three-layered: **rules** (always-loaded behavior)
→ **commands** (invocable orchestration entry points) → **agents** (monolithic
subagent experts).

This ADR also absorbs the frontmatter-schema concern formerly governed by
predecessor ADR-058 (not carried — see [ADR-076](076-claude-only-successor-genesis.md)):
platform-binding fields (`model`, `tools`, `effort`, `disable-model-invocation`) now live
directly in the agent file's frontmatter, since there is no `SKILL.md` to keep
platform-neutral. It supersedes [ADR-033](033-claude-wrapper-disable-model-invocation.md):
`disable-model-invocation: true` remains required on every agent, but the
justification is no longer the VS Code / Copilot dual-discovery collision — it is
that all delegation is orchestrator-controlled, so agents must not be
auto-invocable by the main model.

### Tradeoffs

* Good: one file per expert; no sync pairs; `skills/` and its `validate.sh` checks
  removed; simpler authoring and scaffolding; smaller doc-sync map.
* Good: the in-flight Kafka/MSK agents were already authored as monolithic files,
  so they become the template rather than an exception.
* Bad: loses the theoretical ability to invoke an expert as a main-context skill
  (progressive disclosure). Accepted — no expert is used that way; all delegation
  flows through the orchestrator protocol.
* Bad: large expertise bodies live in a single file rather than a referenced skill
  tree. Acceptable for the current agent sizes.

## More Information

Supersedes [ADR-001](001-skills-first-architecture.md),
[ADR-004](004-three-file-pattern.md), and
[ADR-033](033-claude-wrapper-disable-model-invocation.md). Absorbs the concern from
predecessor ADR-058 (not carried). Companion to
[ADR-075](075-rules-claude-native-single-file.md) (the analogous one-file
collapse for rules).
