---
description: 'Use GitHub Flow branching with dev as integration branch, squash merge for features, merge commit for releases'
---

# GitHub Flow

All repositories in the ecosystem follow GitHub Flow: short-lived feature branches merged via PR into a single integration branch.

## Branches

- **`dev`** is the integration branch. All feature branches target `dev` via pull request. This is a deliberate deviation from canonical GitHub Flow, which uses `main`.
- **`main`** is the stable branch. Code reaches `main` only via release promotion from `dev`, never via direct PRs or commits.

## Branch Naming

Branch names follow `<type>/kebab-case-description` where `<type>` is a Conventional Commits type.

Valid prefixes: `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`, `test/`, `ci/`, `style/`.

The description should be lowercase, kebab-case, 2-5 words. Do not include ticket numbers unless the team convention requires them.

Examples: `feat/offline-cache`, `fix/bash-guard-write-ops`, `docs/readme-workflow-diagrams`.

Do not use `hotfix/`, `release/`, or `dev/` prefixes. All work follows the same branch-PR-merge flow regardless of urgency.

## Branch Lifecycle

1. Create from `dev`: `git switch dev && git pull && git switch -c <type>/description`
2. Keep branches short-lived. Target merge within 3 days. Branches open longer than 7 days are a review signal.
3. After merge, delete the branch (local and remote). In a squash-merge workflow the branch history is collapsed into one commit on `dev`, so the branch has no value after merge.

## Merge Strategy

The merge method depends on the PR target branch:

| PR target | Merge method | Why |
|-----------|-------------|-----|
| `dev` (feature branches) | **Squash and merge** | Produces one commit per feature for a clean, scannable log |
| `main` (release promotions from `dev`) | **Create a merge commit** | Preserves shared SHAs so `dev` and `main` do not diverge |

Do not use rebase merge for either target. Rebase rewrites SHAs and causes the same divergence problem as squash on promotion branches.

### GitHub Settings

In repository Settings > General > Pull Requests:

- Enable "Allow squash merging" — used for feature branches → `dev`
- Enable "Allow merge commits" — used for `dev` → `main` promotions
- Disable "Allow rebase merging"
- Enable "Default to PR title for squash merge commits" — ensures the squash commit message on `dev` follows Conventional Commits

The PR title must be a valid Conventional Commits message: `<type>(<scope>): <description>`. This is enforced by convention, not a hook.

### Why not squash for promotions?

Squash merge creates a new commit with a different SHA than the original commits on `dev`. Git treats these as unrelated changes, causing merge conflicts on every subsequent `dev` → `main` promotion. Merge commits preserve the shared history between branches.

## Branch Protection

Branch protection is enforced through **repository Rulesets** (not classic branch protection). Rulesets are GitHub's current mechanism: they apply to all actors — including repository administrators — unless explicit bypass actors are added, and they support a per-branch `allowed_merge_methods` constraint. This repo configures **no bypass actors**, so the rules apply to everyone including the solo maintainer (every change to `dev` and `main` goes through a PR).

### `dev` branch (ruleset `protect-dev`)

- Require a pull request before merging (0 required approvals)
- Allowed merge method: squash only
- Require linear history
- Block force pushes
- Block branch deletion
- Required status checks: `validate`, `lint-pr-title`, `artifact-review-guard`, `secrets-scan`, `zizmor`, `codeql`, `tests`, `bash32-compat` — `artifact-review-guard` blocks `.review/` handoff artifacts from merging (see `rules/artifact-handoff.md` and ADR-064); `secrets-scan` runs gitleaks (ADR-078); `zizmor` and `codeql` scan the workflows themselves (ADR-081); `tests` runs every `tests/*/run-tests.sh` suite and `bash32-compat` verifies the bash 3.2 floor on a macOS runner (ADR-083)

### `main` branch (ruleset `protect-main`)

- Require a pull request before merging (0 required approvals)
- Allowed merge method: merge commit only
- Block force pushes
- Block branch deletion
- Required status check: `validate`
- Do not require linear history — merge commits from `dev` → `main` promotions are not linear, and this setting would block them.

Required status checks are active now that CI exists. The `validate` job runs `validate.sh`; `lint-pr-title` enforces a Conventional Commits PR title. Because `validate.yml` runs on pull requests targeting both `dev` and `main`, the `validate` check reports on promotion PRs (whose head is `dev`) and can be required on `main`.

Two repository-level rulesets (`protect-dev` and `protect-main`) govern all actors — including the solo maintainer — with 0 required approving reviews and no inherited org or enterprise rulesets. Solo `dev` → `main` promotions take the normal PR path: open a PR from `dev` to `main`, wait for the `validate` required status check to pass, then merge. No owner bypass or additional approval is required. See [ADR-079](../adrs/079-branch-protection.md) and [ADR-056](../adrs/056-branch-protection-rulesets.md).

## What This Rule Does Not Cover

- **Release tagging** is covered by the SemVer tagging rule.
- **PR template structure** is covered by the PR template standard rule.
- **Commit message format** is covered by the Conventional Commits rule.
