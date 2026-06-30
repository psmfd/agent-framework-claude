# Development Tooling and Language Standards

Canonical technology stack the agents consult when making technology choices and
giving technology-specific guidance (see ADR-020).

> **This is a template — customize it for your own environment.** The entries below
> are sensible defaults, not prescriptions. Replace, add, or remove rows to match the
> languages, platforms, and tooling your projects actually use. Agents read this file
> to bias recommendations toward your stack, so keep it accurate to *your* choices.

## Languages and Frameworks

| Technology | Version | Use |
|---|---|---|
| C# / .NET | 10 | Console applications, services, web applications |
| ASP.NET Core | 10 | Web APIs, web applications |
| Entity Framework Core | 10 | ORM — where applicable |
| Bash | 4.0+ minimum | Scripting, automation |
| Python | Latest stable (managed via PDM + UV) | Tooling, scripting, automation |
| Node.js | Latest LTS (managed via nvm) | Tooling — linters, build tools |
| SQL | T-SQL / PL/pgSQL (per database) | Database queries, stored procedures |
| HCL | — | Terraform configurations |
| YAML / JSON / Markdown | — | Configuration, documentation, IaC manifests |

## Databases

| Technology | Role |
|---|---|
| Relational database | Primary structured data store (e.g., MS SQL Server, PostgreSQL) |
| PostgreSQL | Where a specific requirement demands it (e.g., `pgvector` for embeddings) |

Pick a primary relational database and use it consistently; reach for a second engine
only where a concrete requirement (extension, dependency, workload) demands it.

## Infrastructure and Platform

| Technology | Role |
|---|---|
| Cloud platform | Your cloud of record (e.g., Azure, AWS, GCP) |
| Kubernetes | Container orchestration |
| vCluster | Multi-tenancy / virtual clusters |
| Docker | Container images and local development |
| cert-manager | TLS certificate automation on Kubernetes |

## IaC and Configuration Management

| Technology | Version | Role |
|---|---|---|
| Terraform / OpenTofu | — | Infrastructure provisioning |
| Bicep | — | Azure-native IaC (where Azure is used) |
| Ansible | 2.19+ (prefer current release) | Post-creation VM and appliance configuration |
| Helm | 3 | Kubernetes deployment and packaging |

**Provisioning vs. configuration boundary:** Terraform/Bicep provision infrastructure.
Ansible configures what runs on it after creation. Helm deploys containerized workloads.

## CI/CD, Source Control, and Work Management

| Concern | Tooling (examples) |
|---|---|
| Pipelines | GitHub Actions or Azure DevOps Pipelines |
| Source control | GitHub or Azure Repos |
| Work/Project management | GitHub Issues/Projects or Azure DevOps Boards |
| Package registry | GitHub Packages / NuGet.org / your registry of record |

This framework follows GitHub Flow (see `rules/github-flow.md`); adapt to your platform.

## Identity and Authentication

| Technology | Role |
|---|---|
| Cloud identity provider | Your IdP of record (e.g., Microsoft Entra ID) |
| Directory service | On-premises identity where applicable |

Adopt additional identity providers only with deliberate justification — not by default.

## Observability

A Prometheus/Grafana-family stack is a sensible open-source default:

| Component | Role |
|---|---|
| Grafana | Dashboards and visualization |
| Prometheus | Metrics collection |
| Mimir | Long-term metrics storage |
| Loki | Log aggregation |
| Alertmanager | Alert routing and notification |
| Alloy | Telemetry collector |

## AI and ML

| Technology | Role |
|---|---|
| LLM orchestration framework | Application-level AI orchestration (e.g., Semantic Kernel for .NET) |
| Local inference | Local LLM inference and embeddings (e.g., Ollama) |

## Linting

Linting tools are cataloged in the [linter agent](../agents/linter.md). The current set:

| Tool | Targets |
|---|---|
| shellcheck | Shell scripts (`.sh`, shebang detection) |
| markdownlint-cli2 | Markdown (`.md`) |
| yamllint | YAML (`.yaml`, `.yml`) |
| dotnet format | C# / .NET projects |
| helm lint | Helm charts (`Chart.yaml`) |
| hadolint | Dockerfiles |
| terraform validate / tflint | Terraform (`.tf`) |
| actionlint | GitHub Actions workflows |
| ruff | Python (`.py`) |

## Operating Systems

| Context | Operating Systems |
|---|---|
| Servers / VMs | Debian 13 (Trixie) — see `rules/debian-baseline.md` — plus your chosen server OSes |
| Workstations | Your chosen workstation OSes (Linux, macOS, Windows) |

## Dev Tooling and Agent Platforms

| Tool | Role |
|---|---|
| Git | Version control |
| GitHub CLI (`gh`) | GitHub API interaction |
| VS Code | Editor |
| nvm | Node.js version management |
| PDM + UV | Python package and environment management |
| Claude Code | AI coding assistant (CLI, desktop, web, IDE extensions) |
