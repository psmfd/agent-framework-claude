# ADR-062: AGENTS.md is the canonical source for the agent catalog

**Status:** Accepted
**Date:** 2026-06-01

## Context and Problem Statement

The agent catalog is duplicated across five surfaces: `AGENTS.md` (Agent | Tier | Domain | Use when), `rules/agent-first-selection.md` and its Copilot mirror (Agent | Domain | Use when), `README.md` Current Agents (Agent | Model | Tier | Description), and the `web/instructions.md` Skill Catalog (condensed Agent | Domain | Use when). `validate.sh` checked only agent-name presence across these, not the prose cells — so Domain/Use-when edits silently desynced (live drift existed for `work-item-management-expert`, `code-review-expert`, `security-review-expert`, and `tauri-expert`). Tier, Domain, and Use-when are not present in agent wrapper frontmatter (only `name` and `model` are), so they cannot be regenerated from frontmatter as issue #188 originally assumed.

## Considered Options

* **Option A** — Regenerate only frontmatter-derived data (name set, README Model); leave curated columns unchecked. Closes almost none of the drift gap.
* **Option B** — Designate `AGENTS.md` as the canonical source for Tier/Domain/Use-when; a drift-check gate verifies the downstream catalogs against it, and a write mode regenerates the same-schema routing mirrors.
* **Option C** — Add `tier`/`domain`/`use_when` fields to wrapper frontmatter and regenerate everything from frontmatter. Blocked by the Copilot wrapper frontmatter allowlist and the platform-field-isolation rule.

## Decision Outcome

Chosen option: **Option B**, because it closes the actual drift gap (curated prose desync) without violating platform field isolation. `AGENTS.md` is canonical for Tier/Domain/Use-when. `scripts/regen-agent-catalog.sh --check` (wired into `validate.sh` as a blocking error gate) verifies, keyed by agent name: name presence vs `agents/*.md`; Domain + Use-when parity across `AGENTS.md` and both routing mirrors; README Tier vs `AGENTS.md`; README Model vs each wrapper's `model:` frontmatter. The script's `--write` mode regenerates only the same-schema routing mirrors (`rules/agent-first-selection.md` + its Copilot instruction mirror) from `AGENTS.md` via an order-preserving, merge-by-name rewrite.

The README **Description** column and the `web/instructions.md` Skill Catalog are intentionally divergent (README has its own prose; web is deliberately condensed) and are **not** regenerated; the web catalog remains covered by the existing web-sync drift check. Tier is **not** derivable from tools (read-only experts carry `Bash` for research) and stays curated in `AGENTS.md`. Efficacy columns (#167) must remain `AGENTS.md`-only and must never leak into the routing tables; the script extracts columns by header name (not position) so additive `AGENTS.md` columns do not corrupt extraction.

### Tradeoffs

* Good: the routing tables that drive orchestrator agent selection can no longer silently desync from `AGENTS.md`; drift is a CI error with a one-command fix (`--write`).
* Good: no frontmatter schema change, so Copilot wrapper parity and platform field isolation are preserved.
* Bad: `AGENTS.md` becomes a write-authority bottleneck — the routing-mirror Domain/Use-when cells must be edited in `AGENTS.md` and propagated via `--write`, not hand-edited downstream.
* Bad: the generator couples three files to one source and must round-trip markdown tables safely (pipe/whitespace/ordering); mitigated by an order-preserving merge and an idempotency test.

## More Information

* Issue #188 (re-spec'd after a design fan-out: ai-crossplatform-expert + shell-expert + code-review-expert).
* ADR-061 (`scripts/lib/` shared helpers the script sources).
* `#167` efficacy columns — kept firewalled to `AGENTS.md`.
