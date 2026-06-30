# ADR-028: Dual merge strategy — squash for feature branches, merge commit for release promotions

**Status:** Accepted
**Date:** 2026-04-01

## Context and Problem Statement

ADR-027 mandated squash merge for all PRs and required linear history on both `dev` and `main`. When feature branch PRs are squash-merged to `dev`, and then `dev` is squash-merged to `main`, the resulting commit on `main` has a different SHA than the commits on `dev`. Git treats these as unrelated changes, causing merge conflicts on every subsequent `dev` → `main` promotion. This was observed repeatedly in the internal service repository (PRs #30, #31, #32), requiring manual reconciliation merges each time.

## Considered Options

* **Dual merge strategy** — squash merge for feature branches → `dev`, merge commit for `dev` → `main` promotions
* **Rebase and fast-forward for promotions** — rebase `main` onto `dev` to maintain linear history without SHA divergence
* **Status quo (squash everything)** — continue squash-merging `dev` → `main` and reconcile divergence manually each time

## Decision Outcome

Chosen option: **Dual merge strategy**, because it preserves squash merge benefits on `dev` (clean one-commit-per-feature log) while preventing SHA divergence on `main`. Merge commits for release promotions are a natural boundary marker and their non-linear history is expected for integration branches.

Rebase was rejected because it rewrites `dev` commit SHAs when applied to `main`, producing the same divergence problem from the other direction. It also requires force-pushing `main` if the branches have diverged at all, which violates branch protection rules.

### Tradeoffs

* Good: eliminates recurring merge conflicts on `dev` → `main` promotions
* Good: `dev` retains clean linear history from squash merges
* Good: merge commits on `main` serve as clear release boundary markers
* Bad: `main` history is no longer strictly linear — "Require linear history" must be removed from `main` branch protection
* Bad: requires contributors to select the correct merge method per PR target (squash for `dev`, merge commit for `main`)

## More Information

* Supersedes [ADR-027](027-git-workflow-conventions.md) (merge strategy and branch protection sections only — branching model, SemVer tagging, and PR template standard remain unchanged)
* Observed in an internal service: PRs #30, #31, #32 required manual `main` → `dev` reconciliation merges after each squash-merged promotion
* `rules/github-flow.md` — updated to reflect dual merge strategy
