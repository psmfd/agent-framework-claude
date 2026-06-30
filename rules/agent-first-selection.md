---
description: 'Prefer custom skill agents over general-purpose agents for domain-specific tasks'
---

# Agent-First Selection

Custom agents exist because they encode domain expertise, known fragilities, and validated patterns that general-purpose agents lack. Using a general-purpose agent when a custom agent covers the domain is a protocol violation — it discards curated knowledge in favor of generic reasoning.

## Selection Protocol

Before delegating work to an agent, follow this protocol strictly:

1. **Check whether a custom agent covers the task domain.** Consult the catalog below. Check EVERY agent — do not stop at the first plausible match. Tasks frequently touch multiple domains.
2. **If a custom agent exists, invoke it** via the Agent tool with `subagent_type` set to the agent name.
3. **If multiple custom agents are relevant, invoke all of them.** This is not optional. A task touching GitHub CLI and git workflows requires BOTH `gh-cli-expert` and `gitflow-expert`, not just whichever one you think of first.
4. **Use general-purpose agents only when no custom agent covers the domain** — the task falls outside all cataloged domains, or requires cross-domain synthesis that no single agent handles. Even then, supplement with custom agents for any domain-specific subtasks.

## Agent Catalog

| Agent | Domain | Use when |
| --- | --- | --- |
| `gh-cli-expert` | GitHub CLI | Working with issues, PRs, releases, checks, repos via `gh` commands |
| `gitflow-expert` | Git workflows | Branching strategies, PR workflows, release processes, commit conventions |
| `work-item-management-expert` | Work item management | GitHub Issues / Projects v2 and Azure DevOps Boards — type selection, field schemas, label and tag conventions, REST and CLI formatting, cross-platform translation |
| `shell-expert` | Shell scripting | Bash/Zsh/POSIX sh compatibility, idioms, security, cross-platform strategies |
| `code-review-expert` | Code review | Semantic review — logic errors, design quality, security concerns, requirement fidelity |
| `security-review-expert` | Security review | Semantic security review for C#/.NET, Python, TypeScript, T-SQL, Azure/AWS IAM and networking, Active Directory/LDAP. Backed by first-party documentation. |
| `docs-expert` | Documentation | Best practices, content style, curation, Mermaid diagrams for general display and Azure DevOps |
| `ansible-expert` | Ansible | Playbook authoring, variable precedence, collection architecture, privilege escalation, vault, CI/CD integration |
| `docker-expert` | Docker | Dockerfiles, BuildKit, rootless builds, multi-stage, multi-platform, Compose v2, security patterns |
| `helm-expert` | Helm | Chart authoring, values merge semantics, hooks, template debugging, dependency management, release workflows |
| `dotnet-expert` | .NET | .NET 10 LTS SDK, cross-platform builds, ASP.NET Core, worker services, DI, EF Core, testing, publishing, security |
| `tauri-expert` | Tauri | Tauri 2 desktop app authoring — tauri.conf.json schema, generate_context!() codegen, build vs bundle phases, capabilities v2, cross-platform packaging, sidecar/externalBin with Rust target triples, plugin ecosystem, frontend integration, CLI, and GitHub Actions CI |
| `azure-devops-expert` | Azure DevOps | Azure Repos git operations, YAML and classic pipelines, work item management, REST API patterns |
| `azure-infra-expert` | Azure Infrastructure | Entra ID, Key Vault, Managed SignalR, Storage Accounts, Private Endpoints, Private Link, ExpressRoute, custom DNS, Log Analytics workspaces |
| `vcluster-expert` | vCluster | Virtual cluster lifecycle, vcluster.yaml configuration, resource syncing, networking, licensing, platform management |
| `linter` | Code quality | Running shellcheck, markdownlint, yamllint, and other linters on changed files |
| `aws-expert` | AWS | IAM/IRSA/SCPs, S3, VPC, Route 53, EKS, ECS/Fargate, ECR, Elastic Beanstalk, MSK |
| `terraform-expert` | Terraform / OpenTofu | HCL, providers, state and remote backends, modules, workspaces, plan/apply, drift, import, testing, CI/CD |
| `talos-expert` | Talos Linux | talosctl / machine API, machine config, cluster bootstrap, Image Factory + system extensions, OS/k8s upgrades, KubeSpan, Omni |
| `proxmox-expert` | Proxmox VE | qm/pct/pvecm/pvesm CLI, KVM VM + LXC lifecycle, storage, bridged/VLAN networking, clustering/HA, vzdump/PBS backups, cloud-init, API tokens |
| `hyperv-expert` | Hyper-V | Type-1 hypervisor, VM generations + VHDX, virtual switches, checkpoints, nested virtualization, WSL2 utility VM, WHPX, VBS/HVCI |
| `wsl2-expert` | WSL2 | wsl.exe CLI, distro export/import, wsl.conf + .wslconfig, systemd in WSL2, NAT vs mirrored networking, interop |
| `aws-msk-expert` | AWS MSK | Amazon MSK provisioned vs serverless, broker sizing/storage, auth modes (IAM/SASL-SCRAM/mTLS), MSK Connect, MSK Replicator, version management |
| `kafka-developer-expert` | Kafka development | Producer/consumer dev for Kafka 4.x, delivery semantics, idempotence/transactions, consumer groups/rebalance, partition design, client auth |
| `kafka-self-managed-expert` | Self-managed Kafka | Kafka 4.x on Kubernetes, Strimzi and first-party operators, KRaft, storage, HA, cluster admin, encryption/auth |

## Narrow Exemptions

- **No matching agent for the domain** — the task falls outside all cataloged agent domains. General-purpose agents are the correct choice. But verify this by scanning the full catalog, not by assuming.
- **Operating as a subagent** — the parent session already selected the appropriate agent for the task.
- **Cross-domain synthesis** — the task requires combining perspectives from multiple domains and no single agent covers the full scope. Use the research parallelism rule to fan out across the relevant custom agents, supplementing with general-purpose agents only for uncovered domains.

## What Is NOT an Exemption

- **"Agent invocation overhead exceeds the benefit"** — this is not your call to make. The overhead of invoking an agent is seconds. The cost of skipping domain expertise is wrong answers, missed edge cases, and user trust erosion. Invoke the agent.
- **"I already know the answer"** — your confidence is not a substitute for domain expertise. The agent may surface fragilities, caveats, or patterns you are not aware of.
