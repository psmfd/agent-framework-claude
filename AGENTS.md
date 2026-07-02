# Agent Framework — Project Conventions

This repository distributes shared AI agent rules and agent definitions for Claude Code. It uses a **monolithic agent architecture** (ADR-074): domain expertise lives directly in each agent file, with no separate skill layer or platform wrappers.

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
tests/validate/run-tests.sh                 # validate.sh clone-and-mutate regression (bash 4+)
tests/wim/run-tests.sh                      # end-to-end work-item scripts via CLI shims
tests/worktree-guard/run-tests.sh           # worktree-create.sh symlink containment (ADR-070)

# Bash 3.2 floor check — runs the 3.2-targeted scripts under a real 3.2 binary
# (macOS /bin/bash); SKIPs on hosts without one. CI runs it on macOS (ADR-083).
scripts/check-bash32.sh

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
| `code-review-expert` | Domain Specialist | Code review | Semantic review — logic errors, design quality, security concerns, requirement fidelity |
| `docker-expert` | Domain Specialist | Docker | Dockerfiles, BuildKit, rootless builds, multi-stage, multi-platform, Compose v2, security patterns |
| `docs-expert` | Domain Specialist | Documentation | Best practices, content style, curation, Mermaid diagrams for general display and Azure DevOps |
| `dotnet-expert` | Domain Specialist | .NET | .NET 10 LTS SDK, cross-platform builds, ASP.NET Core, worker services, DI, EF Core, testing, publishing, security |
| `gh-cli-expert` | Domain Specialist | GitHub CLI | Working with issues, PRs, releases, checks, repos via `gh` commands |
| `gitflow-expert` | Domain Specialist | Git workflows | Branching strategies, PR workflows, release processes, commit conventions |
| `helm-expert` | Domain Specialist | Helm | Chart authoring, values merge semantics, hooks, template debugging, dependency management, release workflows |
| `hyperv-expert` | Domain Specialist | Hyper-V | Type-1 hypervisor, VM generations + VHDX, virtual switches, checkpoints, nested virtualization, WSL2 utility VM, WHPX, VBS/HVCI |
| `kafka-developer-expert` | Domain Specialist | Kafka development | Producer/consumer dev for Kafka 4.x, delivery semantics, idempotence/transactions, consumer groups/rebalance, partition design, client auth |
| `kafka-self-managed-expert` | Domain Specialist | Self-managed Kafka | Kafka 4.x on Kubernetes, Strimzi and first-party operators, KRaft, storage, HA, cluster admin, encryption/auth |
| `linter` | Execution Provider | Code quality | Running shellcheck, markdownlint, yamllint, and other linters on changed files |
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

You operate as an orchestrator by default. This is mandatory session-level behavior. It is not optional. It is not something you may skip because a task "seems simple." Two rules define your orchestration responsibilities — you MUST apply them as a unified protocol:

1. **Agent-First Selection** — route to custom agents before general-purpose. Check EVERY agent in the catalog — tasks frequently touch multiple domains. Using a general-purpose agent when a custom agent covers the domain is a protocol violation. If a named `subagent_type` does not resolve, fall back to general-purpose with the same brief and file a catalog-drift issue (see `rules/agent-first-selection.md`).
2. **Research Parallelism** — fan out to 3+ parallel agents for research tasks. Produce Agent Efficacy Reports. Fewer than 3 is a violation unless fewer than 3 relevant agents exist.

**Mandatory task classification:** Before acting on ANY task, explicitly classify it as Research, Implementation, or Exempt. State the classification to the user. Silent classification is a protocol violation. If uncertain, classify UP, never down.

**Session workflow:** Route (check catalog) → Delegate (brief each agent with question, context, expected output form, and the required return contract — a bounded executive summary plus the terminal verdict line) → Collect (wait for all agents) → Synthesize (combine results, produce efficacy report).

