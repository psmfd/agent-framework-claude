# ADR-078: CI secret-scanning via inlined gitleaks

**Status:** Accepted
**Date:** 2026-06-29

## Context and Problem Statement

The repository starts private and is intended to go public, so it needs CI-side
secret scanning to complement the local pre-commit and in-session secrets guards
([ADR-059](059-secrets-guard-staged-blob-scan.md),
[ADR-053](053-session-secrets-interception.md)). The `psmfd` org has no shared
reusable-workflow library and no `psmfd/.github` repo; reconnaissance confirmed zero
`on: workflow_call` workflows across the org. GitHub also blocks public repositories
from calling a private org's reusable workflows, which is why the org's reference
pattern (in `a sibling repo`) inlines the scanner rather than sharing it.

## Considered Options

* **Inline gitleaks** — copy the org's `psmfd-secrets-scan.yml` pattern: a gitleaks
  scan via a SHA-pinned public container image, self-contained, no secrets or inputs,
  pointed at the repo's own `.gitleaks.toml`.
* **Reusable workflow `uses:` reference** — call a shared org workflow. Rejected: none
  exists, and public→private reusable calls are blocked by GitHub.
* **CodeQL code scanning** — rejected as the primary control: this is a
  shell/YAML/Markdown repo; CodeQL adds nothing for these languages.

## Decision Outcome

Chosen option: **Inline gitleaks**, matching the established `psmfd` convention. The
repo carries its own `.gitleaks.toml` and a `secrets-scan` workflow running the
SHA-pinned gitleaks container ([ADR-055](055-sha-pin-third-party-actions.md)) on
push and pull request. At the public flip, GitHub-native secret scanning with push
protection and Dependabot alerts are enabled (free on public repos); CodeQL is
deliberately omitted as inapplicable. Together these give layered coverage:
local guards before commit, gitleaks over history in CI, and native scanning on the
remote.

### Tradeoffs

* Good: language-agnostic, no secrets/inputs, consistent with the org pattern.
* Good: works identically while private and after the public flip.
* Bad: the scanner config is duplicated rather than shared. Accepted — it is the
  org-wide convention and GitHub's reusable-workflow constraints make sharing
  impractical for public repos.

## More Information

Complements [ADR-059](059-secrets-guard-staged-blob-scan.md) and
[ADR-053](053-session-secrets-interception.md). Driven by
[ADR-076](076-claude-only-successor-genesis.md). Action pinning per
[ADR-055](055-sha-pin-third-party-actions.md).
