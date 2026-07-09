# Agent Framework — Project Conventions

This repository distributes shared AI agent rules and agent definitions for Claude Code. It uses a **monolithic agent architecture** (ADR-074): domain expertise lives directly in each agent file, with no separate skill layer or platform wrappers. (Self-contained workflow skills under `skills/` — e.g. `/expertise`, ADR-094 — are invocable commands with bundled helper files, not a per-agent expertise layer; they do not dilute ADR-074.)

## Architecture

Every agent follows the monolithic pattern:

- `agents/<name>.md` — full domain expertise inline (YAML frontmatter: `name`, `description`, `model`, `tools`, `disable-model-invocation: true`; body contains the expertise)

Rules are single-file (ADR-075):

- `rules/<name>.md` — Claude Code rule (always-loaded context)

See `CONTRIBUTING.md` for the full specification, frontmatter reference, and naming conventions.

This repo has no build or runtime — it is a distribution of Markdown agents/rules and shell tooling, symlinked into `~/.claude/`. "Testing" means running `validate.sh` and the bash test suites, not compiling code.

## Common Commands

```bash
# Full consistency check — run before every push (also enforced by the pre-push hook).
# Requires bash 4.0+; macOS system /bin/bash (3.2) exits 2 with a version error.
# Use a Homebrew bash: /opt/homebrew/bin/bash ./validate.sh
./validate.sh
VALIDATE_VERBOSE=1 ./validate.sh   # per-warning detail lines

# Bash test suites (plain-bash harnesses: exit 0 PASS, 1 FAIL)
tests/secrets-guard/run-tests.sh            # secrets-guard.sh staged-blob regression (ADR-059)
tests/session-secrets-guard/run-tests.sh    # session-secrets-guard.sh PreToolUse contract (ADR-053)
tests/gh-identity-guard/run-tests.sh        # gh-identity-guard.sh pre-push identity ladder (ADR-054)
tests/session-gh-identity-guard/run-tests.sh # session-gh-identity-guard.sh PreToolUse contract
tests/bash-destructive-guard/run-tests.sh   # bash-destructive-guard.sh command classifier
tests/subagent-verdict-guard/run-tests.sh   # subagent-verdict-guard.sh SubagentStop contract (ADR-088)
tests/fanout-nudge/run-tests.sh             # fanout-nudge.sh PostToolBatch advisory contract (ADR-090)
tests/instructions-loaded-log/run-tests.sh  # instructions-loaded-log.sh InstructionsLoaded logger (ADR-092)
tests/setup-claude-cli/run-tests.sh         # setup.sh setup_claude_cli() install section (ADR-093)
tests/expertise-search/run-tests.sh         # skills/expertise expertise-search.sh helper contract (ADR-094)
tests/validate/run-tests.sh                 # validate.sh clone-and-mutate regression (bash 4+)
tests/wim/run-tests.sh                      # end-to-end work-item scripts via CLI shims
tests/worktree-guard/run-tests.sh           # worktree-create.sh symlink containment (ADR-070)
tests/rulesets/run-tests.sh                 # scripts/rulesets.sh normalization + apply rails (ADR-086)

# Bash 3.2 floor check — runs the 3.2-targeted scripts under a real 3.2 binary
# (macOS /bin/bash); SKIPs on hosts without one. CI runs it on macOS (ADR-083).
scripts/check-bash32.sh

# Ruleset-as-code (ADR-086): live drift check / apply / seed for the committed
# branch-protection rulesets in rulesets/*.json
scripts/rulesets.sh --check

# Shared shell-lib self-tests (also gated by validate.sh)
scripts/lib/log.sh --self-test
scripts/lib/git.sh --self-test

# Scaffold a new agent or rule from templates/
scripts/scaffold.sh

# Lint changed shell/markdown/yaml — prefer the linter agent over raw tools
# (the @linter agent discovers files and runs shellcheck/markdownlint/yamllint)
shellcheck hooks/*.sh scripts/lib/*.sh
```

There is no single "run a single test" command — the bash harnesses run their full suite. To isolate a case, read the relevant `run-tests.sh` and invoke the underlying script directly.

## Working in This Repo

Things that span multiple files and are easy to get wrong:

