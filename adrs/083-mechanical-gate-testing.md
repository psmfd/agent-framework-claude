# ADR-083: Mechanical enforcement of the bash 3.2 floor and hook-pair lockstep

**Status:** Accepted
**Date:** 2026-07-02

## Context and Problem Statement

Two of the framework's reliability guarantees were enforced by comment and
developer discipline only. First, `setup.sh`, `hooks/*.sh`, and
`scripts/lib/*.sh` must stay compatible with macOS system bash 3.2.57, but CI
runs bash 5.x throughout, so nothing mechanically verified the floor — and
`bash -n` cannot: bash-4-isms like `declare -A` are syntax-valid and fail only
at runtime on 3.2. Second, the guard-hook pairs deliberately duplicate their
pattern sets and helper functions (ADR-053/ADR-054: no shared source for
security-critical hooks) with "keep in lockstep" comments, but nothing checked
the copies stayed identical — drift in one hook silently weakens its layer.
Separately, four of the eight hooks and `validate.sh` itself had no regression
test coverage at all.

## Considered Options

* **Option A** — macOS CI runner (real `/bin/bash` 3.2) + fixture test suites
  per hook + an ERROR-gated lockstep check in `validate.sh`
* **Option B** — `bash:3.2` Alpine container job for the floor; otherwise as A
* **Option C** — static-only enforcement (shellcheck, `bash -n`, `dash -n`)
* **Option D** — status quo (comments and discipline)

## Decision Outcome

Chosen option: **Option A**.

* **Bash 3.2 floor:** a CI job on a GitHub-hosted macOS runner executes the
  3.2-targeted surfaces under Apple's actual `/bin/bash` 3.2.57 — the exact
  binary the constraint targets — via `scripts/check-bash32.sh` (lib
  self-tests, syntax checks, hook smoke invocations, and the 3.2-safe test
  suites). macOS runners are free on public repositories and add no image or
  digest pinning surface. Option B remains the documented fallback if runner
  economics change: `docker.io/library/bash:3.2.57-alpine*` is actively
  rebuilt, but it is musl/busybox (not macOS userland), ships no git/jq, needs
  a committed Dockerfile plus a `dependabot.yml` docker entry (Dependabot does
  not scan image refs embedded in workflow YAML). Option C was rejected on
  evidence: shellcheck has no bash-version target, `bash -n` passes
  runtime-only 3.2 breaks, and `dash -n` rejects the legitimate bashisms
  (`[[ ]]`, arrays) these scripts use by design.
* **Lockstep:** `validate.sh check_lockstep_duplication` extracts
  `SECRET_PATTERNS`, `GH_LOGIN_RE`, `sanitize`, `is_valid_login`, and
  `parse_owner_repo` from each hook pair by convention-based `grep`/`awk`
  (single-line `NAME=` assignments; function bodies closed by a lone `}` at
  column 0) and ERRORs on any byte difference. The extractor fails loudly when
  a target is not found in its expected shape, so a reformat cannot silently
  turn the check into an empty-vs-empty pass. Marker comments were the
  considered alternative; rejected to keep hook sources untouched.
* **Hook regression suites:** fixture harnesses under `tests/` (throwaway git
  repos, synthetic PreToolUse JSON, a deterministic `gh` shim at
  `tests/fixtures/bin/gh`, `HOME` overrides) cover both gh-identity guards,
  `session-secrets-guard.sh`, and `bash-destructive-guard.sh`, following the
  `tests/secrets-guard` pattern. `tests/validate/run-tests.sh` adds a
  clone-and-mutate regression harness for `validate.sh` itself, scoped to its
  deterministic file-driven checks. The suites (existing and new) run in CI;
  the hook suites are bash 3.2-safe so the macOS job doubles as their 3.2
  runtime check. The first run of the lockstep check caught real drift
  (`parse_owner_repo` comment divergence), confirming the mechanism.

### Tradeoffs

* Good: the floor and the lockstep move from asserted to enforced; hook
  regressions and `validate.sh` regressions fail CI instead of shipping;
  accepted gaps (wrapper-resolver depth cap, 512 KB scan cap) become locked
  assertions rather than folklore.
* Bad: a macOS CI job is slower to schedule than Linux; the convention-based
  extractor constrains how the lockstep functions may be formatted; the
  validate.sh harness pays a full `validate.sh` run per case and is coupled to
  its output message shapes.

## More Information

Related: ADR-053, ADR-054 (hook duplication rationale), ADR-059 (secrets-guard
test suite precedent), ADR-069 (tool allowlists), issue #12 (this batch),
issue #17 (session-hook host scoping — its fix joins the lockstep set).
