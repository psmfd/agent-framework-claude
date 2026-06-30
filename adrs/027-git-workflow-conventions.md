# ADR-027: Git workflow conventions — GitHub Flow, SemVer tagging, PR template standard

**Status:** Superseded by [ADR-028](028-dual-merge-strategy.md)
**Date:** 2026-04-01

## Context and Problem Statement

Cross-project git workflow conventions were undefined. Branching strategy, release tagging, and PR template structure were ad-hoc, leading to inconsistency across repositories. The agent framework and an internal service projects had organically adopted similar patterns (short-lived feature branches, squash merge, Conventional Commits) but these were not codified or enforceable.

## Considered Options

* **GitHub Flow variant + SemVer + standardized PR template** — GitHub Flow with `dev` as the integration branch and `main` as the stable/release branch, SemVer tags cut from `main`, and a required PR template structure across all repos
* **GitFlow** — separate `develop`, `release/*`, and `hotfix/*` branches with merge commits
* **Trunk-based development** — all commits land directly on a single branch with feature flags
* **Status quo** — no codified standard, rely on ad-hoc patterns

## Decision Outcome

Chosen option: **GitHub Flow variant + SemVer + standardized PR template**, because it matches the workflow already in use, keeps the branch model simple for solo/small-team projects, and provides release traceability via SemVer tags without requiring CI/CD automation.

The `dev`/`main` split (rather than canonical GitHub Flow's single `main`) separates ongoing integration work from release-tagged snapshots, which is valuable when releases are manual and infrequent.

### Tradeoffs

* Good: single workflow for all change types — no special hotfix or release branch mechanics
* Good: squash merge produces a clean, scannable log on `dev` with one commit per feature
* Good: SemVer tags on `main` create traceable links between deployed artifacts and source
* Good: standardized PR template sections give reviewers a consistent structure across repos
* Bad: `dev`/`main` split adds a promotion step that canonical GitHub Flow avoids
* Bad: squash merge limits `git bisect` granularity to per-PR, not per-commit
* Bad: manual tagging process requires discipline until CI/CD automation is adopted

## More Information

* Issue #88 — GitHub Flow branching strategy
* Issue #89 — SemVer release tagging convention
* Issue #90 — PR template standard
* [ADR-014](014-conventional-commits.md) — Conventional Commits format (referenced by version bump mapping)
* `rules/github-flow.md` — branching strategy rule
* `rules/semver-tagging.md` — tagging convention rule
* `rules/pr-template-standard.md` — PR template standard rule