- **Monolithic agent pattern.** An agent is a single file: `agents/<name>.md` with YAML frontmatter (`name`, `description`, `model`, `tools`, `disable-model-invocation: true`) followed by the full domain expertise inline. A rule is a single file: `rules/<name>.md`. See ADR-074 and ADR-075.
- **Catalog and doc-sync coupling.** Adding/removing an agent or rule also requires updating the README catalogs (Current Agents/Rules), the `AGENTS.md` agent table, and the `web/instructions.md` Agent Catalog. `validate.sh` enforces most of these and the README directory tree must be hand-checked when `hooks/`, `scripts/`, `templates/`, or `adrs/` change. The authoritative pair list is the Documentation Sync Map in `CONTRIBUTING.md`.
- **Bash version split.** `setup.sh` and `hooks/*.sh` must stay bash 3.2-safe (macOS system bash); `validate.sh` requires 4.0+. Don't introduce associative arrays or `${var^^}` into the 3.2 scripts.
- **Hooks may block your own commits/pushes.** The secrets guard and gh-identity guard fire in-session and at commit/push time. Legitimate blocks are overridden with `SKIP_SECRETS_GUARD=1` / `SKIP_GH_IDENTITY_GUARD=1` (one-shot) or the repo-root allowlist files — never with a silent `--no-verify` unless documented.
- **Decisions need ADRs.** Convention/pattern/architecture changes require a new ADR in `adrs/` (MADR minimal template). Supersede prior ADRs; never edit a superseded ADR's body.

## Available Agents

Custom agents encode domain expertise, known fragilities, and validated patterns that general-purpose agents lack. Before using a general-purpose agent for a domain-specific task, check this catalog for a matching custom agent. Fall back to general-purpose only when no custom agent covers the domain.

| Agent | Tier | Domain | Use when |
| --- | --- | --- | --- |
| `ansible-expert` | Domain Specialist | Ansible | Playbook authoring, variable precedence, collection architecture, privilege escalation, vault, CI/CD integration |
| `aws-expert` | Domain Specialist | AWS | IAM/IRSA/SCPs, S3, VPC, Route 53, EKS, ECS/Fargate, ECR, Elastic Beanstalk, MSK |
| `aws-msk-expert` | Domain Specialist | AWS MSK | Amazon MSK provisioned vs serverless, broker sizing/storage, auth modes (IAM/SASL-SCRAM/mTLS), MSK Connect, MSK Replicator, version management |
| `azure-devops-expert` | Domain Specialist | Azure DevOps | Azure Repos git operations, YAML and classic pipelines, work item management, REST API patterns |
| `azure-infra-expert` | Domain Specialist | Azure Infrastructure | Entra ID, Key Vault, Managed SignalR, Storage Accounts, Private Endpoints, Private Link, ExpressRoute, custom DNS, Log Analytics workspaces |
| `cilium-expert` | Domain Specialist | Cilium CNI | Install/upgrades, IPAM, tunnel vs native routing, kube-proxy replacement, CiliumNetworkPolicy/L7/FQDN, LB-IPAM/L2/BGP, ClusterMesh, Hubble, WireGuard/IPsec, Gateway API, Cilium-on-Talos |
| `code-review-expert` | Domain Specialist | Code review | Semantic review — logic errors, design quality, security concerns, requirement fidelity |
| `docker-expert` | Domain Specialist | Docker | Dockerfiles, BuildKit, rootless builds, multi-stage, multi-platform, Compose v2, security patterns |
| `docs-expert` | Domain Specialist | Documentation | Best practices, content style, curation, Mermaid diagrams for general display and Azure DevOps |
| `dotnet-expert` | Domain Specialist | .NET | .NET 10 LTS SDK, cross-platform builds, ASP.NET Core, worker services, DI, EF Core, testing, publishing, security |
| `gh-cli-expert` | Domain Specialist | GitHub CLI | Working with issues, PRs, releases, checks, repos via `gh` commands |
| `gitflow-expert` | Domain Specialist | Git workflows | Branching strategies, PR workflows, release processes, commit conventions |
| `grafana-expert` | Domain Specialist | Grafana | Provisioning as code, unified alerting, dashboard authoring, LGTM datasource/correlation config, auth and org model, security hardening, deployment patterns |
| `helm-expert` | Domain Specialist | Helm | Chart authoring, values merge semantics, hooks, template debugging, dependency management, release workflows |
| `hyperv-expert` | Domain Specialist | Hyper-V | Type-1 hypervisor, VM generations + VHDX, virtual switches, checkpoints, nested virtualization, WSL2 utility VM, WHPX, VBS/HVCI |
| `kafka-developer-expert` | Domain Specialist | Kafka development | Producer/consumer dev for Kafka 4.x, delivery semantics, idempotence/transactions, consumer groups/rebalance, partition design, client auth |
| `kafka-self-managed-expert` | Domain Specialist | Self-managed Kafka | Kafka 4.x on Kubernetes, Strimzi and first-party operators, KRaft, storage, HA, cluster admin, encryption/auth |
| `lgtm-backends-expert` | Domain Specialist | LGTM backends | Loki (LogQL, deployment modes, retention), Tempo (TraceQL, metrics-generator), Mimir (ingest, blocks storage, multi-tenancy), Alloy pipelines, S3/MinIO object storage, backend-side correlation |
| `linter` | Execution Provider | Code quality | Running shellcheck, markdownlint, yamllint, and other linters on changed files |
| `longhorn-expert` | Domain Specialist | Longhorn storage | Architecture and v1/v2 data engines, install prerequisites, StorageClass/volume management, RWX, snapshots vs backups and DR, node/disk ops and drain policies, upgrades, Longhorn-on-Talos |
| `proxmox-expert` | Domain Specialist | Proxmox VE | qm/pct/pvecm/pvesm CLI, KVM VM + LXC lifecycle, storage, bridged/VLAN networking, clustering/HA, vzdump/PBS backups, cloud-init, API tokens |
| `security-review-expert` | Domain Specialist | Security review | Semantic security review for C#/.NET, Python, TypeScript, T-SQL, Azure/AWS IAM and networking, Active Directory/LDAP. Backed by first-party documentation. |
| `shell-expert` | Domain Specialist | Shell scripting | Bash/Zsh/POSIX sh compatibility, idioms, security, cross-platform strategies |
| `talos-expert` | Domain Specialist | Talos Linux | talosctl / machine API, machine config, cluster bootstrap, Image Factory + system extensions, OS/k8s upgrades, KubeSpan, Omni |
| `tauri-expert` | Domain Specialist | Tauri | Tauri 2 desktop app authoring — tauri.conf.json schema, generate_context!() codegen, build vs bundle phases, capabilities v2, cross-platform packaging, sidecar/externalBin with Rust target triples, plugin ecosystem, frontend integration, CLI, and GitHub Actions CI |
| `terraform-expert` | Domain Specialist | Terraform / OpenTofu | HCL, providers, state and remote backends, modules, workspaces, plan/apply, drift, import, testing, CI/CD |
| `vcluster-expert` | Domain Specialist | vCluster | Virtual cluster lifecycle, vcluster.yaml configuration, resource syncing, networking, licensing, platform management |
| `work-item-management-expert` | Domain Specialist | Work item management | GitHub Issues / Projects v2 and Azure DevOps Boards — type selection, field schemas, label and tag conventions, REST and CLI formatting, cross-platform translation |
| `wsl2-expert` | Domain Specialist | WSL2 | wsl.exe CLI, distro export/import, wsl.conf + .wslconfig, systemd in WSL2, NAT vs mirrored networking, interop |

