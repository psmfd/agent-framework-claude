# ADR-089: paths:-Scoping for Cleanly File-Triggered Rules

**Status:** Accepted
**Date:** 2026-07-03

## Context and Problem Statement

Rules without `paths:` frontmatter load unconditionally into every session and every non-Explore/Plan subagent spawn, and are re-injected after every compaction. The measured baseline (#27, 2026-07-03) is ~124 KB (~23k–31k estimated tokens) of always-loaded context across CLAUDE.md, AGENTS.md, and all 20 rules — roughly quadrupled per task under the mandatory 3-agent research fan-out. Most of that content is only conditionally relevant, but `paths:` scoping triggers solely on a matching file Read, so a naively scoped rule is silently absent on topic-triggered tasks — the exact sessions where some rules matter most.

## Considered Options

* **Option A** — Scope only rules whose relevance is reliably signaled by file reads AND whose miss blast-radius is bounded by a mechanical backstop or is style-only; keep everything else unconditional.
* **Option B** — Scope every rule with any plausible glob to maximize token savings.
* **Option C** — Status quo: keep all rules unconditional.

## Decision Outcome

Chosen option: **Option A**, because the #27 research established that the safe-to-scope test is not glob availability but the combination of a reliable file-read trigger and a bounded miss cost. Three rules pass that test and are scoped in this change:

| Rule | `paths:` globs | Why the miss cost is bounded |
| --- | --- | --- |
| `script-output-conventions.md` | `**/*.sh` | Style-only impact; `validate.sh check_lib_selftests` backstops `scripts/lib` conformance |
| `artifact-handoff.md` | `.review/**` | The never-merge contract is fully enforced by the `artifact-review-guard` required CI check |
| `pr-template-standard.md` | `**/PULL_REQUEST_TEMPLATE.md` | Process-quality only; PR-title format has its own CI backstop (`lint-pr-title`) |

Estimated saving is ~2,500 always-loaded tokens per context (~10k per fan-out task).

Rules that MUST NOT be `paths:`-scoped under this decision: the session-level orchestration and planning rules (`orchestrator-protocol`, `agent-first-selection`, `research-parallelism`, `consensus-by-replication`, `plan-before-code`, `file-issues-first`, `documentation-in-plan`, `post-implementation-review`), security policy with in-session relevance and no in-session backstop (`no-mcp-servers`), and every topic-triggered rule with no reliable file signal (`debian-baseline`, `github-flow`, `semver-tagging`, `conventional-commits`, `structured-review-format`). `secrets-guard` and `gh-identity-guard` are hook-backstopped and theoretically scopable, but are deliberately deferred: scoping them removes the agent's ability to explain guard blocks and choose the correct override, and the savings do not yet justify that regression. Topic-triggered rules are a skills-architecture question tracked separately (#51), not a `paths:` question.

### Tradeoffs

* Good: recovers ~2.5k tokens per context with zero policy-coverage loss on the scoped rules' enforced invariants.
* Good: establishes the backstop-over-glob decision lens for any future scoping proposal.
* Bad: the scoped rules' guidance is unavailable on tasks that discuss shell scripts, review artifacts, or PR templates without reading a matching file (e.g. pure advisory questions); the residual risk is style drift, not broken enforcement.
* Bad: whether a `paths:`-scoped rule re-triggers inside a subagent's own file reads is not explicitly documented; until verified (#52 provides the observability tooling), subagents may operate without the scoped rules even when reading matching files.

## More Information

* #27 — the research record (semantics verification, 20-rule classification, measured baseline)
* #50 — the adoption issue, including the before/after `/context` measurement protocol
* #51 — skills-based lazy loading for topic-triggered rules (revisits ADR-074/ADR-075)
* #52 — `InstructionsLoaded` observability logger
* ADR-074, ADR-075 — the monolithic/no-skill-layer architecture this decision deliberately does not reopen
