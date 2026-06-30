# ADR-002: Prohibit MCP servers in all distributed content

**Status:** Accepted
**Date:** 2026-03-25

## Context and Problem Statement

MCP (Model Context Protocol) servers extend agent capabilities at runtime by loading external packages. This repo distributes agent skills and configuration to multiple consumers across platforms. Any `mcp-servers` field committed here propagates that runtime dependency — and its attack surface — to every consuming environment.

## Considered Options

* **Prohibit MCP servers, use tools allowlists** — all tool access controlled via explicit `tools:` fields in agent wrapper frontmatter
* **Allow curated MCP servers** — maintain an approved list of vetted MCP server packages
* **No policy** — let individual skill authors decide whether to use MCP servers

## Decision Outcome

Chosen option: **Prohibit MCP servers, use tools allowlists**, because MCP servers loaded at runtime are the primary attack vector for OWASP ASI04 (Supply Chain Vulnerabilities) and both known Claude Code CVEs (CVE-2025-59536, CVE-2026-21852). The `tools:` allowlist approach provides equivalent capability control without runtime dependency loading.

### Tradeoffs

* Good: eliminates the supply chain attack surface entirely — no runtime package loading
* Good: `tools:` allowlists are statically analyzable and validated by validate.sh
* Bad: skills cannot leverage MCP-only capabilities (e.g., database connectors, custom API integrations)
* Bad: if a future MCP security model addresses the supply chain risk, this policy would need revisiting

## More Information

* OWASP AAIF ASI04 — Supply Chain Vulnerabilities
* CVE-2025-59536, CVE-2026-21852 — Claude Code MCP injection vulnerabilities
* `rules/no-mcp-servers.md` — the enforcing rule
* PR #18 — established the policy
