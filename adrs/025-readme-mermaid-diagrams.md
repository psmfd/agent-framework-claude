# ADR-025: Mermaid diagrams in README.md

**Status:** Accepted
**Date:** 2026-03-31

## Context and Problem Statement

The documentation standard (`standards/documentation.md`) prohibits diagrams and images in all `.md` files, requiring architecture to be described in prose or tables. The agent framework has grown to include multiple interconnected workflows (orchestrator protocol, research parallelism, expertise lifecycle, planning-to-review lifecycle) that are difficult to communicate through prose alone. The README needs visual representations of these communication paths and workflows to orient new readers and serve as quick-reference for existing users.

## Considered Options

* **Option A** — Allow Mermaid diagrams in README.md only, amend the documentation standard with a scoped exception
* **Option B** — Allow Mermaid diagrams in all `.md` files, remove the prohibition entirely
* **Option C** — Status quo — keep the prohibition, describe all workflows in prose and tables

## Decision Outcome

Chosen option: **Option A**, because README.md is the primary orientation surface for the repository and benefits most from visual workflow diagrams, while the prohibition remains valuable for skill files, rules, and other documents where prose and tables are sufficient and more maintainable. A scoped exception limits the maintenance burden of keeping diagrams accurate to a single file.

### Tradeoffs

* Good: visual communication of complex multi-agent workflows; faster orientation for new readers; diagrams render natively on GitHub and most Markdown viewers
* Bad: diagrams must be kept in sync with workflow changes; Mermaid rendering varies across platforms (GitHub, ADO, VS Code preview); adds maintenance surface to README

## More Information

Mermaid diagram types used: `flowchart` (LR and TD) for routing and sequential workflows, `stateDiagram-v2` for lifecycle states. All types are supported on GitHub and Azure DevOps. Node IDs use camelCase to avoid hyphen/edge-operator conflicts in Mermaid syntax.
