# ADR-030: Add docker-expert domain specialist agent

**Status:** Accepted
**Date:** 2026-04-02

## Context and Problem Statement

Docker and BuildKit usage spans local development, CI/CD pipelines, and production deployments across the ecosystem. Neither shell-expert nor the linter's hadolint coverage provides design-level Docker expertise. BuildKit secret mount edge cases (`--mount=type=secret`), cache mount optimizations (`--mount=type=cache`), multi-platform build performance tuning, `# syntax` directive requirements, and multi-stage build patterns are high-density pitfall areas where generic LLM knowledge frequently produces outdated or subtly incorrect guidance — particularly around BuildKit-specific features that diverge from legacy builder behavior.

## Considered Options

* **Option A** — Add a dedicated `docker-expert` domain specialist agent with SKILL.md encoding BuildKit, multi-stage, security, and Compose pitfalls
* **Option B** — Extend `shell-expert` to cover Dockerfiles as a subsection
* **Option C** — Rely on the linter's hadolint integration plus general-purpose agents with web search

## Decision Outcome

Chosen option: **Option A**, because Docker's domain (BuildKit execution model, layer caching semantics, multi-platform manifests, Compose service orchestration) is distinct from shell scripting and mechanical linting. Extending shell-expert would dilute its focus and conflate two different execution models. Hadolint catches structural issues but cannot advise on cache mount strategies, secret handling patterns, or multi-stage optimization — the exact areas where encoded expertise prevents costly rebuild cycles and security misconfigurations.

### Tradeoffs

* Good: Prevents documented failure modes (legacy builder syntax in BuildKit contexts, insecure COPY patterns, suboptimal cache invalidation); covers Compose v2 semantics and multi-platform build matrices
* Bad: Adds a new three-file set to maintain; Docker's breadth (BuildKit, Compose, Swarm, registry APIs) means SKILL.md must focus on cross-cutting pitfalls and delegate reference docs to `docker --help` and official documentation

## More Information

* Follows the domain specialist tier (ADR-021): read-only tools, no Write/Edit
* Tracked in issue #74
* Agent catalog precedent: #75 (helm-expert), #99 (ansible-expert)
* Originated from Agent Efficacy Report (2026-03-30) identifying BuildKit secret mount and cache mount optimization as knowledge gaps
