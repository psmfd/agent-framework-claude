# ADR-021: Agent tiering taxonomy

**Status:** Accepted
**Date:** 2026-03-27
**Note:** The Domain Specialist tool-boundary clause (Bash as a tier-level default) is superseded by [ADR-069](069-execution-tool-allowlist.md). The tiering taxonomy itself stands.

## Context and Problem Statement

The repo has eight custom agents with implicit role distinctions — the `*-expert` suffix signals read-only advisory, `*-agent` signals executor capability, and the expertise pair forms a read/write split. But there is no formal taxonomy guiding when to build a new agent, what tool allowlists are appropriate for each role, or how roles compose. The README naming convention table captures two tiers; the codebase has four functional archetypes.

## Considered Options

* **Two-tier (naming convention only)** — keep the existing `*-expert` / `*-agent` split from the README; rely on naming to signal capability
* **Three-tier (issue #31 proposal)** — Orchestrator / Domain Specialist / Execution Provider, adapted from RepoFactory's architecture
* **Four-tier (observed reality)** — Domain Specialist / Execution Provider / Data Gateway / Orchestrator, reflecting the four functional archetypes that already exist in the codebase

## Decision Outcome

Chosen option: **Four-tier**, because the three-tier model forces the curator/lookup pair into either Specialist or Executor, neither of which captures their distinct characteristics — scoped store access, hook-guarded Bash, and a read/write split enforced by ADR-009. The four-tier model codifies what already exists without requiring agents to be reclassified.

### Tier Definitions

| Tier | Role | Tool boundary (Claude) | Tool boundary (Copilot) | Naming convention |
| --- | --- | --- | --- | --- |
| **Domain Specialist** | Read-only advisory — researches, explains, recommends | `Read, Glob, Grep, Bash, WebFetch, WebSearch` — no `Write`, `Edit`, or `Agent` | `read, search, web` — no `execute` or `edit` | `*-expert` |
| **Execution Provider** | Performs operations — may write files, delegate to subagents | Adds `Write`, `Edit`, and/or `Agent` as needed | Adds `execute`, `edit`, and/or `agent` as needed | `*-agent` or descriptive |
| **Data Gateway** | Read/write access to a specific data store — scoped operations only | `Bash` scoped via hooks or instructions; `Write` for queue files | `execute` for API calls; behavioral scoping only (no hooks) | Descriptive (no suffix convention) |
| **Orchestrator** | Routes requests, delegates to other agents, synthesizes results | `Agent` required; minimal direct tools | `agent` required; sequential only (no parallel fan-out) | TBD (none exist yet) |

### Current Agent Assignments

| Agent | Tier |
| --- | --- |
| `ai-crossplatform-expert` | Domain Specialist |
| `code-review-expert` | Domain Specialist |
| `docs-expert` | Domain Specialist |
| `gitflow-expert` | Domain Specialist |
| `shell-expert` | Domain Specialist |
| `gh-cli-expert` | Domain Specialist |
| `ansible-expert` | Domain Specialist |
| `docker-expert` | Domain Specialist |
| `helm-expert` | Domain Specialist |
| `dotnet-expert` | Domain Specialist |
| `kitty-agent` | Execution Provider |
| `linter` | Execution Provider |
| `lookup` | Data Gateway |
| `curator` | Data Gateway |

### Bash and Execute in Domain Specialists

All Domain Specialists include `Bash` in their Claude tool list despite being "read-only." This is intentional — `Bash` is needed for read-only operations like `git log`, `gh pr view`, and `curl -sf` health checks. The read-only constraint is enforced by body instructions ("never run destructive commands"), not by tool omission. On Copilot, the equivalent constraint is enforced structurally by omitting `execute`, with one exception: `gh-cli-expert` carries `execute` on Copilot because running `gh` commands is the agent's core function. The agent is behaviorally read-only (its instructions say "read-only by default — mutating operations require explicit user intent"), but it requires shell access to invoke `gh` on both platforms.

### Cross-Platform Enforcement Asymmetries

Claude Code enforces tier boundaries through `tools:` allowlists and `hooks:` guards. Copilot enforces only through `tools:` allowlists (coarser granularity) and body instructions. Specifically:

* Data Gateway hook guards (`curator-bash-guard.sh`) exist only on Claude — Copilot has no hook equivalent
* Copilot CLI silently blocks network I/O in subagent contexts, making Data Gateway agents non-functional as subagents on Copilot CLI
* Orchestrator parallel fan-out (multiple simultaneous Agent tool calls) is Claude-only — Copilot processes agent invocations sequentially

### When to Use Each Tier

* **Domain Specialist** — the agent's value is knowledge and judgment, not action. It answers questions, reviews designs, and recommends approaches. It never modifies files or external state.
* **Execution Provider** — the agent performs operations that change state: writing files, running linters with `--fix`, creating git branches. It may delegate to Domain Specialists for research.
* **Data Gateway** — the agent mediates access to a specific data store or API. Its Bash/execute access is scoped to that store's operations, not general-purpose. Read and write roles should be separated (per ADR-009).
* **Orchestrator** — the agent's primary function is routing and synthesis, not domain expertise. It delegates to other agents and combines their results. No orchestrator agents exist yet; this tier is reserved for future use if the catalog grows beyond ~12 agents (per issue #60).

### Tradeoffs

* Good: codifies four functional archetypes that already exist, preventing miscategorization
* Good: tool allowlist guidance per tier makes PR review of new agents faster
* Good: cross-platform enforcement asymmetries are documented, not discovered by surprise
* Bad: four tiers add cognitive overhead compared to the simpler two-tier naming convention
* Bad: tier enforcement is documentation-only — validate.sh does not cross-check tier against tool lists

## More Information

* Issue #31 — original proposal for agent tiering taxonomy
* ADR-009 — expertise read/write split (motivates the Data Gateway tier)
* ADR-011 — model selection strategy (Opus for quality-critical agents, Sonnet for lightweight)
* ADR-013 — agent-first selection routing
* Issue #59 — evaluate hook-based agent selection enforcement (deferred)
* Issue #60 — agent routing skill for catalog lookup (deferred until catalog >12)

## Amendments

**2026-04-03 — Copilot hook support correction:** Lines 26 and 56 state "no hooks" and "Copilot has no hook equivalent." As of April 2026, VS Code Copilot supports 8 hook events (`command` type only) including `PreToolUse` with `permissionDecision`. Copilot CLI also supports 8 hook events but with limited actionability — only `preToolUse` deny is actionable; all other event output is ignored (see ADR-037). The tier definitions and enforcement asymmetries remain valid, but the gap is narrower than originally documented — both Copilot surfaces can enforce Data Gateway hook guards via `preToolUse` deny, though with coarser granularity (no matcher support).
