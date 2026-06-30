# ADR-023: Consolidate documentation standards into a dedicated file

**Status:** Accepted
**Date:** 2026-03-27

## Context and Problem Statement

Documentation conventions (README section order, CLAUDE.md structure, Markdown formatting rules) were observed implicitly from existing files but never codified. Issue #35 identified this gap after documentation standards had to be reverse-engineered during a project setup. The question is whether to consolidate these standards into a single dedicated file or distribute them across existing files (CONTRIBUTING.md, AGENTS.md, standards/tooling.md).

## Considered Options

* **Option A** — Create `standards/documentation.md` as a dedicated documentation standards file
* **Option B** — Distribute documentation conventions across existing files (add README guidance to CONTRIBUTING.md, CLAUDE.md guidance to AGENTS.md, formatting rules to each file that needs them)
* **Option C** — Status quo — leave conventions implicit and discoverable only by reading existing files

## Decision Outcome

Chosen option: **Option A**, because documentation conventions (README structure, CLAUDE.md structure, Markdown formatting) are a cohesive concern that does not belong in CONTRIBUTING.md (contribution process), AGENTS.md (agent behavior), or standards/tooling.md (technology choices). A dedicated file is consistent with how `standards/tooling.md` handles technology standards — each `standards/` file owns a distinct concern.

### Tradeoffs

* Good: single authoritative source for all documentation conventions; agents and contributors have one file to consult; `validate.sh` can enforce checks by referencing the standard
* Bad: one more file to maintain; documentation about documentation risks becoming meta-overhead

## More Information

* Issue: #35
* Validation checks for heading depth, code fence language tags, and structural requirements were added to `validate.sh` alongside this ADR.
