# ADR-034: Standardized Script Output Conventions

**Status:** Superseded by [ADR-051](051-diagnostic-output-to-stderr.md)
**Date:** 2026-04-07

## Context and Problem Statement

The agent framework produces, suggests, and designs shell scripts across multiple repositories. Existing scripts in this repo (`validate.sh`, `the queue-flush script`, `scaffold.sh`) use similar but inconsistent output formats — different label widths, inconsistent bracket usage, and no shared specification for exit codes or summary blocks. Without a standard, every new script reinvents its output format, making cross-script parsing and human scanning harder than it needs to be.

## Considered Options

* **Option A** — Framework-wide output convention as a rule, applied to all scripts the framework produces
* **Option B** — Repo-local convention documented in CONTRIBUTING.md, applied only to scripts in this repo
* **Option C** — Status quo / no convention, let each script choose its own format

## Decision Outcome

Chosen option: **Option A**, because the agent framework's purpose is producing consistent, high-quality artifacts. Script output is a user-facing surface that benefits from the same standardization applied to commit messages, PR templates, and review formats. A framework-wide default with project-level override preserves flexibility without sacrificing consistency.

### Tradeoffs

* Good: consistent, grep-able output across all framework-generated scripts; parseable by CI tooling; clear exit code semantics
* Good: target project conventions take precedence, so the standard does not force conflicts
* Bad: existing scripts in this repo will need a follow-up retrofit to fully conform
* Bad: adds one more rule to the framework's convention set

## More Information

The output format specification is defined in `rules/script-output-conventions.md`. Existing scripts (`validate.sh`, `the queue-flush script`) largely conform already — the primary gaps are missing `SKIP` support and inconsistent bracket labels in the flush script.