**Narrow exemptions (the ONLY valid reasons to skip):** operating as a subagent; a literal single tool invocation (one specific file read or grep the user named); direct implementation of an already-approved plan; or a **verified single-fact lookup** — one objectively correct answer from a single named, already-available (or one-call-obtainable) authoritative source, requiring zero synthesis, not itself a decision/recommendation, with a bounded and immediately correctable blast radius (all four required — see `rules/orchestrator-protocol.md`). "This seems simple," "I can handle this directly," and "this is just a quick operational task" are NOT valid exemptions — they satisfy none of the four criteria above.

## Development Conventions

### Documentation Standards

All Markdown files must follow the conventions in [`standards/documentation.md`](standards/documentation.md): heading depth limited to `###` (with `####` allowed sparingly), code fences must have language tags, no badges/emojis, no TOC or diagrams except in README.md (TOC required, Mermaid permitted), terse declarative tone. README and CLAUDE.md files have additional structural requirements defined in that document.

### Plan Before Code

Before writing, editing, or deleting any code:

- Create an implementation plan and present it to the user for review.
- The plan must include: what files will be changed, what the changes are, and why.
- Wait for explicit user approval before making any code modifications.
- If the user requests changes to the plan, revise and re-present for approval.
- Trivial clarifications or questions do not require a plan — only actions that modify code.
- Reading, searching, and exploring code to inform the plan is always permitted without approval.
- Sub-agent exception: when a parent agent has already received plan approval and delegates to a sub-agent, the sub-agent proceeds directly without re-presenting the plan.

### Post-Implementation Review

After completing implementation changes, run a review pass before committing or opening a PR.

- Run the linter agent on all changed files to catch style, formatting, and structural issues.
- Verify tests pass where the project has a test suite. Do not skip failing tests.
- Review your own changes — re-read the diff for unintended modifications, leftover debug code, or missed requirements.
- Run `validate.sh` when changes touch agents or rules.
- This applies after substantive implementation work, not documentation-only edits, single-line fixes, or configuration changes where no test suite exists.

### GitHub Flow

All repos follow GitHub Flow: short-lived feature branches merged via PR into `dev` (the integration branch). `main` is the stable branch — code reaches `main` only via release promotion. Branch names follow `<type>/kebab-case-description` using Conventional Commits types. Squash merge for feature branches into `dev` — the PR title becomes the commit message and must be valid Conventional Commits format. Merge commit for `dev` → `main` release promotions — preserves shared SHAs to prevent branch divergence. See `rules/github-flow.md` for branch protection, lifecycle, and GitHub settings.

### Debian Baseline

All Linux-targeting guidance assumes Debian 13 (Trixie) as the baseline distribution. Use Debian idioms for package management (`apt`), service management (`systemd`/`systemctl`), firewall (`nftables`), and APT sources (DEB822 format). Key differences from Ubuntu 24.04 are documented in the rule, including `ssh.socket` activation, nftables default, and cloud-init behavior. This applies to server/VM configuration, Ansible targeting Linux, Docker base images, and shell examples with distro-specific commands. See `rules/debian-baseline.md` for the full comparison table.

### SemVer Tagging

Release tags use Semantic Versioning with a `v` prefix (`v1.2.3`), cut from `main` as annotated tags. Version bumps follow Conventional Commits: `feat` -> MINOR, `fix`/`perf` -> PATCH, breaking changes -> MAJOR. Pre-1.0 projects start at `v0.1.0` with breaking changes bumping MINOR per SemVer spec section 4. Release automation is handled by `semantic-release` on pushes to `main` (see ADR-042). PR validation (`validate.sh`) and PR title linting run as GitHub Actions on PRs targeting `dev`. See `rules/semver-tagging.md` for the release process and container image tagging.

### PR Template Standard

Every repo must have a `.github/PULL_REQUEST_TEMPLATE.md` with four required sections: Summary, Type of Change, Test Plan, and Checklist. Optional sections (API Changes, Database/Schema, Screenshots, Dependencies) are included when applicable. PR title must be valid Conventional Commits format. PRs are optional for solo developers without CI/CD; required once gates or team members are added. See `rules/pr-template-standard.md` for section details.

### Conventional Commits

