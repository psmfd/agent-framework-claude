# ADR-032: Add dotnet-expert domain specialist agent

**Status:** Accepted
**Date:** 2026-04-02

## Context and Problem Statement

The ecosystem is expanding .NET usage for the internal service and related services. .NET 10 LTS introduced significant changes (built-in container support, AOT improvements, minimal API enhancements, `IHostedService` lifecycle changes) and the project targets cross-platform deployments across macOS (Apple Silicon), Linux (k3s), Windows, and containers. No existing agent covers the .NET domain: shell-expert handles shell scripting, docker-expert covers container image authoring, but neither addresses .NET SDK tooling, ASP.NET Core patterns, worker service lifecycle, DI lifetime pitfalls, EF Core migration ordering, or the cross-platform publish matrix. General-purpose agents produce unreliable answers for DI lifetime mismatches, nullable reference type edge cases, and the differences between `dotnet publish` profiles across RIDs.

## Considered Options

* **Option A** — Add a dedicated `dotnet-expert` domain specialist agent with SKILL.md encoding cross-platform patterns, ASP.NET Core, worker services, and security best practices
* **Option B** — Extend `docker-expert` to cover .NET containerization patterns as a subsection
* **Option C** — Rely on general-purpose agents with web search for .NET tasks

## Decision Outcome

Chosen option: **Option A**, because .NET's domain is distinct from container orchestration (it has its own SDK, project system, DI framework, hosting model, and publish pipeline), and the cross-platform deployment matrix (macOS ARM64, Linux x64/ARM64, Windows, containers) creates a dense pitfall surface that justifies dedicated encoded expertise. Extending docker-expert would dilute its focus and miss non-container .NET concerns (worker services, testing, security). General-purpose agents produce wrong or outdated answers for DI lifetime rules, nullable reference type interactions, and the AOT compatibility matrix.

### Tradeoffs

* Good: Prevents documented LLM failure modes (DI lifetime mismatches, AOT incompatibilities, cross-RID publish failures); covers both web and worker service patterns needed by the internal service
* Bad: Adds a new three-file set to maintain; .NET's breadth (ASP.NET Core, EF Core, Blazor, MAUI) means SKILL.md cannot be exhaustive — must focus on web APIs, worker services, and cross-platform deployment patterns relevant to the ecosystem

## More Information

* Follows the domain specialist tier (ADR-021): read-only tools, no Write/Edit
* Agent catalog precedent: #74 (docker-expert), #75 (helm-expert), #99 (ansible-expert)
* Motivated by an internal service inference backend implementation requiring ASP.NET Core DI, BackgroundService, and cross-platform deployment across k3s and macOS
