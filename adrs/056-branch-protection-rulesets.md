# ADR-056: Branch Protection via Repository Rulesets

**Status:** Accepted
**Date:** 2026-05-28

## Context and Problem Statement

The repo had zero server-side branch protection — neither classic branch protection nor rulesets — on `dev` or `main`. The client-side guards this repo ships (the `gh-identity-guard` pre-push hook, the in-session `PreToolUse` guards) protect a developer's own machine but do nothing server-side: a force-push, a branch deletion, or a wrong-account direct push to the remote is unconstrained. This is acute for `main`, where any push triggers `semantic-release` and cuts a real SemVer tag plus GitHub Release; an accidental or wrong-account (the documented recurring identity-drift on this host, ADR-054) direct push to `main` would publish a release with no gate. `dev` is also load-bearing: `semantic-release` derives the version bump and changelog from `dev`'s Conventional Commits history, so a force-push to `dev` is an indirect attack on release integrity. CI now exists (`validate.yml`, `lint-pr-title.yml`), so the "defer required status checks until CI/CD exists" stance previously recorded in `rules/github-flow.md` is obsolete.

## Considered Options

* **Option A — Repository Rulesets** — express the `github-flow.md` protections as two rulesets (`protect-dev`, `protect-main`) with no bypass actors and required status checks.
* **Option B — Classic branch protection** — the legacy mechanism `github-flow.md` originally described.
* **Option C — Status quo** — no server-side protection; rely on convention and client-side hooks.

## Decision Outcome

Chosen option: **Option A**, because Rulesets are GitHub's current, actively-developed mechanism and give two things classic protection does not: a per-branch `allowed_merge_methods` constraint (so `dev` accepts squash-only and `main` accepts merge-commit-only, enforced at the API level), and a clean no-bypass model — rulesets apply to all actors including administrators unless bypass actors are explicitly added. Classic protection's "include administrators" toggle achieves a similar effect but lacks the per-branch merge-method control and is the legacy path. Option C is rejected: the client-side guards are not a server-side control, and an unprotected `main` is a release-integrity and auditability risk.

No bypass actors are configured. For a solo maintainer this means even the owner opens a PR for every change to `dev` and `main` — accepted deliberately, because the recurring wrong-account drift on this host (ADR-054) means an admin-bypass hole would let a drifted-but-admin account push directly to `main` and trigger a release. Required approving reviews are 0 (solo); the PR requirement still adds value (it is the only path that runs `lint-pr-title`, and it produces an audit trail and a CI gate). Required status checks are now active: `validate` + `lint-pr-title` on `dev`, `validate` on `main`. `validate.yml` was extended to run on PRs targeting `main` so the `validate` check reports on `dev` → `main` promotion PRs (whose head is `dev`) and can be required there.

### Tradeoffs

* Good: `main` cannot receive a direct or wrong-account push; force-push and deletion are blocked on both branches; released history is immutable and auditable.
* Good: the `validate` security gate (secrets-guard shellcheck, frozen-SHA pins, hook checks) and Conventional Commits title linting are enforced at merge, not advisory — this realizes the required-check design intent recorded in ADR-042.
* Good: per-branch merge-method enforcement makes the squash-for-dev / merge-commit-for-main convention structural, not just documented.
* Bad: no-bypass adds real friction for the solo maintainer — every change, however trivial, requires a PR and a passing `validate` run (~1 min). Emergency direct changes require temporarily setting a ruleset to `evaluate`/`disabled` or adding a bypass actor.
* Bad: required `validate` on `main` depends on `validate.yml` reaching `main` (via promotion) and on the promotion PR's head (`dev`) carrying the `main` trigger — a sequencing dependency, not a steady-state cost.
* Bad: merge-method *availability* (squash/merge/rebase buttons) is repo-wide; the ruleset restricts which method is *allowed* per branch but cannot hide the inapplicable button in the UI (cosmetic only — enforcement is real).

## More Information

* **Implementation** — repo rulesets `protect-dev` and `protect-main`; repo settings set `allow_rebase_merge=false`, `delete_branch_on_merge=true`, `squash_merge_commit_title=PR_TITLE`, `squash_merge_commit_message=PR_BODY`. Documented in `rules/github-flow.md` (and its Copilot instruction + web distillate mirrors).
* **Related** — ADR-042 (release automation; recorded the intent that `validate` run as a required check on PRs to `dev`); ADR-054 (two-layer client-side gh-identity guard — this ADR is the server-side complement); the 2026-05-28 currency review item on adopting Rulesets.
* **Possible follow-up** — raise required approvals to 1 when collaborators are added; consider required signed commits and Dependabot for Actions as further hardening.
