# ADR-031: Add helm-expert domain specialist agent

**Status:** Accepted
**Date:** 2026-04-02

## Context and Problem Statement

Helm is the standard deployment tool for Kubernetes workloads across the ecosystem. Existing agents handle Helm "adequately" at a surface level but lack deep knowledge of values merge semantics (replace vs merge for maps and lists), `helm diff` for pre-deploy validation, Helm hook patterns and ordering, and values layering strategies for multi-environment deployments. These are high-density pitfall areas where incorrect merge behavior silently produces wrong configurations and hook ordering mistakes cause deployment failures that are difficult to diagnose.

## Considered Options

* **Option A** — Add a dedicated `helm-expert` domain specialist agent with SKILL.md encoding values semantics, hooks, diff workflows, and chart structure pitfalls
* **Option B** — Extend an existing agent (shell-expert or a future IaC agent) to cover Helm as a subsection
* **Option C** — Rely on general-purpose agents with web search for Helm tasks

## Decision Outcome

Chosen option: **Option A**, because Helm's domain (Go template engine, values merge algebra, hook lifecycle, chart dependency resolution) is a distinct knowledge area with its own execution model and failure modes. Subsectioning it under another agent would dilute focus and miss the cross-cutting interactions between values layering, hook ordering, and template debugging that require dedicated expertise. General-purpose agents consistently produce incorrect guidance on values merge semantics — the single most common source of Helm deployment failures.

### Tradeoffs

* Good: Prevents documented failure modes (list-replace-not-merge surprise, hook weight ordering, subchart values scoping); covers `helm diff` pre-deploy validation and template debugging workflows
* Bad: Adds a new three-file set to maintain; Helm's ecosystem (chart museums, OCI registries, Helmfile, helm-secrets) means SKILL.md must focus on core Helm 3 pitfalls and delegate ecosystem tooling to documentation references

## More Information

* Follows the domain specialist tier (ADR-021): read-only tools, no Write/Edit
* Tracked in issue #75
* Agent catalog precedent: #74 (docker-expert), #99 (ansible-expert)
* Originated from Agent Efficacy Report (2026-03-30) identifying values merge semantics and hook patterns as knowledge gaps
