# ADR-054: Fail-Closed GitHub Identity Enforcement Layers

**Status:** Accepted
**Date:** 2026-05-27
**Note:** The in-session `GH_IDENTITY_OVERRIDE` clause is superseded by [ADR-070](070-guard-hardening-symlink-override.md) (env var only; the command-string prefix form is no longer honored). The two-layer design otherwise stands.
**Supersedes:** [ADR-052](052-gh-identity-preflight-guard.md)

## Context and Problem Statement

ADR-052 established a GitHub identity guard for the work-item driver plus a non-fatal `validate.sh` warning, both using repo *accessibility* (`gh api repos/{owner}/{repo}`) as the signal. That posture is deliberately advisory: it catches the wrong active account before the wim driver writes, and warns in CI, but it does not block an ordinary `git push` or a mutating `gh` call issued from an agent session or a plain terminal. During the work on this epic the active account silently flipped from `account-a` to `account-b` multiple times within a single session, producing `Could not resolve to a Repository` errors and, absent a guard, would have allowed a wrong-account mutation. A warn-only posture is insufficient for an error class whose remediation (force-push, history rewrite, secret-in-wrong-repo) is expensive and sometimes impossible.

A second gap: the wim-driver guard only covers the `apply-manifest.sh` path. `git push` and `gh` mutations from agent `Bash` tool calls, plain terminals, IDE git clients, and scripts are unguarded.

## Considered Options

* **Option A — two fail-closed layers (in-session `PreToolUse` hook + git pre-push hook), hybrid signal.** A `PreToolUse` hook (`session-gh-identity-guard.sh`) denies mutating `gh`/`git push` agent calls; a git pre-push hook (`gh-identity-guard.sh`) blocks any `git push` regardless of how it is invoked. Signal: a committed `.gh-expected-identity` pin file (strict login compare) when present, else accessibility fallback. Retain ADR-052's `validate.sh` warning as an early signal.
* **Option B — in-session layer only.** Catches agent calls but misses raw-terminal/IDE pushes — the exact vector the multi-account incident also occurs through.
* **Option C — pre-push layer only.** Catches all `git push` but no non-push `gh` mutations (`gh issue create`, `gh pr merge`, `gh api -X POST`), which are exactly what the wim flow emits.
* **Option D — keep ADR-052 warn-only.** No behavioral change; the incident recurs.
* **Signal sub-decision — accessibility vs pinned login vs hybrid.** Accessibility (ADR-052) passes if a wrong-but-also-authorized account can reach the repo. A pinned login catches that case but needs a per-repo file. Hybrid uses the pin when present and falls back to accessibility otherwise.

## Decision Outcome

Chosen option: **A, with the hybrid signal.** Both layers are necessary and each closes a gap the other cannot: the `PreToolUse` hook is the only structural gate for non-push `gh` mutations during an agent session; the pre-push hook is the only gate for `git push` issued outside any agent. Fail-closed is correct given the cost asymmetry — a false block is a 10-second `gh auth switch` or an override; a false allow is a wrong-account push.

The hybrid signal is chosen over accessibility-only because the observed incident is an account *flip*, and on repos where both accounts can read the target an accessibility probe would not detect it; it is chosen over a *required* pin because that would block every consuming repo until a file is committed, creating friction that drives users to disable the guard. The pin is therefore optional in general and **committed for this repo** (`.gh-expected-identity` = `account-a`), so the strict layer is active here while the framework remains usable elsewhere out of the box.

The in-session hook fails open for non-mutating commands by construction: a cheap string pre-check runs before any identity probe, so only `git push` / mutating `gh` calls are ever gated or slowed. Under `GH_TOKEN`/`GITHUB_TOKEN` (CI/bot), both layers verify repo access under the token instead of comparing logins, so CI pushes (which carry `GITHUB_TOKEN`) are not broken. Three announced overrides are provided: per-invocation `GH_IDENTITY_OVERRIDE=<login>` (validated against the gh username regex), a `.gh-identity-allowlist` command-substring file, and the session-wide `SKIP_GH_IDENTITY_GUARD=1`.

ADR-052's `validate.sh check_gh_identity` warning is retained unchanged as an early-development signal (layer 0). This ADR supersedes ADR-052 because it changes the enforcement posture (warn-only → fail-closed) and widens coverage from the wim driver to all `gh`/`git push` surfaces; per the supersession-not-editing rule, ADR-052's body is unchanged and only its status line is updated.

### Tradeoffs

* **Good:** closes the in-session and raw-shell wrong-account vectors with one clear message before any remote write; hybrid signal catches account flips a pure-accessibility check misses; reuses the established `PreToolUse` + `.github/hooks` cross-platform delivery; CI-safe via the token carve-out.
* **Bad:**
  * Identity logic is duplicated across the two bash hooks (no shared sourced lib, to avoid the option-state and symlink-resolution hazards of sourcing in a hook context) — kept in lockstep by comment.
  * A network round-trip (`gh api user`, and the accessibility probe) on each mutating op; negligible against push/mutation frequency, bounded by the 10 s hook timeout.
  * The in-session hook checks against `origin`; a push to a non-origin remote is verified by the pre-push hook, not in-session.
  * Accepted detection gaps: shell aliases, env-var-constructed command strings, and `curl` carrying a `gh auth token`. The pre-push hook backstops all `git push` vectors regardless.
  * Committing `.gh-expected-identity` pins this repo to one login; other authorized accounts must use an override.

## More Information

* **Issue** — a tracking issue (#184) (Phase A of epic #181); the in-session secrets hook #183 (ADR-053) established the `PreToolUse` delivery pattern reused here.
* **Prior art** — `a sibling repo` `agent/extensions/gh-identity-guard/` + `hooks/gh-identity-guard.sh` (ADR-0022): the donor two-layer design and the `extract_host`/`is_valid_login`/override patterns adapted here.
* **Rule** — `rules/gh-identity-guard.md` + `copilot/instructions/gh-identity-guard.instructions.md` document the behavior and overrides.
* **Operator documentation** — `docs/multi-account-git-identity.md`.
* **Output convention** — `rules/script-output-conventions.md`.
* **Relationship to ADR-052** — supersedes it; the `validate.sh` warning from ADR-052 is retained as the layer-0 early signal.
