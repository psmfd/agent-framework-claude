# ADR-046: Remove Automated Expertise Injection Surface

**Status:** Accepted
**Date:** 2026-04-28

## Context and Problem Statement

The framework's expertise pipeline injected content from an external HTTP endpoint into the harness system context on every UserPromptSubmit, with no provenance, signing, or user review. The `hooks/the preflight injection hook.sh` script queried `${SERVICE_ENDPOINT}/expertise/search` and emitted the response as `{"systemMessage": ...}` — which both Claude Code and VS Code Copilot inject into the system role. This is structurally identical to the MCP-server threat the project rejects in `rules/no-mcp-servers.md` (OWASP ASI04, citing CVE-2025-59536 and CVE-2026-21852). A multi-hop write path (subagent → `candidate` block → curator → store → next session preflight) closed a self-poisoning loop with no human review at any stage. The default URL was hardcoded in both `settings.json` and the script, making the threat live by default for any user who ran `setup.sh`.

## Considered Options

* **Option A** — Remove the automated injection surface; design a safer expertise mechanism separately
* **Option B** — Disable-by-default opt-in (URL stripped, hook off until explicit user consent)
* **Option C** — Hook-side hardening (signing, URL allowlist, content schema validation, instruction-pattern blocklists)
* **Option D** — Local-only / read from local signed snapshot only; no network at hook time
* **Option E** — Status quo

## Decision Outcome

Chosen option: **A — Remove**, because it is the only option that fully eliminates the runtime supply-chain vector AND closes the multi-hop write path AND aligns with the project's existing `no-MCP-servers` policy. Option B leaves the architectural problem unchanged for opt-in users. Option C is defense-in-depth against an arms race; pattern-matching content filters cannot guarantee absence of effective injection. Option D removes remote compromise but requires a signing infrastructure the project does not yet have. Option E is the status quo and was rejected on first principles.

The expertise pipeline is removed in its entirety. A future, safer mechanism for sharing lessons-learned across sessions is being designed separately (signed local snapshots, signature verification, allowlisted public keys). When that design lands, the API database backup taken before this PR can be reviewed and re-fed into the new system. The `lookup` agent is removed in a follow-up issue (#212); its read-only nature is structurally distinct from the injection surface but has no remaining consumer after this change.

### Tradeoffs

* Good: Full elimination of the runtime supply-chain vector consistent with `rules/no-mcp-servers.md`
* Good: Closes the multi-hop subagent → curator → store → preflight self-poisoning loop
* Good: Removes maintenance burden of signing infrastructure, key management, and content schema enforcement
* Good: Reduces the framework's attack surface to the static file-based skills, rules, and agent wrappers only
* Bad: Loss of automated pre-flight context — the model must explicitly invoke a lookup tool when it wants prior knowledge (lookup agent removed in #212; future replacement TBD)
* Bad: Some users may have relied on the automated surfacing of stored expertise across sessions
* Bad: Existing expertise data backed up from the API DB cannot be auto-reintegrated; manual review and seeding into the new mechanism will be required

## More Information

Supersedes:

* ADR-009 — expertise read-write split (store still exists as backed-up data, but no automated read or write from this framework; the read/write split principle remains valid as a pattern for any future replacement)
* ADR-010 — the preflight injection hook hook (hook deleted)
* ADR-019 — surfacing (convention and shared skill deleted)
* ADR-024 — repo-local expertise queue (`.expertise/` directory deleted)
* ADR-043 — expertise-benchmark-methodology (benchmark scripts deleted)
* ADR-044 — benchmark-history-retention (moot without benchmarks)

Cross-references:

* `rules/no-mcp-servers.md` — extended in this PR to explicitly cover network-sourced `systemMessage` injection
* ADR-037 (Copilot Surface Parity) — context paragraph updated to use `stop-preflight-check.sh` as the canonical `UserPromptSubmit` example; capability matrix preserved (still accurate post-removal)
* Issue #210 — hotfix that disabled the surface in config (merged before this PR)
* Issue #212 — follow-up removal of the `lookup` agent

Threat model and platform constraints determined that mitigation could not be achieved at the platform layer: `UserPromptSubmit` `systemMessage` is treated as system-role on both Claude Code and VS Code Copilot, no platform mechanism exists for user review of injected content before consumption, and no platform-side signature verification is available for hook payloads. The decision was therefore architectural rather than configurational.
