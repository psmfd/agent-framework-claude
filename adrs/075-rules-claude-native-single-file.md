# ADR-075: Rules as Claude-native single files

**Status:** Accepted
**Date:** 2026-06-29

## Context and Problem Statement

In the cross-platform predecessor, every rule existed in three mirrored forms: the
canonical `rules/<name>.md`, a `copilot/instructions/<name>.instructions.md` mirror
consumed by Copilot, and a distilled section in `web/instructions.md` for Claude
web surfaces. The mirroring was enforced by a `validate.sh` `check_rules()` parity
gate. With Copilot removed, the instruction mirror has no consumer, and maintaining
a three-way mirror is pure overhead.

## Considered Options

* **Single-file rules** — `rules/<name>.md` is the sole authoritative form; no
  instruction mirror; `web/instructions.md` retained only as the Claude-web
  distillate.
* **Keep the instruction mirror** — preserve `copilot/instructions/` shape for a
  hypothetical future consumer. Rejected: no consumer exists and it violates the
  Claude-only mandate.

## Decision Outcome

Chosen option: **Single-file rules**. Each rule lives once in `rules/<name>.md`,
loaded natively into every Claude session. The `validate.sh` `check_rules()`
mirror-parity check is removed. `web/instructions.md` survives as the
Claude-web/Claude.ai consumption distillate (see
[ADR-048](048-claude-code-web-distillate.md)) — it is a Claude artifact, not a
Copilot one — with its Copilot-specific language stripped.

### Tradeoffs

* Good: one file per rule; no parity gate; smaller documentation-sync map.
* Bad: a future non-Claude consumer would need the mirror rebuilt. Accepted — the
  framework is Claude-only by charter ([ADR-076](076-claude-only-successor-genesis.md)).

## More Information

Companion to [ADR-074](074-monolithic-agent-pattern.md) (the analogous one-file
collapse for agents). Relates to [ADR-039](039-documentation-sync-enforcement.md)
(the doc-sync map this simplifies) and [ADR-048](048-claude-code-web-distillate.md)
(the retained web distillate).
