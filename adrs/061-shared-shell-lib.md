# ADR-061: shared shell helper library (scripts/lib/)

**Status:** Accepted
**Date:** 2026-05-29

## Context and Problem Statement

The output helpers mandated by `rules/script-output-conventions.md` (`ok`/`skip`/`warn`/`info`/`err`/`detail`) are copy-pasted into seven scripts (`validate.sh`, `hooks/secrets-guard.sh`, `hooks/gh-identity-guard.sh`, `scripts/setup-repo.sh`, the frozen `scripts/wim/_lib.sh`, and two test runners), and four divergent verbosity variables are in use (`VALIDATE_VERBOSE`, `SECRETS_GUARD_VERBOSE`, `WIM_VERBOSE`, `VERBOSE`). ADR-051 defines the output convention but no shared source implements it, and there is no isolated, network-free test surface for shared shell logic. The constraint that makes this non-obvious: the highest-value consumers cannot all share one source — the security hooks are installed standalone into `.git/hooks/` (a relative `source` cannot resolve), and `validate.sh` cannot depend on a library it is itself responsible for testing.

## Considered Options

* **Option A** — A `scripts/lib/` of sourced helper modules, each bash-3.2-safe with a `--self-test` mode, wired into `validate.sh`; migrate only the scripts that can safely source it.
* **Option B** — A single flat `lib/log.sh` only (the narrower #161 scope), no module directory, no `git` helpers.
* **Option C** — Status quo: keep copy-pasting the helper block into every script.

## Decision Outcome

Chosen option: **Option A**, because it gives one canonical source for the convention plus a deterministic, network-free self-test gate, without forcing the consumers that legitimately cannot share a source to do so.

Scope and rules:

* **Modules shipped now: `scripts/lib/log.sh` and `scripts/lib/git.sh`.** `path.sh` is deferred — no current script has path logic beyond the one-line `cd "$(dirname "$0")" && pwd` idiom, so a `path.sh` would ship with no caller and an inherently vacuous self-test. It will be added when a real caller needs it.
* **The libs never set shell options** (`set -euo pipefail`) — the caller owns them, matching the frozen `scripts/wim/_lib.sh` precedent. They are POSIX/bash-3.2-safe so `setup.sh` and `scripts/setup-repo.sh` (which run on macOS system bash 3.2) can source them.
* **The libs own their counters** (`LOG_ERROR_COUNT`/`LOG_WARN_COUNT`, incremented by `warn`/`err`). This differs from `validate.sh`'s caller-owned counters, but `validate.sh` does not source the lib (see exclusions), so the consumers that do source it benefit from counter ownership the way the wim suite does.
* **`--self-test` contract:** each module, when executed directly (`bash scripts/lib/<m>.sh --self-test`), runs assertions, writes all diagnostics to **stderr only** (so a caller capturing stdout is unaffected), and exits `0` on pass / non-zero on fail. `validate.sh`'s `check_lib_selftests` runs each module as a **subprocess** (never sourced), so validate.sh's own bash-4.0 floor does not constrain the bash-3.2-safe libs. Self-tests must be non-vacuous: they assert exact format strings and that `warn`/`err` route to stderr.
* **Verbosity is unified on `VERBOSE=1`** for `detail()`, consistent with the existing `--verbose`/`detail` convention. The four legacy variables are untouched in this PR (their scripts are not migrated here).

Exclusions (deliberate, not oversights):

* **Security hooks** (`hooks/secrets-guard.sh`, `hooks/gh-identity-guard.sh`, `hooks/session-*.sh`) are **not** migrated. They are installed standalone into `.git/hooks/`, and ADR-053/ADR-054 chose pattern-duplication-with-a-lockstep-comment over a shared source precisely to avoid sourcing hazards in the hook context. This ADR does not supersede them.
* **Frozen wim scripts** (`scripts/wim/*.sh`) are exempt per ADR-050 (SHA-pinned).
* **`validate.sh`** keeps its own inline helpers — it is the one script that cannot depend on the lib it tests (bootstrap hazard).
* **Migration in this PR is limited to `scripts/scaffold.sh` and `scripts/setup-repo.sh`.** Broader migration is deferred to a follow-up so the diff stays reviewable.

This decision is **additive to ADR-051** — it implements the helpers ADR-051 specifies — and supersedes nothing.

### Tradeoffs

* Good: one canonical source for the output helpers; a deterministic, network-free self-test surface enforced by both the shellcheck gate (extended to `scripts/lib/*.sh`) and the new `check_lib_selftests` gate in `validate.sh`.
* Good: the libs are bash-3.2-safe, so they are usable by every framework script including the macOS-system-bash callers.
* Bad: a second sourced-lib pattern now coexists with the frozen `scripts/wim/_lib.sh` until (or unless) the wim suite is unfrozen and consolidated.
* Bad: the security hooks remain duplicated by design, so the lib does not eliminate every copy of the helper block — the convention is "source the lib unless a standalone-deployment or frozen constraint applies."

## More Information

* Issue #192 (this change); issue #161 (narrower `lib/log.sh` story — **subsumed** by this work, its log.sh scope delivered here); issue #99 (setup.sh `--non-interactive`, related, deferred).
* `rules/script-output-conventions.md` — the convention these helpers implement; amended to reference `scripts/lib/` as the source.
* ADR-050 (frozen wim scripts), ADR-051 (diagnostic output to stderr), ADR-053 / ADR-054 (security-hook no-shared-source decisions).
