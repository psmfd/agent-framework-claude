---
description: 'Prohibit MCP server references in all agent wrappers, skill files, and configuration'
---

# No MCP Servers

**Enforcement:** validate.sh check_agent (frontmatter `mcp-servers`/`mcpServers` key scan, #25); validate.sh check_no_mcp_prose (WARN heuristic for concrete package-name patterns in distributed prose, #37); validate.sh check_no_mcp_manifests (committed `.mcp.json` / `.claude-plugin/` plugin manifests; ADR-094)

This repo prohibits MCP server usage in all content it produces or distributes.

When creating or editing agent wrappers, skill files, or configuration:

- **Never add `mcp-servers`** to any frontmatter field in agent wrappers or skill files. The prohibition also covers plugin packaging: never bundle an MCP server manifest (`.mcp.json`) in a Claude Code plugin — plugin distribution does not change the policy. (The frontmatter scan is automated; the plugin-manifest check is `validate.sh check_no_mcp_manifests`.)
- **Never commit a project-level `.claude/settings.json`** (or `.claude/settings.local.json`) into a repo. That is the path Claude Code auto-loads as project configuration the moment a user opens the repo — the auto-execution-on-open vector behind CVE-2025-59536. This repo's own root-level `settings.json` is exempt and intentional: it is the distribution payload, never auto-loaded (Claude Code does not auto-discover a root `settings.json`), and it becomes active only when a user deliberately runs `setup.sh`, which symlinks it into user-level `~/.claude/settings.json`. The carve-out applies **only** to that root distribution file installed via `setup.sh` — it never licenses committing a file at the `.claude/settings.json` / `.claude/settings.local.json` path, and `.gitignore` ignores the `.claude/` path as an added friction layer (not a hard gate — `git add --force` can override it).
- **Never reference MCP server packages** (npm, PyPI, or otherwise) in skill content or instructions.
- All tool access must be controlled through explicit **`tools` allowlists** in agent wrapper frontmatter.
- If a user requests MCP server integration, explain this policy and suggest the `tools` allowlist approach instead.

This policy exists because runtime-loaded MCP servers are a supply-chain attack surface that the `tools` allowlist cannot constrain — the threat class captured by OWASP ASI04 (Agentic Supply Chain Vulnerabilities) and OWASP MCP04:2025 (Software Supply Chain Attacks). Both known Claude Code CVEs reinforce the related lesson that committed content must never carry runtime-loaded configuration: CVE-2025-59536 (pre-trust-dialog code execution from a repository-controlled `.claude/settings.json`, via project hooks and an MCP consent bypass; CVSS 8.7, fixed v1.0.111) and CVE-2026-21852 (API-key exfiltration via `ANTHROPIC_BASE_URL` redirection in the same file, with no MCP involvement; CVSS 5.3, fixed v2.0.65).

## Network-sourced context injection

This policy extends to **any runtime mechanism that injects external network content into the harness system context**, not just MCP servers as a protocol. The threat model is identical regardless of protocol: a runtime-loaded source whose content is treated as harness instructions creates a supply-chain injection vector with session-scope blast radius.

Specifically prohibited:

- **Hooks** (`UserPromptSubmit`, `PostToolUse`, or any other event) that fetch content from a remote URL and emit it as `systemMessage` or any other channel that the harness treats as system-role context.
- **Scripts** that read external HTTP responses and inject them into agent context without prior signing, allowlisting, or explicit user review.
- **Any mechanism** where a remote endpoint can dictate harness-level instructions for the session.
- **Hooks whose stdout or `additionalContext` enters context automatically** — a `SessionStart` command hook's stdout is auto-added as session context, and any hook event's `hookSpecificOutput.additionalContext` is injected where the hook fired. Either channel carrying runtime-fetched network content is prohibited, regardless of the emitting field's name.
- **Plugin background monitors** (`monitors/monitors.json`) whose output can deliver network-fetched content into the session — monitor stdout arrives as notifications with no visible tool call: the same threat mechanism as a fetch-hook, via different plumbing.

ADR-046 records the removal of one such mechanism (a `UserPromptSubmit` hook that injected external API content into the system context) and the rationale for treating it as policy-equivalent to MCP server injection.

Defense-in-depth alternatives that do NOT contradict this policy:

- Hooks that emit static content from local files (no network calls).
- Hooks that emit content the user explicitly approved out-of-band (e.g., signed snapshots verified against an allowlist of public keys).
- Tool-call style retrieval where the agent makes the request as a tool invocation (visible in the activity stream) and the result enters context as untrusted tool output, not system role.
