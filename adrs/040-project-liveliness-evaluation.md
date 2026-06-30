# ADR-040: Project Liveliness Evaluation in Research Protocol

**Status:** Accepted
**Date:** 2026-04-14

## Context and Problem Statement

When research agents evaluate and recommend external libraries, tools, or utilities, they do not assess whether the project is actively maintained. This gap was identified during research into SFTP/file transfer tools, where project health was a valid concern requiring manual investigation. Recommending abandoned or stagnating projects risks unpatched security vulnerabilities, degrading platform compatibility, and no path forward for bug fixes.

## Considered Options

* **Option A** — Add a "Dependency Liveliness Evaluation" section to the research parallelism rule, defining signals to check and a standard output format
* **Option B** — Create a dedicated `project-health` agent that evaluates project liveliness on demand
* **Option C** — Add guidance as an lookup pattern rather than a rule, relying on stored entries about specific project health assessments
* **Option D** — Status quo — rely on manual checking when project health is a concern

## Decision Outcome

Chosen option: **Option A**, because liveliness evaluation is a research quality concern that applies across all domains and agent types. Embedding it in the research parallelism rule ensures every research task that recommends external dependencies includes a health assessment, without the overhead of a dedicated agent or the inconsistency of ad-hoc expertise entries.

### Tradeoffs

* Good: universal coverage — any research task recommending a dependency must assess liveliness, regardless of which agents are involved
* Good: lightweight — no new agent, no new infrastructure, just a section in an existing rule with a defined output format
* Bad: agents must gather liveliness signals themselves (via web search, GitHub API, etc.) rather than delegating to a specialist — this may produce inconsistent depth of assessment across different agent types
* Bad: the signals table is guidance, not automation — agents may miss signals or assess them superficially without tooling to enforce thoroughness

## More Information

* Issue: #93
* Rule: `rules/research-parallelism.md` — "Dependency Liveliness Evaluation" section
* Copilot mirror: `copilot/instructions/research-parallelism.instructions.md`
* Trigger: research into Midnight Commander (mc) for SFTP integration, where the user asked "is MC actively being developed?" and the research agents did not proactively address the question
