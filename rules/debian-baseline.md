---
description: 'Use Debian 13 (Trixie) as the assumed Linux distribution for all server, VM, and container guidance'
---

# Debian Baseline

**Enforcement:** self-report only

All agent framework rules, guidance, and examples that reference Linux distributions assume **Debian 13 (Trixie)** as the baseline.

## When This Rule Applies

- Server and VM configuration guidance (package installation, service management, firewall rules)
- Ansible playbooks and roles targeting Linux hosts
- Docker base images for project-owned containers (unless a specific image is required by a dependency)
- Shell script examples that use distro-specific commands or paths

## When This Rule Does Not Apply

- macOS or Windows tooling — those platforms have their own conventions
- Container base images dictated by upstream dependencies (e.g., a vendor image based on Alpine)
- Distro-agnostic guidance that does not reference package managers, paths, or system behavior

## Debian Idioms

Use Debian conventions for all Linux examples:

- **Package management:** `apt` (not `yum`, `dnf`, or `apk`)
- **Init system:** `systemd` with `systemctl`
- **Firewall:** `nftables` (not `iptables` or `ufw`)
- **APT sources:** DEB822 format (`.sources` files in `/etc/apt/sources.list.d/`), not legacy one-line format

## Key Differences from Ubuntu 24.04

Agents providing Linux guidance should be aware of these Debian 13 behaviors that diverge from Ubuntu 24.04:

| Area | Debian 13 | Ubuntu 24.04 |
|---|---|---|
| SSH | `ssh.socket` activation on fresh installs; upgrades from Debian 12 keep the traditional `ssh.service` | `ssh.socket` activation by default (since 22.10); existing installs are migrated on upgrade |
| Firewall | `nftables` as default backend | `iptables` with `ufw` frontend |
| APT sources | DEB822 `.sources` format | Legacy one-line `/etc/apt/sources.list` |
| Cloud-init | Minimal default config, network-config v2 | Opinionated defaults, Netplan integration |
| Kernel | 6.x mainline | 6.x HWE, backport cadence differs |

The SSH row is the one baseline fact that is not stable across install paths, so automation must not hard-code which unit is active. Query the specific unit instead: a name-only `ansible.builtin.systemd_service` task (no `state`/`enabled`) returns the unit's state without making changes. `service_facts` cannot see `.socket` units (it lists `--type service` only) and is the wrong tool for this detection. Handlers must target the detected unit — restarting `ssh.service` alone does not pick up `Port`/`ListenAddress` changes under socket activation.

## Rationale

- Debian 13 is the current stable release and widely deployed in self-hosted and server contexts
- Package names and paths are predictable and well-documented
- Consistent with common ARM64 VPS deployments
- Avoids Ubuntu-ism creep in guidance that should follow upstream Debian conventions where possible
