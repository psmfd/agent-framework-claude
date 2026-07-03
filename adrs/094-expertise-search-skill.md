# ADR-094: Reject Plugin Packaging for Expertise-API Retrieval; Adopt a Skill with a Bundled Helper Script

**Status:** Accepted
**Date:** 2026-07-03

## Context and Problem Statement

The Pi ecosystem consumes the agent-expertise-api through an extension whose
`expertise_search` tool surfaces results strictly as visible tool output; this
framework removed its own earlier integration because it injected fetched API
content into system context (ADR-046) and prohibits MCP servers outright
(ADR-002, `rules/no-mcp-servers.md`). Issue #47's research concluded parity is
achievable compliantly — the open design question (#63) was the vehicle:
Claude Code's plugin system, or the repo's existing symlink distribution. A
three-agent design fan-out (Claude Code surface mechanics, shell/token safety,
documentation structure) plus a requirement-fidelity review of the constraint
text informed this decision.

## Considered Options

* **Option A** — Claude Code plugin (manifest, marketplace or local install)
  packaging a skill + helper script.
* **Option B** — Skills-directory plugin (`.claude-plugin/plugin.json` dropped
  under `~/.claude/skills/`, no marketplace).
* **Option C** — MCP server wrapping the API — rejected by standing policy
  (ADR-002, `rules/no-mcp-servers.md`) and by the API's own ADR-007.
* **Option D** — Hook-based fetch injection (`SessionStart`/`UserPromptSubmit`
  stdout or `additionalContext`) — the exact mechanism ADR-046 removed.
* **Option E** — Skill folder (`skills/expertise/SKILL.md` + bundled
  `scripts/expertise-search.sh`) distributed via a new `skills` entry in
  `setup.sh`'s existing `~/.claude/` symlink model.
* **Option F** — Out-of-band signed snapshot sync to local files — the
  "future mechanism" direction ADR-046 named; deferred-viable, not needed for
  an on-demand read path.

## Decision Outcome

Chosen option: **Option E**, because it delivers full read-side parity with
the Pi extension inside the policy boundary at the smallest surface area:

1. **Tool-call-only trust shape.** The agent invokes the bundled script as an
   explicit, visible Bash tool call; the response enters context as untrusted
   tool output — the carve-out `rules/no-mcp-servers.md` explicitly blesses.
   Commands and skills are one unified Claude Code mechanism, but only a skill
   folder has first-party support for bundled files (`${CLAUDE_SKILL_DIR}`
   resolution), which Option E needs and single-file `commands/*.md` lacks.
2. **Plugin packaging (A/B) is rejected**, not deferred: it adds no capability
   the symlink model lacks for this ask, while inviting `hooks/hooks.json`,
   `.mcp.json`, and `monitors/monitors.json` as first-class sibling surfaces —
   the exact doors this repo's policy keeps closed. Plugin background
   monitors (stdout streamed into the session with no visible tool call) are
   policy-equivalent to fetch-hooks; the companion amendment to
   `rules/no-mcp-servers.md` names these surfaces explicitly.
3. **Read-only phase 1.** The skill and script perform GET-only retrieval
   (`/health/ready`, `/expertise/search/semantic`); a deployment issues only
   `expertise.read` (+ `expertise.agent` actor-class) scopes, making the
   consumer structurally incapable of writing regardless of client bugs (API
   ADR-003 four-scope split, amended by ADR-008). Any write path (draft
   submissions, `expertise.write.draft`) requires its own ADR first.
4. **Token hygiene.** The bearer token lives in `~/.config/expertise-search/config`
   (mode 600, user-provisioned out-of-band, never agent-written), is passed to
   curl via `-H @file` so it never appears in process argv, and every line
   expanding it runs with xtrace suppressed. The base URL is loopback-only,
   hard-refused otherwise, with no redirect following.

This does not conflict with ADR-074's "no separate skill layer": that decision
rejected per-agent expertise wrappers (skill files paired with agent
definitions); a self-contained workflow skill like `/expertise` is the same
class of surface as the existing `/review` command.

### Tradeoffs

* Good: parity with the Pi read path; no new policy carve-out; the new
  `skills/` surface is wired into `setup.sh`, `validate.sh` (symlink pair,
  shellcheck), and the bash-3.2 floor check like every other distributed dir.
* Bad: a new distribution surface (`skills/`) to keep in the Documentation
  Sync Map; the script's exit-code contract extends the base 0/1/2 convention.
* Accepted residual risks: (1) if the API ever echoed a credential into a
  response, it would enter the session transcript before any redaction — a
  structural property of the visible-tool-call model, mitigated server-side
  (API ADR-008 response hygiene) and by the skill's redaction constraints;
  (2) the secrets-guard pattern set has no bearer/JWT detector — tracked as
  #64.

## More Information

* #47 (research: go/no-go and shape), #63 (this design), #64 (secrets-guard
  bearer-token gap)
* ADR-046 (expertise injection removal), ADR-002 / `rules/no-mcp-servers.md`
  (policy this stays inside), ADR-074 (monolithic agent pattern, no per-agent
  skill layer)
* agent-expertise-api ADR-003 (four-scope split), ADR-007 (API-side MCP
  no-go), ADR-008 (response hygiene / actor class)
* Pi precedent: `pi_config` extension `expertise-client` (ADR-0028/0029/0067
  there) — loopback-only, API-key phase 1, tool-call-only surfacing
