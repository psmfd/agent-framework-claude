# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities **privately** via GitHub's
[private vulnerability reporting](https://github.com/psmfd/agent-framework-claude/security/advisories/new)
— the repository's **Security** tab → **Report a vulnerability**. Do **not** open
a public issue for a security report.

Reports are acknowledged on a best-effort basis (typically within a few days),
and a fix and coordinated-disclosure timeline are agreed with the reporter.

## Scope

This repository distributes Claude Code agent definitions, behavioral rules,
shell security hooks, and CI configuration — not a running service. Relevant
areas include:

- the security guard hooks under `hooks/` (secrets, identity, destructive-command guards),
- the GitHub Actions workflows under `.github/workflows/`,
- the per-agent tool allowlists and the execution-tool policy (`rules/agent-first-selection.md`, ADR-069).

The framework loads **no MCP servers** and ships **no runtime-loaded network
configuration** (see `rules/no-mcp-servers.md`), which removes a class of
supply-chain injection vectors by design.

## Supported Versions

The latest release on `main` is supported. This is an open-source project
maintained on a best-effort basis.