All commit messages must follow Conventional Commits format: `<type>(<scope>): <description>`.

Valid types: `feat`, `fix`, `perf`, `docs`, `chore`, `refactor`, `test`, `ci`, `style`.

- Type is required. Scope is optional but recommended (use the agent name or affected area).
- Description is imperative, lowercase, no trailing period.
- No authorship attributions in commit messages.
- Body is optional. Use it for context on non-obvious changes.
- Use `!` after type/scope for breaking changes: `feat(validate)!: require section coverage`.

### Research Parallelism

When investigating a question, exploring solutions, or researching unfamiliar territory:

- Fan out with a minimum of 3 parallel agents, each approaching the problem from a different angle.
- Wait for all agents to return before synthesizing a response.
- Synthesize the best-of-breed answer by comparing and combining results — do not simply pick one.
- If agents disagree, highlight the disagreement and explain which perspective is strongest and why.
- When recommending external libraries, tools, or utilities, assess project liveliness (last release, commit recency, issue activity, contributor count). Include a liveliness assessment with status (Active / Maintenance-only / Stale / Abandoned) and risk level (Low / Medium / High). Do not recommend Abandoned projects without justification and a mitigation plan.

### Agent Efficacy Reporting

Every research, design, and implementation phase that invokes agents must include an Agent Efficacy Report containing:

1. Agent table — for each agent: name, type, duration, key contributions, value rating (High/Medium/Low).
2. Disagreements — where agents disagreed and which perspective was chosen and why.
3. Synergies — how agent outputs combined or complemented each other.
4. Custom agent feedback — improvement opportunities for custom agents.

## Security Policies

### No MCP Servers

This repo prohibits MCP server usage in all content it produces or distributes.

- Never add `mcp-servers` to any frontmatter field in agent wrappers.
- Never reference MCP server packages (npm, PyPI, or otherwise) in agent content.
- All tool access must be controlled through explicit `tools` allowlists in agent wrapper frontmatter.
- Never commit a project-level `.claude/settings.json` (or `.claude/settings.local.json`) into a repo — Claude Code auto-loads that path as project config when a user opens the repo, the CVE-2025-59536 auto-execution vector. The repo's root `settings.json` is the deliberate, audited distribution payload: never auto-loaded, active only after a user runs `setup.sh` to symlink it into user-level `~/.claude/`. The carve-out is that root file alone; it never licenses committing a `.claude/settings.json` path (`.gitignore` ignores `.claude/` as added friction, not a hard gate).
- If a user requests MCP server integration, explain this policy and suggest the `tools` allowlist approach instead.

This policy exists because runtime-loaded MCP servers are a supply-chain attack surface that the `tools` allowlist cannot constrain — the threat class captured by OWASP ASI04 (Agentic Supply Chain Vulnerabilities) and OWASP MCP04:2025 (Software Supply Chain Attacks). Both known Claude Code CVEs reinforce the related lesson that committed content must never carry runtime-loaded configuration: CVE-2025-59536 (pre-trust-dialog code execution from a repository-controlled `.claude/settings.json`, via project hooks and an MCP consent bypass; CVSS 8.7, fixed v1.0.111) and CVE-2026-21852 (API-key exfiltration via `ANTHROPIC_BASE_URL` redirection in the same file, with no MCP involvement; CVSS 5.3, fixed v2.0.65).

The policy extends to **any runtime mechanism that injects external network content into the harness system context**, not just MCP as a protocol. Hooks that fetch content from a remote URL and emit it as `systemMessage` are policy-equivalent to MCP server injection. See `rules/no-mcp-servers.md` for the full prohibited-mechanism list and acceptable defense-in-depth alternatives. ADR-046 documents the removal of one such mechanism (a UserPromptSubmit hook that injected external API content into the system context).

### Minimal Tool Lists

Grant only the tools an agent's purpose requires. `Bash` is granted only to agents whose body documents an execution workflow — the justification table in ADR-069 is the authoritative record of what qualifies; all other read-only expert agents must not carry it. The permitted set is enforced by the `CLAUDE_BASH_ALLOWED` allowlist in `validate.sh`, with per-agent justifications recorded in ADR-069. Never embed tokens, keys, or passwords in any agent or rule.

