# ADR-036: Standardize on Debian 13 as Linux baseline

**Status:** Accepted
**Date:** 2026-04-08

## Context and Problem Statement

Agent framework rules and guidance that reference Linux distributions or OS-level tooling have no standardized distro assumption. This causes ambiguity when rules reference package managers, paths, or system behavior — authors default to whatever distro they are most familiar with, leading to inconsistent guidance (Ubuntu `ufw` vs. Debian `nftables`, legacy APT format vs. DEB822).

## Considered Options

* **Option A** — Standardize on Debian 13 (Trixie) as the assumed baseline
* **Option B** — Standardize on Ubuntu 24.04 LTS as the assumed baseline
* **Option C** — Remain distro-agnostic, requiring all guidance to avoid distro-specific commands

## Decision Outcome

Chosen option: **Option A**, because Debian 13 is the current stable release, aligns with the project's existing VPS deployments (ARM64 VPS), and provides predictable package names and paths. Ubuntu 24.04 was considered but introduces Ubuntu-specific abstractions (Netplan, `ufw`, Snap) that diverge from upstream Debian. Distro-agnostic guidance (Option C) was rejected because it is impractical — server configuration inherently involves package managers, service managers, and firewall tools.

### Tradeoffs

* Good: consistent idioms across all Linux guidance, matches production deployment targets, avoids Ubuntu-ism creep
* Bad: contributors familiar with Ubuntu or RHEL must translate to Debian conventions, guidance may not apply directly to non-Debian hosts without adaptation

## More Information

- [Debian baseline rule](../rules/debian-baseline.md) — the convention itself
- [Tooling standards](../standards/tooling.md) — OS table updated to specify Debian 13
- #94 — tracking issue
