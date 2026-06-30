# ADR-029: Add ansible-expert domain specialist agent

**Status:** Accepted
**Date:** 2026-04-02

## Context and Problem Statement

The ecosystem is expanding Ansible usage for VPS provisioning and infrastructure automation. Ansible has a high-density pitfall surface — 22-level variable precedence, the 2.9/2.10 architecture cliff (ansible-core vs. collections), `become` + pipelining + `requiretty` interactions, Jinja2 type coercion, and handler execution semantics — where generic LLM knowledge frequently produces confidently wrong or outdated answers. No existing agent covers this domain: shell-expert handles shell scripting but not Ansible-specific semantics, and general-purpose agents lack encoded knowledge of the post-2.10 collection architecture and deprecation pipeline.

## Considered Options

* **Option A** — Add a dedicated `ansible-expert` domain specialist agent with SKILL.md encoding cross-cutting pitfalls
* **Option B** — Extend `shell-expert` to cover Ansible as a subsection
* **Option C** — Rely on general-purpose agents with web search for Ansible tasks

## Decision Outcome

Chosen option: **Option A**, because Ansible's domain is distinct from shell scripting (it has its own execution model, variable system, module namespaces, and connection plugins), and the pitfall density justifies dedicated encoded expertise. Extending shell-expert would dilute its focus and exceed SKILL.md size constraints. General-purpose agents produce wrong answers for variable precedence, FQCN requirements, and the ansible-core/ansible package distinction — the exact areas where encoded expertise adds the most value.

### Tradeoffs

* Good: Prevents documented LLM failure modes (variable precedence, pre-2.10 syntax, handler edge cases); covers GitHub Actions integration patterns specific to ansible-core
* Bad: Adds a new three-file set to maintain; Ansible's breadth (9,200+ modules, 30+ collection namespaces) means SKILL.md cannot be exhaustive — must focus on cross-cutting pitfalls and delegate module docs to `ansible-doc`

## More Information

* Follows the domain specialist tier (ADR-021): read-only tools, no Write/Edit
* Agent catalog precedent: #74 (docker-expert), #75 (helm-expert)
* Motivated by ansible-core version and callback plugin issues encountered in an internal service repo CI/CD provisioning workflow