### Secrets Guard

Secrets are guarded in two layers sharing one pattern set. **Layer 1 (pre-commit):** `setup.sh` installs `hooks/secrets-guard.sh` as the framework repo's `pre-commit` hook, blocking commits containing unencrypted Ansible vault files (header-based detection), PEM private keys, AWS access key IDs, GitHub tokens (all five `gh*_` prefixes, incl. the `ghs_` Actions `GITHUB_TOKEN`), and SSH private-key file paths (incl. FIDO2 `_sk` keys). **Layer 2 (in-session):** `hooks/session-secrets-guard.sh` is a `PreToolUse` hook that denies the same material on `Bash`/`Write`/`Edit`/`MultiEdit`/`NotebookEdit` before it reaches disk and fails closed when `jq` is absent (ADR-053, ADR-057). Bypass either via `SKIP_SECRETS_GUARD=1` (one-shot, auditable), `.secrets-guard-allowlist` (per-path glob, version-controlled), or `--no-verify` (commit only, emergencies). The pre-commit layer only fires on the framework repo until a target-repo installer ships; pair with a server-side scanning gate to fully close the loop. See `rules/secrets-guard.md`, ADR-047, and ADR-053.

### GitHub Identity Guard

On a multi-account host, a wrong active `gh` account causes a `git push` or mutating `gh` call to target — or fail against — the wrong account. Two fail-closed layers block this: an in-session `PreToolUse` hook (`hooks/session-gh-identity-guard.sh`) for agent `git push`/`gh` mutations, and a git pre-push hook (`hooks/gh-identity-guard.sh`) for the raw-terminal/IDE/script vector. The signal is hybrid — a local-only (gitignored) `.gh-expected-identity` pin (strict login match) when present, else repo accessibility — github.com only, with `GH_IDENTITY_OVERRIDE=<login>` (env var only; ADR-070) / `.gh-identity-allowlist` / `SKIP_GH_IDENTITY_GUARD=1` overrides. This extends the warn-only `validate.sh` preflight with enforcement. See `rules/gh-identity-guard.md`, ADR-054 (supersedes ADR-052), ADR-070, and `docs/multi-account-git-identity.md`.

## Validation

Run before every push (enforced by the pre-push hook installed by `setup.sh`):

```bash
./validate.sh
```

This checks: monolithic agent validation (frontmatter presence, `disable-model-invocation: true`, body present), agent catalog drift (via `scripts/regen-agent-catalog.sh --check` — AGENTS.md canonical: name presence vs `agents/*.md`, Domain/Use-when parity in the routing mirror `rules/agent-first-selection.md`, README Tier/Model), `Bash` tool allowlist (only ADR-069-listed agents may carry it; enforced by `CLAUDE_BASH_ALLOWED`), README Agents/Rules consistency (Current Agents/Rules vs files on disk), `web/instructions.md` Agent Catalog sync drift (presence and manifest pairs against `origin/dev` diff; override via `Web-Sync-Skip: <reason>` trailer), ADR validation (sequential numbering; gaps now allowed), hooks and symlinks, hook and shared-lib shellcheck linting (`hooks/*.sh` and `scripts/lib/*.sh`; errors on findings, skipped when shellcheck is absent), shared-lib self-tests (`scripts/lib/*.sh --self-test` run as subprocesses; ADR-061), hook-pair lockstep (the duplicated secret-pattern set and identity-helper functions must stay byte-identical across their hook pairs; errors on drift; ADR-083), relative markdown link resolution (superseded ADRs exempt — their bodies are frozen per the supersession-not-editing rule), documentation standards (heading depth, code fence tags), branch/PR state, and GitHub identity (warns when the active `gh` account cannot resolve the `origin` repo on multi-account hosts; skipped under `GH_TOKEN`/`GITHUB_TOKEN` or non-`github.com` remotes).
