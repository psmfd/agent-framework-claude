# ADR-052: GitHub Identity Preflight Guard for Work-Item Scripts

**Status:** Superseded by [ADR-054](054-gh-identity-enforcement-layers.md)
**Date:** 2026-05-26

## Context and Problem Statement

On a host authenticated to more than one GitHub account, `gh` authenticates as the globally-active account recorded in `hosts.yml` and never auto-selects an account from a repository's remote owner. When the active account differs from the account that can access the target repository, every `gh` call fails with `Could not resolve to a Repository` — a 404-shaped error that does not name the real cause. The frozen work-item driver (`scripts/wim/apply-manifest.sh`, GitHub backend) inherits this failure: it walks the Epic → Feature → Story tree issuing `gh issue create` calls, so a wrong active account produces a scatter of cryptic per-call errors, potentially after partial writes. This was observed directly in this repo (remote owner `a sandbox org`, owning account `account-a`, active account `account-b`) and is tracked by issue #172.

A correct guard cannot compare the active account login to the repository owner: repositories are frequently org-owned, so the owning account login rarely equals the owner string even when access is correct. The signal must be repository *accessibility*, not a name match.

## Considered Options

* **Option A — Blocking preflight in the frozen driver + non-fatal `validate.sh` warning** — `apply_gh()` calls a `gh_preflight_identity` helper (in `_lib.sh`) that tests `gh api repos/{owner}/{repo}` before any writes and `die`s with an actionable `gh auth switch` hint on failure. `validate.sh` runs the same probe as a `WARN` against the `origin` remote. Re-author the two frozen scripts and re-pin their SHAs per ADR-050's legitimate-update path.
* **Option B — Non-fatal warning only** — emit an early `WARN` in the driver but continue; the subsequent `gh` calls still fail on their own. No ADR threshold met.
* **Option C — Documentation only** — describe the multi-account identity model and rely on operator discipline; no code guard.

## Decision Outcome

Chosen option: **Option A**, because the whole value of the guard is preventing a partial run under the wrong identity. A non-fatal warning (Option B) lets the driver proceed into the failing `gh issue create` calls it was meant to prevent, and documentation alone (Option C) does not change runtime behavior. Blocking before the first write turns a scatter of cryptic 404s into one message that names the corrective `gh auth switch <account>` command.

The guard uses accessibility (`gh api repos/{owner}/{repo} --silent` exit code) as the signal, not a login-vs-owner string comparison, because org-owned repositories make the latter wrong by construction. On failure it probes the other authenticated accounts (via `gh auth token --user`, without switching) to name the account that works; if none can be identified it emits a generic `gh auth status` / `gh auth login` hint. It honors `GH_TOKEN`/`GITHUB_TOKEN` environment overrides and is scoped to `github.com`.

The two layers carry different severities deliberately. The driver guard is a fatal `ERROR` (fail-fast, exit 1) because it gates a write operation. The `validate.sh check_gh_identity` is a non-fatal `WARN` and is skipped when a token is in the environment, because `validate.sh` runs in CI where the active identity is a bot token, not a developer's account — a fatal check there would fail every CI run.

### Relationship to ADR-050 (frozen scripts)

This is the first re-authoring of a frozen script since ADR-050. ADR-050's prohibition ("MUST NOT edit ... under any circumstances") is an *agent-behavioral* constraint binding the `work-item-management-expert` when it *uses* the suite to create work items — it prevents an instruction-following agent from rationalizing edits or generating replacement scripts. It is not a prohibition on framework maintainers *improving* the suite through reviewed change. ADR-050 itself, the `.frozen-shas` header, and the Documentation Sync Map all define the legitimate-update path: re-author through PR review, then update the SHA pin in the same commit. This change follows that path — `_lib.sh` and `apply-manifest.sh` are re-pinned in `scripts/wim/.frozen-shas`, and `validate.sh check_frozen_scripts` enforces the new hashes. The guard hardens the trusted execution surface rather than expanding the agent's write latitude.

### Tradeoffs

* **Good:**
  * One clear, actionable error before any write, instead of cryptic post-hoc 404s and a possible partial tree.
  * Accessibility-based check is correct for org-owned repositories, where a login-vs-owner match would false-positive.
  * `validate.sh` surfaces the same condition early for any `gh`-backed tooling, scoped to avoid CI noise.
  * Re-pinning keeps the frozen guarantee intact and visible in the diff.

* **Bad:**
  * One extra `gh api` round-trip before the manifest run (negligible against a bulk tree creation).
  * The account-probe path parses `gh auth status`, whose human-readable format is not a stable API; parsing is best-effort and degrades to a generic hint if the format changes.
  * The guard covers the `apply-manifest.sh` driver path; direct invocation of `create-*.sh` is not guarded (the documented flow routes through the driver). A follow-up could extend coverage if direct invocation becomes common.
  * GHES remotes and SSH host-alias remotes are out of scope for the `validate.sh` check.

## More Information

* **Issue** — a tracking issue (#172) (filed as a tracking issue (#172)). Related to #238 (documenting general multi-account `gh auth` patterns in `gh-cli-expert`); this ADR scopes the wim-suite-specific guard, cross-referenced rather than duplicated.
* **Frozen-script convention** — ADR-050. Re-pin path: `scripts/wim/.frozen-shas` + `validate.sh check_frozen_scripts`.
* **Operator documentation** — `docs/multi-account-git-identity.md` (three-layer identity model: commit identity via gitconfig `includeIf`, transport credential via SSH host-alias or `gh auth git-credential`, `gh auth switch` active account).
* **Output convention** — guard and check follow `rules/script-output-conventions.md` (`ERROR`/`WARN [gh-identity]` labels). ADR-034 records the originating convention.
* **Tests** — `tests/wim/run-tests.sh` adds a failure-path assertion (active account cannot resolve the manifest repo ⇒ driver exits 1 with `gh-identity`, before any `issue create`), using a `GH_SHIM_DENY_REPO` hook in the `gh` shim.
