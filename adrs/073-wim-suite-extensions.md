# ADR-073: WIM frozen-script suite extensions — title sanitization and standalone issues

**Status:** Accepted
**Date:** 2026-06-16

## Context and Problem Statement

The frozen work-item suite (`scripts/wim/`, ADR-050) is SHA-pinned and re-authored only through a deliberate PR + re-pin cycle. Two gaps surfaced in the v2.1.0 pre-promotion review that require re-authoring frozen files:

1. **Search-query injection (#177).** `gh_search_by_title` in `_lib.sh` embeds a manifest-supplied title directly into a `gh issue list --search` string, and `ado_search_by_title` relied on `wiql_escape` without a documented guarantee. A title carrying GitHub search operators (`OR`, `label:`, quotes) can broaden or narrow the server-side result set and corrupt the idempotency decision (reuse the wrong item or create a duplicate). Impact is idempotency drift, not RCE — both backends pass titles as parameterized arguments, not through a shell.
2. **No standalone issues (#178).** The manifest schema and driver enforce an Epic → Feature → Story hierarchy, and `create-epic.sh` unconditionally appends `type/epic`. The suite could not file a standalone issue with a different type (e.g. a `bug`), forcing a fallback to raw `gh issue create` that bypasses the frozen suite entirely.

Per ADR-050's re-author contract, both fixes must land with an atomic `.frozen-shas` re-pin, and any change to the suite must propagate to the `work-item-management-expert` SKILL.md and both wrappers.

## Considered Options

* **Option A** — Fix both in `_lib.sh`/driver/schema and re-pin, recording the decision in a new ADR that extends ADR-050. Bundle #177 + #178 in one PR to share a single re-pin cycle (`.frozen-shas` is one file; splitting risks an inconsistent intermediate state).
* **Option B** — Supersede ADR-050 with a replacement record. Rejected: ADR-050's freeze/SHA-pin convention remains fully load-bearing; superseding would wrongly imply it is obsolete and break its 10+ cross-references and the `validate.sh`/CONTRIBUTING doc-sync pair.
* **Option C** — For #178, add a `--type`/standalone mode flag to `create-epic.sh` rather than a new script. Rejected: an Epic is a distinct work-item type with a hardcoded `type/epic` label; overloading it breaks the create-`<type>`.sh naming coherence and forces re-pinning a more central script. A dedicated `create-issue.sh` adds one new `.frozen-shas` entry and leaves `create-epic.sh` untouched.

## Decision Outcome

Chosen option: **Option A**.

**#177 — sanitization.** `gh_search_by_title` derives a `safe_title` (stripping double-quotes, colons, and the bare boolean words `OR`/`AND`/`NOT`) used only in the `--search` pre-filter; the authoritative match remains the `jq` exact-title filter against the *original* title. `wiql_escape` gains a comment documenting that doubling single-quotes is the correct and sufficient WIQL escape (single-quote is the only structural character inside a WIQL string literal), and `ado_search_by_title` gains a defensive abort if an un-doubled quote survives escaping. The analysis found the issue overstated the ADO risk — the substantive gap was the GitHub `--search` site.

**#178 — standalone issues.** `manifest.schema.json` gains a top-level `issues: []` array of a new `standalone_issue` type, the root `required` relaxes to `["backend"]`, and a new frozen `scripts/wim/create-issue.sh` creates an issue with labels applied verbatim (no `type/*` injection) and an explicit ADO `--type` (default `Issue`). `apply-manifest.sh` dispatches the `issues[]` list after the epic tree, skips the epic block when absent, and requires at least one of `.epic` or a non-empty `.issues`.

**ADR-050 relationship.** This ADR **extends** ADR-050; it does not supersede it. ADR-050 keeps `Status: Accepted`; the SHA-pin enforcement and the agent-behavioral freeze constraint remain in force. `scripts/wim/.frozen-shas` is re-pinned atomically in the same commit (`_lib.sh` and `apply-manifest.sh` updated, `create-issue.sh` added). The suite now has **six** frozen scripts; the `work-item-management-expert` SKILL.md, both wrappers, and the README tree are updated accordingly.

### Tradeoffs

* Good: idempotency is robust against adversarial titles; standalone issues route through the frozen suite instead of bypassing it; ADR-050's freeze guarantee is preserved.
* Good: `create-issue.sh` as a new script keeps the existing create-`<type>`.sh scripts untouched (only their shared `.frozen-shas` file changes).
* Bad: the suite grows to six scripts and a richer schema — more surface to keep in doc-sync and re-pin on future changes (an expected ADR-050 cost).

## More Information

* Issues #177, #178; epic #266; part of #181. The standalone-shim cross-reference (#174) is a separate skill-doc change with no frozen-script impact.
* Extends [ADR-050](050-frozen-wim-scripts.md) (frozen-script SHA-pin convention) — not a supersession.
* `tests/wim/run-tests.sh` extended with adversarial-title and standalone-issue cases; `tests/wim/fixtures/bin/{gh,az}` shims updated (the `az` shim's single-quote round-trip bug was fixed as part of #177's test coverage).
