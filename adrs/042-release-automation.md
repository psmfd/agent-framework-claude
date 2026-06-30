# ADR-042: Release Automation via semantic-release

**Status:** Accepted
**Date:** 2026-04-14

## Context and Problem Statement

The release process is entirely manual: version bumps, tag creation, changelog generation, and GitHub Release publishing all require manual steps. The SemVer tagging rule (ADR not numbered — predates formal ADR process) explicitly defers automation until CI/CD exists. With the agent framework at v1.0.2 and a stable dual-branch workflow (squash merge to `dev`, merge commit to `main`), the deferral can be lifted.

## Considered Options

* **Option A** — `semantic-release` on `main`, with `validate.sh` CI and PR title linting on `dev`
* **Option B** — `release-please` (Google) on `dev` or `main`
* **Option C** — Custom shell script for version bumping and tagging
* **Option D** — Status quo — continue manual releases

## Decision Outcome

Chosen option: **Option A**, because `semantic-release` is the only tool that natively supports the dual-branch merge strategy. `release-please` has a fundamental incompatibility: it scans commits on its target branch, but `dev` → `main` merge commits hide the Conventional Commits signals from `main`. `semantic-release` handles this correctly because merge commits preserve the original squash commit SHAs from `dev`, and `semantic-release` walks those commits to derive the version bump.

### Tradeoffs

* Good: fully automated version bumping, tagging, and GitHub Release creation after `dev` → `main` promotion
* Good: changelog included in GitHub Release body only — no commits pushed back to `main`, no deploy key or PAT needed
* Good: PR title linting ensures squash commits on `dev` are valid Conventional Commits, which semantic-release reads on `main`
* Good: `validate.sh` runs as a required status check on PRs targeting `dev`
* Bad: introduces Node.js as a CI dependency for a pure bash/markdown repo (semantic-release requires Node.js)
* Bad: `semantic-release` does not natively support pre-1.0 versioning (not a concern — repo is at v1.0.2)

### Workflow Architecture

Three GitHub Actions workflows:

* **`validate.yml`** — runs `validate.sh` on PRs targeting `dev` and on pushes to `dev`. Pure bash, no dependencies.
* **`release.yml`** — runs `semantic-release` on pushes to `main`. Creates annotated `v`-prefixed tags and GitHub Releases with generated changelog.
* **`lint-pr-title.yml`** — enforces Conventional Commits format on PR titles targeting `dev`. Uses `amannn/action-semantic-pull-request`.

The existing `merge-method-check.yml` (ADR-035) continues to warn about merge method on `dev` → `main` promotion PRs.

### Why not release-please?

`release-please` scans git commit history on its target branch. When configured on `main`, it only sees the `dev` → `main` merge commit — not the underlying `feat`/`fix` squash commits from feature branches. It cannot derive version bumps or changelog entries from a merge commit. Configuring it on `dev` would tag `dev` directly, violating the "tags from `main` only" convention.

### Why changelog in GitHub Release body only?

Writing `CHANGELOG.md` back to the repo requires `@semantic-release/git`, which pushes commits to `main`. This conflicts with branch protection (requires a deploy key or PAT to bypass) and creates noise in the commit history. The GitHub Release body is the natural location for changelogs — it is where users look for release notes.

## More Information

* Issue: #176
* Workflows: `.github/workflows/validate.yml`, `.github/workflows/release.yml`, `.github/workflows/lint-pr-title.yml`
* Config: `.releaserc.json`
* Supersedes: "Deferred Automation" section in `rules/semver-tagging.md`
* Related: ADR-028 (dual merge strategy), ADR-035 (merge method enforcement)
