# ADR-004: Atomic three-file pattern for every skill

**Status:** Superseded by [ADR-074](074-monolithic-agent-pattern.md)
**Date:** 2026-03-24

## Context and Problem Statement

A skill could exist as just a SKILL.md, or with one platform wrapper but not the other. This creates inconsistent states where domain knowledge exists but one platform cannot access it. Contributors might create a Claude wrapper and forget the Copilot wrapper (or vice versa), leaving a platform gap that is invisible until someone on that platform tries to use the skill.

## Considered Options

* **Atomic three-file requirement** — every skill must have all three files (SKILL.md + Claude wrapper + Copilot wrapper), enforced as a hard error in validate.sh
* **SKILL.md required, wrappers optional** — create wrappers as needed, warn on missing wrappers
* **No enforcement** — trust contributors to create all needed files

## Decision Outcome

Chosen option: **Atomic three-file requirement**, because it prevents partial states that leave one platform without access to a skill. The pre-push validation gate (validate.sh) catches missing files before they reach the repo.

### Tradeoffs

* Good: every committed skill is immediately usable on both platforms — no half-deployed skills
* Good: validate.sh catches omissions automatically, reducing review burden
* Bad: creating a new skill requires three files even if the author only uses one platform
* Bad: requires a `shared: true` escape hatch for library skills that are consumed by other agents, not invoked directly ([ADR-006](006-shared-skill-variant.md))

## More Information

* [ADR-001](001-skills-first-architecture.md) — skills-first architecture
* [ADR-006](006-shared-skill-variant.md) — shared skill variant
* [ADR-015](015-validation-pre-push-gate.md) — validation as pre-push gate
* CONTRIBUTING.md Three-File Pattern section
