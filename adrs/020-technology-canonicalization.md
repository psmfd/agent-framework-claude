# ADR-020: Canonical technology stack in standards/tooling.md

**Status:** Accepted
**Date:** 2026-03-25

## Context and Problem Statement

Agents make technology recommendations during implementation — which database, which framework, which CLI tool. Without a canonical reference, different agents (or different sessions) may recommend different technologies for the same purpose. This creates inconsistency across projects and unexpected tooling choices.

## Considered Options

* **Canonical standards file** — a single `standards/tooling.md` lists approved technologies by category; agents reference it when making recommendations; deviations require justification
* **Per-agent knowledge** — each skill embeds its own technology preferences in SKILL.md
* **No standard** — let agents use their training knowledge to recommend technologies

## Decision Outcome

Chosen option: **Canonical standards file**, because it provides a single authoritative reference that all agents consult. The file is organized by category (languages, databases, infrastructure, CI/CD, etc.) with brief rationale for each choice. Technologies not on the list are not prohibited but require deliberate justification.

### Tradeoffs

* Good: consistent technology recommendations across all agents and sessions
* Good: the rationale for each choice is documented alongside the choice itself
* Good: easy to update — one file change propagates to all agents
* Bad: the file must be maintained as technology choices evolve
* Bad: agents may not always consult the file unless directed by a rule or skill

## More Information

* `standards/tooling.md` — the canonical technology list
* CONTRIBUTING.md Technology Standards section (pointer to tooling.md)
* PR #25 — established the standards file
