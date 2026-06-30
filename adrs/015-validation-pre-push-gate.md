# ADR-015: validate.sh as a pre-push hard gate

**Status:** Accepted
**Date:** 2026-03-24

## Context and Problem Statement

The three-file pattern, frontmatter constraints, platform field isolation, and tool allowlists are easily broken during development. A broken skill that reaches the repo propagates to all consuming platforms via symlinks. Manual review alone is insufficient — reviewers miss structural issues that a script can catch reliably.

## Considered Options

* **Pre-push hook** — `setup.sh` installs a git pre-push hook that runs validate.sh; exit code 1 blocks the push
* **CI-only** — run validation in CI after push; broken commits can land but are flagged
* **Manual** — rely on contributors to run validate.sh before pushing

## Decision Outcome

Chosen option: **Pre-push hook**, because it catches errors before they reach the repo. A broken push that passes CI-only would still be visible to other consumers during the review window. The pre-push hook provides an immediate local gate.

### Tradeoffs

* Good: broken skills never reach the remote repo — errors are caught locally
* Good: zero manual discipline required — the hook runs automatically
* Bad: the hook adds latency to every push (currently <2 seconds, acceptable)
* Bad: contributors must run `setup.sh` to install the hook — a cloned repo without setup has no gate

## More Information

* [ADR-004](004-three-file-pattern.md) — three-file pattern that validation enforces
* [ADR-012](012-symlink-distribution.md) — symlink distribution that propagates any committed errors
* `validate.sh` — the validation script
* `setup.sh` — installs the pre-push hook
* CONTRIBUTING.md Validation section
