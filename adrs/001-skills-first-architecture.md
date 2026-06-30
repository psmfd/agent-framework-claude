# ADR-001: Skills-first architecture with shared SKILL.md files

**Status:** Superseded by [ADR-074](074-monolithic-agent-pattern.md)
**Date:** 2026-03-24

## Context and Problem Statement

The user works with Claude Code personally while their team uses GitHub Copilot. Both platforms need the same domain expertise, but they have different agent formats and discovery mechanisms. Maintaining separate, fully independent agent bodies for each platform doubles the update cost and introduces drift as the catalog grows.

## Considered Options

* **Skills-first with shared SKILL.md** — domain knowledge lives once in a shared file; thin platform wrappers add tool restrictions and platform behavior
* **Duplicate bodies** — each platform gets its own complete agent body with no shared content
* **Claude-only** — author for Claude Code only, accept that Copilot users get nothing

## Decision Outcome

Chosen option: **Skills-first with shared SKILL.md**, because it eliminates content duplication while supporting both platforms natively. The agentskills.io SKILL.md format is discovered by both Claude Code (`~/.claude/skills/`) and VS Code Copilot (`agentSkillsLocations` setting), making it the natural shared layer.

### Tradeoffs

* Good: single source of truth for domain knowledge — update once, both platforms benefit
* Good: the shared layer is platform-neutral by design, enforced by validate.sh
* Bad: Copilot wrappers must inline key content from SKILL.md because Copilot has no `skills:` injection, creating a controlled form of duplication
* Bad: contributors must understand the three-file pattern and Copilot-first authoring order

## More Information

* [ADR-003](003-copilot-first-authoring.md) — Copilot-first authoring order
* [ADR-004](004-three-file-pattern.md) — three-file pattern
* [ADR-007](007-platform-field-isolation.md) — platform field isolation
* CONTRIBUTING.md Architecture section
