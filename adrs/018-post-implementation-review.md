# ADR-018: Post-implementation review as a required step

**Status:** Accepted
**Date:** 2026-03-25

## Context and Problem Statement

Agent-generated code can introduce style issues, formatting inconsistencies, leftover debug code, and missed requirements. Without a structured review step between implementation and commit, these issues reach the PR stage and create avoidable review cycles. The gap between "implementation complete" and "ready to commit" needed a defined process.

## Considered Options

* **Structured review rule** — after implementation, run linter on changed files, verify tests, self-review the diff, and run validate.sh; defined as a rule that applies after substantive work
* **PR review only** — rely entirely on PR reviewers to catch issues
* **Automated CI only** — run linters and tests in CI, skip local review

## Decision Outcome

Chosen option: **Structured review rule**, because it catches issues locally before they reach the PR. The linter agent handles mechanical quality checks while the self-review step catches logical and requirement gaps. The rule explicitly excludes trivial changes (docs-only, single-line fixes, config changes) to avoid overhead where review adds no value.

### Tradeoffs

* Good: reduces PR review cycles — reviewers focus on design, not style
* Good: validate.sh catches structural regressions before push
* Good: the exclusion for trivial changes keeps the process proportional
* Bad: adds time to every substantive implementation (offset by fewer PR revisions)

## More Information

* `rules/post-implementation-review.md` — the enforcing rule
* [ADR-015](015-validation-pre-push-gate.md) — validate.sh as pre-push gate
* AGENTS.md Post-Implementation Review section