## Architecture Decision Records

Significant decisions are recorded in `adrs/` using the MADR minimal format. See `CONTRIBUTING.md` for when and how to create ADRs. Current ADRs cover: monolithic agent pattern (ADR-074), no-MCP policy (ADR-002), release automation (ADR-042), and all development conventions below. ADR-046 records the removal of the automated expertise injection surface. The prior cross-platform ADRs were superseded when this repo forked to Claude-only (ADR-076).

## Orchestrator Protocol

You operate as an orchestrator by default — mandatory, not skippable for "simple" tasks. The full protocol (task classification, agent-first routing, fan-out shapes and aggregation policy, narrow exemptions, sub-agent obligations) is defined in `rules/orchestrator-protocol.md`, `rules/agent-first-selection.md`, and `rules/research-parallelism.md`, loaded automatically every session.

## Development Conventions

### Documentation Standards

All Markdown files must follow the conventions in [`standards/documentation.md`](standards/documentation.md): heading depth limited to `###` (with `####` allowed sparingly), code fences must have language tags, no badges/emojis, no TOC or diagrams except in README.md (TOC required, Mermaid permitted), terse declarative tone. README and CLAUDE.md files have additional structural requirements defined in that document.

### Plan Before Code

Before writing, editing, or deleting code: present an implementation plan, wait for explicit approval, then implement. Full protocol (approval workflow, revision handling, sub-agent exception) is in `rules/plan-before-code.md`.

### Post-Implementation Review

Run the linter, verify tests, self-review the diff, and run `validate.sh` after substantive implementation work — before closing the task or opening the PR. Full per-task and pre-PR gates are in `rules/post-implementation-review.md`.

### GitHub Flow

Short-lived feature branches merged via PR into `dev`; `main` receives only release promotions. Branch naming, merge strategy, and branch protection are defined in `rules/github-flow.md`.

### Debian Baseline

Linux-targeting guidance (server config, Ansible, Docker base images, shell examples) assumes Debian 13 (Trixie) — `apt`, `systemd`, `nftables`, DEB822 sources. Full idioms and Ubuntu 24.04 deltas are in `rules/debian-baseline.md`.

