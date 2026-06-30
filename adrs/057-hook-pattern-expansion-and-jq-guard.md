# ADR-057: Expanded Token Coverage and Fail-Closed jq Guard for In-Session Hooks

**Status:** Accepted
**Date:** 2026-05-29

## Context and Problem Statement

The lockstep secret-pattern hooks (`hooks/secrets-guard.sh` + `hooks/session-secrets-guard.sh`, ADR-053) detected only two of GitHub's five documented token prefixes — `ghp_` (classic PAT) and `github_pat_` (fine-grained PAT) — missing `gho_`, `ghu_`, `ghs_`, and `ghr_`. The omission of `ghs_` is the most consequential: it is the prefix of the GitHub Actions `GITHUB_TOKEN`, the single most common accidental CI secret. The sensitive-path checks also missed the OpenSSH 8.2+ hardware-backed key basenames `id_ecdsa_sk` / `id_ed25519_sk` (#211). Separately, both in-session hooks (`session-secrets-guard.sh`, `session-gh-identity-guard.sh`) parse tool input with `jq` guarded only by `2>/dev/null || true`; when `jq` is absent the parse yields an empty string, the tool-name self-filter falls through to its default allow case, and the entire in-session security layer silently disables — a fail-open hole in a fail-closed design (#212).

These are corrections to enumerated detail and a hardening of the fail posture; the in-session-hook architecture chosen in ADR-053 and the two-layer identity guard of ADR-054 are unchanged.

## Considered Options

* **Option A** — Extend the token alternation to `gh[oprsu]_` with an open-ended body bound, add the `_sk` basenames, and add a `command -v jq` fail-closed guard to both in-session hooks. Record as a new ADR citing ADR-053/ADR-054 as prior art.
* **Option B** — Same code changes, but supersede ADR-053 (and annotate ADR-054).
* **Option C** — Add the `gh*_` prefixes with a fixed `{36}` body (matching the old `ghp_` form) and leave the `jq` path as-is.

## Decision Outcome

Chosen option: **Option A.**

**Token prefixes and body length.** Detect `gh[oprsu]_` — the explicit five-prefix set (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`) rather than `gh[a-z]_`, which would match prose tokens like `ghz_` for negligible benefit. The body bound is open-ended (`gh[oprsu]_[A-Za-z0-9]{36,}`, `github_pat_[A-Za-z0-9_]{82,}`) rather than fixed, because GitHub treats tokens as opaque and is rolling out a new stateless `ghs_` installation-token format (~520 characters, variable; staged rollout from 2026-04-27). A fixed `{36}` would silently fail to match newly issued Actions tokens — exactly the highest-impact case — so Option C is rejected. The lower bound (`{36}`, `{82}`) is retained to suppress false positives on short identifiers. POSIX ERE open-ended intervals (`{m,}`) are portable across BSD grep (macOS), GNU grep (Debian), and `ugrep`.

**FIDO2 SK keys.** Add `id_ecdsa_sk` / `id_ed25519_sk` to the `is_sensitive_path()` basename lists in both hooks and to `BASH_SENSITIVE_PATH_RE` in `session-secrets-guard.sh`. No explicit `.pem` arm is added for the `_sk` names — the existing `*.pem` glob already covers them.

**Fail-closed on missing jq.** Each in-session hook gains a `command -v jq` check after the announced `SKIP_*` bypass and the empty-input exit, before the first `jq` call. A missing `jq` is treated as an indeterminate state and denied (exit 2), mirroring "a secrets guard must not be defeatable by a malformed payload" (ADR-053) and "fail CLOSED on indeterminate identity" (ADR-054). The pre-commit `secrets-guard.sh` and pre-push `gh-identity-guard.sh` use no `jq` and already guard their `git`/`gh` dependencies, so they are unchanged.

**ADR form.** A new ADR, not supersession. ADR-053's decision (a `PreToolUse` bash hook, lockstep-duplicated pattern set, split fail posture) and ADR-054's decision (two-layer hybrid-signal identity guard) both still describe current behavior. Marking either Superseded would freeze its body and mislead a reader into thinking the architecture it documents is obsolete, which it is not. The `#211` acceptance note's "superseded or annotated" is satisfied by annotation: this ADR records the amendment and cites the prior decisions. Option B is therefore rejected.

### Tradeoffs

* Good: closes the silent fail-open on missing `jq`; detects the high-impact `ghs_` Actions token and the other three prefixes; future-proofs against GitHub's growing token lengths; covers hardware-backed SSH keys.
* Good: keeps ADR-053/ADR-054 honest as live records of unchanged architecture.
* Bad: a host without `jq` has both in-session hooks deny every gated tool call until `jq` is installed or an announced `SKIP_*` bypass is set — an accepted denial-of-availability tradeoff. The hooks' deny messages name the cause and the `apt install jq` / `brew install jq` / `SKIP_*=1` remediation so a blocked user has immediate guidance.
* Bad: the open-ended `{36,}` bound slightly widens the false-positive surface versus a fixed length, mitigated by the mandatory `gh[oprsu]_` / `github_pat_` prefix anchor.

## More Information

* Amends [ADR-053](053-session-secrets-interception.md) (in-session secrets interception) and [ADR-054](054-gh-identity-enforcement-layers.md) (gh-identity enforcement layers); supersedes neither.
* Issues: #211 (token-prefix and FIDO2-SK coverage), #212 (jq-absent fail-open).
* Companion (not in scope here, same lockstep hook pair): #176 (staged-blob scan).
* GitHub token formats: <https://github.blog/engineering/platform-security/behind-githubs-new-authentication-token-formats/>; new `ghs_` installation-token format rollout: <https://github.blog/changelog/2026-04-24-notice-about-upcoming-new-format-for-github-app-installation-tokens/>.
