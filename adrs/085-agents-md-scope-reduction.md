# ADR-085: AGENTS.md scope reduction — pointers for content mirrored in rules/

**Status:** Accepted
**Date:** 2026-07-02

## Context and Problem Statement

`CLAUDE.md` imports `AGENTS.md` via `@AGENTS.md`, loading it at session start;
`rules/*.md` auto-loads independently via Claude Code's native rule discovery.
`AGENTS.md`'s Orchestrator Protocol, Development Conventions, and Security
Policies sections (14 subsections, ~94 lines) restated content already
canonical in 14 `rules/*.md` files — so that content entered every session's
fixed context twice. Per current first-party docs, every custom subagent spawn
also inherits the full CLAUDE.md import chain plus all unscoped rules, so with
the mandatory 3+-agent fan-out the duplication cost multiplies per task, not
per session. The restated copy had already drifted stale against its `rules/`
sources (missing the Fan-Out Shapes table and Sub-Agent Obligations added by
ADR-084), demonstrating the double-maintenance cost. The cross-platform mirror
rationale for a self-contained `AGENTS.md` ended with the Claude-only fork
(ADR-076).

The always-loaded agent catalog is also duplicated: `AGENTS.md`'s Available
Agents table (canonical, ADR-062) and `rules/agent-first-selection.md`'s
generated routing mirror both load every session.

## Considered Options

* **Option A** — status quo
* **Option B** — delete the restated sections outright, no pointers
* **Option C** — trim the restated sections to 1–3 line pointers naming the
  canonical `rules/<name>.md`; retire the generated catalog mirror in
  `rules/agent-first-selection.md` in favor of a pointer to `AGENTS.md`'s table
* **Option D** — delete `AGENTS.md` entirely, folding unique content into
  `CLAUDE.md`

## Decision Outcome

Chosen option: **Option C**.

* The 14 rule-restating subsections become short pointers (Research
  Parallelism and Agent Efficacy Reporting merge into one). Preserved
  unchanged: intro, Architecture, Common Commands, Working in This Repo,
  Available Agents, the ADR pointer, Documentation Standards (its target,
  `standards/documentation.md`, is not a rule and does not auto-load), and the
  Validation narrative (synced to `validate.sh` per the Documentation Sync
  Map). Net: ~227 → ~170 lines; roughly 1,700 tokens removed from every
  session and every subagent spawn. Option B was rejected because `AGENTS.md`
  is the cross-tool standard filename — a reader opening only it should still
  discover where each convention lives. Option D was rejected as a larger
  structural change than the problem warrants and contrary to keeping the
  standard entry-point file.
* **Catalog dedup:** `rules/agent-first-selection.md`'s generated table is
  replaced by a pointer to `AGENTS.md`'s Available Agents table, and
  `scripts/regen-agent-catalog.sh`'s mirror-regeneration/parity path
  (`write_routing`, `check_routing`) is removed. `AGENTS.md` remains the
  canonical source for Tier/Domain/Use-when — ADR-062's canonicality decision
  is unchanged; this amends only its mirror mechanism (the Tier column has no
  home in any alternative, making reversed canonicality strictly worse — see
  the #14 tooling analysis). The README Tier/Model check and bidirectional
  name-presence check remain.
* `CONTRIBUTING.md`'s Documentation Sync Map row for the restated sections is
  reworded to "pointer text only"; substantive changes propagate through the
  existing `rules/<name>.md` → `web/instructions.md` row.

### Tradeoffs

* Good: eliminates the drift-prone duplicate copies from the fixed context of
  every session and subagent spawn; future edits land only in the canonical
  rule; the observed staleness class disappears structurally.
* Bad: `AGENTS.md` alone is a thinner document for a non-Claude reader —
  mitigated by each pointer naming its exact target; a session without the
  rules symlinks installed (no `setup.sh`) sees only pointers, but that state
  is already unsupported.

## More Information

Issue #14; ADR-062 (catalog canonical source — mirror mechanism amended here),
ADR-074/075/076 (the sibling collapses this completes), ADR-084 (the drift
evidence); #27 (paths-scoping/lazy-loading follow-up), #28 (catalog gate test
coverage).