### SemVer Tagging

Release tags use SemVer with a `v` prefix, cut from `main`. Version bumps follow the Conventional Commits type (`feat` -> MINOR, `fix`/`perf` -> PATCH, breaking -> MAJOR; pre-1.0 breaking bumps MINOR). Full release process is in `rules/semver-tagging.md`.

### PR Template Standard

Every repo's `.github/PULL_REQUEST_TEMPLATE.md` requires Summary, Type of Change, Test Plan, and Checklist sections. Full section spec is in `rules/pr-template-standard.md`.

### Conventional Commits

Commit messages follow `<type>(<scope>): <description>` — imperative, lowercase, no trailing period, no authorship attributions. Full type list and constraints are in `rules/conventional-commits.md`.

### Research Parallelism and Agent Efficacy Reporting

Research tasks fan out to 3+ parallel agents from different angles; synthesize a best-of-breed answer, surface disagreements, and produce an Agent Efficacy Report. Full protocol, dependency liveliness assessment, and report structure are in `rules/research-parallelism.md`.

## Security Policies

### No MCP Servers

This repo prohibits MCP server usage and any runtime mechanism that injects external network content into the harness system context. All tool access is controlled through explicit `tools` allowlists; never commit a project-level `.claude/settings.json`. Full policy, CVE rationale, and acceptable defense-in-depth alternatives are in `rules/no-mcp-servers.md`.

### Minimal Tool Lists

Grant only the tools an agent's purpose requires. `Bash` is limited to the `CLAUDE_BASH_ALLOWED` allowlist in `validate.sh`, with per-agent justifications in ADR-069. Never embed tokens, keys, or passwords in any agent or rule.

### Secrets Guard

Secrets are guarded in two fail-closed layers — pre-commit (`hooks/secrets-guard.sh`) and in-session `PreToolUse` (`hooks/session-secrets-guard.sh`) — sharing one pattern set and override mechanisms (`SKIP_SECRETS_GUARD=1`, `.secrets-guard-allowlist`). Full pattern set and layer detail are in `rules/secrets-guard.md`.

### GitHub Identity Guard

Two fail-closed layers block a `git push` or mutating `gh` call from the wrong account on a multi-account host: an in-session `PreToolUse` hook and a git pre-push hook. Full signal model and overrides are in `rules/gh-identity-guard.md`.

## Validation

Run before every push (enforced by the pre-push hook installed by `setup.sh`):

```bash
./validate.sh
```

This checks: monolithic agent validation (frontmatter presence, `disable-model-invocation: true`, no prohibited `mcp-servers` key, body present), MCP prose-reference heuristic (concrete package-name patterns in distributed rule/agent/command/skill/web prose; warns — #37), committed plugin/MCP manifest check (any `.mcp.json` or `.claude-plugin/` errors — ADR-094), rule Enforcement-line presence (every `rules/*.md` carries `**Enforcement:**` near its H1; off-vocabulary mechanism tokens warn — ADR-084), agent catalog drift (via `scripts/regen-agent-catalog.sh --check` — AGENTS.md canonical: name presence vs `agents/*.md`, Domain/Use-when parity in the routing mirror `rules/agent-first-selection.md`, README Tier/Model), `Bash` tool allowlist (only ADR-069-listed agents may carry it; enforced by `CLAUDE_BASH_ALLOWED`), README Agents/Rules consistency (Current Agents/Rules vs files on disk), `web/instructions.md` Agent Catalog sync drift (presence and manifest pairs against `origin/dev` diff; override via `Web-Sync-Skip: <reason>` trailer), ADR validation (sequential numbering; gaps now allowed), hooks and symlinks, hook/shared-lib/skill-script shellcheck linting (`hooks/*.sh`, `scripts/lib/*.sh`, and `skills/*/scripts/*.sh`; errors on findings, skipped when shellcheck is absent), shared-lib self-tests (`scripts/lib/*.sh --self-test` run as subprocesses; ADR-061), hook-pair lockstep (the duplicated secret-pattern set and identity-helper functions must stay byte-identical across their hook pairs; errors on drift; ADR-083), ruleset required-check drift (every context in rulesets/*.json must match a workflow job's effective check name; errors; offline — ADR-086), relative markdown link resolution (superseded ADRs exempt — their bodies are frozen per the supersession-not-editing rule), documentation standards (heading depth, code fence tags), branch/PR state, and GitHub identity (warns when the active `gh` account cannot resolve the `origin` repo on multi-account hosts; skipped under `GH_TOKEN`/`GITHUB_TOKEN` or non-`github.com` remotes).
