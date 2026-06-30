# ADR-048: Claude Code Web / Claude.ai Distillate

**Status:** Accepted
**Date:** 2026-05-06

## Context and Problem Statement

Framework conventions, orchestrator protocol, security policies, and review gates live in `CLAUDE.md`, `AGENTS.md`, and the `rules/` directory. Claude Code (CLI, desktop, IDE) and GitHub Copilot (CLI, VS Code) auto-load these files via established discovery paths. Claude Code Web (`code.claude.com`, `claude.ai/code`) and Claude.ai chat sessions do not — those surfaces accept Project Instructions, Profile Instructions, or a single `CLAUDE.md` upload, with web-context character budgets that cannot accommodate a verbatim copy of every source file. The framework needs a curated single-file distillate, sized for web context and authored to capture the high-leverage subset of the local rules and conventions.

## Considered Options

* **Option A** — Hand-curated `web/instructions.md` as the canonical web-surface distillate. Manually updated when source files change; drift surfaces as a PR-review concern.
* **Option B** — Generate the distillate from `CLAUDE.md`, `AGENTS.md`, and `rules/*.md` via a script. Keep in sync via CI, with a lossy summarization step to fit the web context budget.
* **Option C** — Upload `AGENTS.md` verbatim to web surfaces and accept the surface's own truncation behavior.
* **Option D** — Don't support web surfaces. Direct users to the local CLI exclusively.

## Decision Outcome

Chosen option: **Option A**, because it ships immediately with zero new tooling, authorial ownership of the web copy is unambiguous, and a hand-curated distillate can be tighter and more context-aware than a mechanical generation. Option B requires a generation script with a lossy summarization step (the aggregate source is several thousand lines; the web context budget is much smaller) — feasible later if drift becomes painful, but premature today. Option C is wrong on principle — `AGENTS.md` contains references to local-only tooling (`validate.sh`, `hooks/`, file paths) that have no analog on the web; uploading verbatim ships dead instructions. Option D abandons users who actually use the web surfaces, including the project owner.

The distillate at `web/instructions.md` covers the orchestrator protocol, agent-first selection, research parallelism, plan-before-code, sub-agent obligations, agent efficacy reports, the skill catalog (as a routing reference), GitHub Flow, Conventional Commits, SemVer tagging, PR template standard, ADR-required, Debian baseline, post-implementation review, structured review format, documentation standards, no-MCP policy, secrets awareness, minimal tool lists, and script output conventions. A "Web Session Notes" section explicitly calls out the local mechanisms that have no harness-level equivalent on the web (`validate.sh`, `hooks/`) and explains how their intent is captured manually.

### Tradeoffs

* Good: zero new tooling; consistent with the framework's minimal-automation philosophy
* Good: file is sized for web context budgets and can omit local-only mechanisms cleanly
* Good: drift between source rules and the distillate is visible in PR diffs when both files are touched
* Good: web users get the same orchestrator discipline and security posture as local users
* Bad: manual sync — a rule or `AGENTS.md` change can ship without updating the distillate, and there is no automated guard yet
* Bad: no Documentation Sync Map entry exists for `web/instructions.md`; this should be added as a follow-up so reviewers know to check the pair
* Bad: `SKILL.md` files uploaded to Claude.ai are separate from those installed under `.claude/skills/` — users must manually maintain each surface's copy

## More Information

* PR — this change
* Follow-up issue (TBD) — add `web/instructions.md` to the Documentation Sync Map in `CONTRIBUTING.md` so reviewers explicitly check the pair on AGENTS.md or rules/ changes
* Follow-up issue (TBD) — consider a drift-detection check in `validate.sh` that warns when rule or AGENTS.md content changes without a corresponding `web/instructions.md` change in the same PR
* Related: [`rules/adr-required.md`](../rules/adr-required.md) — the rule that mandates this ADR
* Related: [`web/instructions.md`](../web/instructions.md) — the distillate itself
