# ADR-079: Branch protection for agent-framework-claude

**Status:** Accepted
**Date:** 2026-06-29

## Context and Problem Statement

The predecessor's `main` carried an inherited enterprise-baseline ruleset (from an external enterprise) that forced approving reviews, last-push approval, and linear
history, making solo `dev`→`main` promotions require a per-merge owner bypass
(predecessor ADR-068, not carried). This repo lives in the personal `psmfd` org.
Reconnaissance confirmed `psmfd` has **no org-level rulesets** (`gh api
orgs/psmfd/rulesets` → `[]`), so no enterprise/org constraint is inherited here.

## Considered Options

* **Two repo-level rulesets, no forced review** — `protect-dev` and `protect-main`
  configured directly on the repo, requiring PRs and status checks but zero approving
  reviews, allowing clean solo promotion.
* **Mirror the predecessor's constraints** — replicate forced reviews/linear history
  on `main`. Rejected: nothing inherited forces it, and it would re-impose the
  owner-bypass friction for no benefit on a solo repo.

## Decision Outcome

Chosen option: **Two repo-level rulesets, no forced review**, following
[ADR-056](056-branch-protection-rulesets.md). `protect-dev`: require a PR (0 reviews),
squash-only merges, linear history, block force-push and deletion, required checks
`validate` + `lint-pr-title` + `artifact-review-guard` + `secrets-scan`. `protect-main`:
require a PR (0 reviews), merge-commit-only, block force-push and deletion, required
check `validate`; linear history deliberately omitted so `dev`→`main` merge commits
are allowed. Because nothing is inherited, solo promotions merge on the normal path
with no owner bypass. This decision is revisited if `psmfd` later joins an enterprise
or gains org rulesets, or when collaborators are added (introduce a `CODEOWNERS`
file and required reviews then).

### Tradeoffs

* Good: clean solo promotion; no owner-bypass ceremony; still gates every change
  behind a PR and CI.
* Bad: zero required reviews offers no second-set-of-eyes gate. Accepted while
  solo-maintained; the policy explicitly flags the collaborator-time revision.

## More Information

Follows [ADR-056](056-branch-protection-rulesets.md). Adds the `secrets-scan` check
from [ADR-078](078-ci-security-gitleaks.md) to the `dev` required set. Driven by
[ADR-076](076-claude-only-successor-genesis.md). Replaces the relevance of
predecessor ADR-068 (inherited enterprise ruleset, not carried).
