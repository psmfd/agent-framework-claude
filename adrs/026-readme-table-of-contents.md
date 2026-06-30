# ADR-026: Require table of contents in README.md

**Status:** Accepted
**Date:** 2026-03-31

## Context and Problem Statement

The documentation standard (`standards/documentation.md`) prohibits tables of contents with the rationale that documents should be short enough not to need one. The README has grown to 700+ lines covering repository structure, settings, rules, agents, skills, workflows (with 6 Mermaid diagrams added in ADR-025), installation, and precedence. Navigating this content without a TOC requires scrolling or browser search. Other documents in the repo (SKILL.md files, rules, ADRs, standards) remain short enough that the prohibition is appropriate.

## Considered Options

* **Option A** — Require a manually maintained TOC in README.md, keep the prohibition for other documents
* **Option B** — Remove the TOC prohibition entirely, allow TOC in any document
* **Option C** — Status quo — no TOC anywhere, rely on scrolling and browser search

## Decision Outcome

Chosen option: **Option A**, because the README is the only document in the repo that has grown beyond comfortable navigation without a TOC. A scoped requirement (not just permission) ensures the TOC is maintained as sections are added or removed. Keeping the prohibition for other documents avoids unnecessary boilerplate in short files where a TOC would be longer than the content it indexes.

### Tradeoffs

* Good: faster navigation of the README; readers can assess the document's scope at a glance; consistent with ADR-025's scoped exception pattern
* Bad: TOC must be manually updated when H2 sections change; adds maintenance surface to README edits

## More Information

Follows the same scoping pattern as ADR-025 (Mermaid diagrams in README.md only). The TOC covers H2 sections only — H3 subsections are not included to keep the TOC concise.
