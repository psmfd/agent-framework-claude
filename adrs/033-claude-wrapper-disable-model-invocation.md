# ADR-033: Require disable-model-invocation in all Claude agent wrappers

**Status:** Superseded by [ADR-074](074-monolithic-agent-pattern.md)
**Date:** 2026-04-06

## Context and Problem Statement

VS Code Copilot discovers agent files from both `~/.copilot/agents/` and `~/.claude/agents/` (documented in the ai-crossplatform-expert SKILL.md). This repo symlinks `agents/` to `~/.claude/agents/` and `copilot/agents/` to `~/.copilot/agents/` via `setup.sh`. When both directories contain a file for the same agent name, VS Code may resolve the Claude-format wrapper instead of the Copilot wrapper, loading wrong tool names, wrong descriptions, and producing broken agent behavior. The immediate symptom was observed in curator (#120): the Claude wrapper's description caused model self-restriction in the Copilot context, blocking all tool calls.

## Considered Options

* **Option A** — Add `disable-model-invocation: true` to all Claude wrappers in `agents/`
* **Option B** — Rename Claude wrapper files to use a different extension (e.g., `.claude.md`) to avoid discovery by name match
* **Option C** — Remove `agents/` from `~/.claude/agents/` symlink scope and use a separate Claude-only discovery path

## Decision Outcome

Chosen option: **Option A**, because `disable-model-invocation` is a documented Copilot frontmatter field designed for this case — it signals to VS Code that a file should not be auto-selected for model invocations. Claude Code ignores unrecognized frontmatter fields, making it a no-op on the Claude side. Options B and C require structural changes to the discovery path setup or file naming conventions, breaking existing Claude agents that reference wrappers by name.

### Tradeoffs

* Good: zero impact on Claude Code behavior — unrecognized frontmatter fields are silently ignored
* Good: uses the documented Copilot mechanism for this exact scenario — no workarounds needed
* Good: one-line addition per file, no architectural change required
* Bad: adds a Copilot-specific field to Claude wrapper files, creating a mild precedent for cross-platform field leakage
* Bad: requires the convention to be maintained for all future Claude wrappers — new wrappers that omit the field will re-expose the collision

## More Information

* Issue #120 — original curator non-functional bug report
* [ADR-012](012-symlink-distribution.md) — symlink-based distribution that creates the dual-discovery condition
* [ADR-007](007-platform-field-isolation.md) — platform field isolation policy (this ADR introduces a narrow exception)
