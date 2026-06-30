# ADR-035: Merge method enforcement for dev-to-main promotions

**Status:** Accepted
**Date:** 2026-04-08

## Context and Problem Statement

The `github-flow.md` rule specifies squash merge for feature branches and merge commit for `dev` → `main` promotions. GitHub repo settings control which merge methods are available but cannot enforce a specific method per target branch. Accidental squash-merges on promotion PRs rewrite SHAs, causing persistent merge conflicts between `dev` and `main`. This failure mode has occurred repeatedly in `an internal service repo`, requiring manual reconciliation merges.

## Considered Options

* **Option A** — GitHub Action that posts a reminder comment and adds a `promotion` label on PRs targeting `main` from `dev`
* **Option B** — Branch ruleset enforcing merge strategy per branch (requires GitHub Team/Enterprise plan)
* **Option C** — Pre-merge CI check that blocks merge if the PR does not match the promotion pattern
* **Option D** — Documentation and PR template warning only, relying on human discipline

## Decision Outcome

Chosen option: **Option A supplemented by Option D**, because the GitHub Action provides automated, visible reminders at the point of action without requiring a paid plan. The PR template adds a standing reference for all PRs regardless of target branch. Option B is not available on the free plan. Option C was considered but a blocking status check adds friction to all PRs targeting `main`, not just promotions from `dev`.

### Tradeoffs

* Good: automated reminder on every promotion PR, no paid plan required, low maintenance, `promotion` label provides visual signal in the PR list
* Bad: cannot block the wrong merge method — only reminds. A distracted merge with the wrong button is still possible. Upgrade to Option B if the repo moves to a paid plan.

## More Information

- [GitHub Flow rule](../rules/github-flow.md) — documents the merge strategy and failure mode
- #104 — tracking issue
