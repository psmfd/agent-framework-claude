#!/usr/bin/env bash
#
# run-tests.sh — clone-and-mutate regression harness for validate.sh itself.
#
# validate.sh has no test suite of its own: every other harness in tests/
# exercises a single hook or script. This harness exercises validate.sh's
# check functions by cloning the repo into a throwaway fixture, injecting
# exactly one defect per case, running the fixture's own validate.sh against
# it, and asserting the exit code plus the real ERROR/WARN line the check
# emits (substring match — never a guessed message).
#
# Bash floor: THIS HARNESS REQUIRES BASH 4.0+, unlike every other suite in
# tests/ (those target bash 3.2, the hooks' floor). validate.sh itself
# requires bash 4.0+ (it uses `declare -A FM` for frontmatter parsing), so a
# harness that drives it inherits the same floor — there is no way to test a
# bash-4-only script from bash 3.2. See validate.sh's own header check for
# the same pattern this harness reproduces below.
#
# Fixture and isolation:
#   - `git clone --local --no-hardlinks -q <repo-root> <tmpdir>/fixture` ONCE.
#     A plain local clone rewrites `origin` to the source path; this harness
#     restores the real origin URL immediately after cloning — see "Surprise"
#     #1 below for why that is not cosmetic.
#   - HOME is a fresh mktemp'd directory for the whole run (never has
#     ~/.claude symlinks), so check_symlinks sees a controlled, empty home.
#   - PATH is rebuilt from scratch as symlinks to the specific tools needed
#     by validate.sh and its shellcheck-driven checks (bash, git, grep, sed,
#     awk, find, jq, the shellcheck binary itself, sha256sum/shasum,
#     coreutils, …), resolved via `command -v` while the real PATH is still
#     active. `gh` is deliberately never symlinked, but a deterministic
#     no-op stub (`exit 1`, no network) is installed under that name — see
#     "Surprise" #2 below for why bare absence is not enough.
#   - Each run uses `env -i PATH=... HOME=... LANG=C LC_ALL=C bash
#     ./validate.sh` for a fully clean environment (no inherited GH_TOKEN,
#     no leaked shell functions/aliases).
#
# Reset between cases: `git -C fixture checkout -q -- .` (reverts tracked-file
# mutations) then `git -C fixture clean -q -fdx -- <paths>` scoped to the
# untracked paths the case created (new fixture-only files never committed
# upstream), then a re-apply of the validate.sh/rulesets/ overlay (see
# "Uncommitted-gate overlay" below) — the blanket `git checkout -- .` step
# reverts EVERY modified tracked file, validate.sh included, so every reset
# must restore the overlay or later cases silently run against the stale
# committed-HEAD validate.sh. The fixture is cloned once; every case mutates
# and resets it in place rather than paying a fresh clone per case.
#
# Surprises found while building this harness (validate.sh behaviors, not
# harness bugs — reported to the orchestrator rather than fixed here, since
# fixing validate.sh is outside this task's scope):
#
#   1. check_gh_identity's non-github.com branch (`case ... *) return ;;
#      esac`) uses a bare `return` whose exit status is inherited from the
#      immediately preceding `[[ -z "$remote_url" ]]` test. When that test is
#      false (the common case — a remote IS set), the bare `return` exits the
#      function with status 1, and because check_gh_identity is called as a
#      plain statement in main(), `set -e` aborts the entire script with no
#      further output. A `git clone --local` fixture whose origin is left
#      pointing at the local source path — not a github.com URL — hits this
#      branch on every run, which is why this harness restores the real
#      origin URL immediately after cloning rather than leaving the
#      clone-rewritten local-path origin in place.
#   2. The same bare-`return`-inherits-prior-$?  hazard exists in
#      check_branch_pr_state's and check_gh_identity's `command -v gh || return`
#      guards: with `gh` entirely absent from PATH, `command -v gh` fails (1),
#      and the bare `return` propagates that 1 out of the function, aborting
#      the script the same way. This is why the harness installs a
#      deterministic no-op `gh` stub (always `exit 1`, never touches the
#      network) instead of leaving `gh` off PATH altogether — presence
#      avoids the trap while the stub's guaranteed failure still keeps every
#      gh-backed check a no-op.
#
# Uncommitted-gate overlay: this harness's `git clone --local` only sees
# committed HEAD, but validate.sh and rulesets/ are, as of this writing,
# UNCOMMITTED working-tree changes (a new check_ruleset_job_drift function,
# ADR-086, plus the WARN-not-SKIP check_shellcheck rewrite). A bare clone
# would exercise the OLD validate.sh and every rulesets-* / shellcheck-absent
# case below would fail against gate logic that doesn't exist yet. This
# harness deliberately overlays $REPO_ROOT's *working-tree* validate.sh and
# rulesets/ onto the fixture immediately after cloning (see "Overlay" below)
# so it always tests the CURRENT gate logic on disk. Once these changes are
# committed, `git clone --local` already carries them and the overlay copy
# is a byte-identical no-op — this step never needs to be removed.
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all cases pass, 1 one or more case failures (or precondition
# failure), 2 environment/precondition setup failure (missing tool, no fixture).
#
# Usage: bash tests/validate/run-tests.sh
#
# Cases (17 total, including the precondition):
#   1.  clean baseline                          -> precondition (must PASS)
#   2.  agent missing `tools:` frontmatter       -> check_agent
#   3.  agent missing disable-model-invocation   -> check_agent
#   4.  duplicate ADR number                     -> check_adrs
#   5.  ADR numbering gap (positive control)     -> check_adrs
#   6.  agent row removed from README            -> check_readme_catalog
#   7.  shellcheck-detectable defect in a hook    -> check_shellcheck (SKIP if
#       (guarded: command -v shellcheck)            shellcheck absent)
#   8.  scripts/lib/log.sh self-test corrupted   -> check_lib_selftests
#   9.  scripts/wim/*.sh edited, .frozen-shas not -> check_frozen_scripts
#       repinned
#   10. HOME has no ~/.claude symlinks           -> check_symlinks
#   11. dangling relative markdown link          -> check_relative_links
#   12. code fence without a language tag        -> check_documentation
#   13. ruleset context renamed out from under    -> check_ruleset_job_drift
#       its workflow job (ADR-086)                 (ERROR)
#   14. workflow job renamed out from under a     -> check_ruleset_job_drift
#       ruleset's required context (ADR-086)        (ERROR, same message,
#                                                     triggered from the
#                                                     workflow side)
#   15. rulesets/ absent entirely                -> check_ruleset_job_drift
#       (ruleset-as-code not adopted)                (SKIP, not ERROR)
#   16. new workflow job not required by any     -> check_ruleset_job_drift
#       committed ruleset (positive control)        (WARN, exit 0)
#   17. shellcheck absent from PATH               -> check_shellcheck
#       (guarded: real shellcheck must be            (WARN, not SKIP)
#       present on the host to prove removal)

if (( ${BASH_VERSINFO[0]:-0} < 4 )); then
  echo "ERROR [env] tests/validate/run-tests.sh requires bash 4.0 or later (found ${BASH_VERSION:-unknown}) — it drives validate.sh, which has the same floor (declare -A)" >&2
  echo "INFO  On macOS install a modern bash: brew install bash" >&2
  exit 2
fi

# -e is intentionally omitted: a test runner must continue past a failing
# case to report all results; failures are tracked via the `errors` counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_REL="validate.sh"

ok()   { echo "OK    [$1] $2"; }
skip() { echo "SKIP  [$1] $2"; }
info() { echo "INFO  $*"; }
err()  { echo "ERROR [$1] $2" >&2; }

errors=0
TMPDIRS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local d; for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

for cmd in git bash; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd is required but not on PATH"; exit 2; }
done
[[ -f "$REPO_ROOT/$VALIDATE_REL" ]] || { err "env" "validate.sh not found at $REPO_ROOT/$VALIDATE_REL"; exit 2; }

# --- Build the fixture: one clone, reused and reset across every case ---
WORK="$(mktemp -d)"
TMPDIRS+=("$WORK")
FIXTURE="$WORK/fixture"
CLEAN_BIN="$WORK/bin"
FIXTURE_HOME="$WORK/home"

if ! git clone --local --no-hardlinks -q "$REPO_ROOT" "$FIXTURE" 2>/dev/null; then
  err "env" "git clone --local of $REPO_ROOT failed"
  exit 2
fi
git -C "$FIXTURE" config user.email "validate-harness@example.com"
git -C "$FIXTURE" config user.name "validate-harness"

# Surprise #1 (see header): restore the real origin URL so check_gh_identity
# takes its intended github.com branch instead of the bare-`return`-crashes
# non-github.com branch that a bare local-path origin would hit on every run.
REAL_ORIGIN="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
if [[ -n "$REAL_ORIGIN" ]]; then
  git -C "$FIXTURE" remote set-url origin "$REAL_ORIGIN" 2>/dev/null || true
fi

mkdir -p "$CLEAN_BIN" "$FIXTURE_HOME"

# Curated PATH: symlink only the specific binaries needed, resolved to their
# real disk paths while the unrestricted PATH is still active. Filtered to
# absolute paths only — a shadowed builtin/function can make `command -v`
# return a bare name, which must never become a broken symlink target.
_needed_tools="bash git grep sed awk find sort cut mktemp rm cp mv cat printf
wc head tail tr xargs basename dirname readlink sha256sum shasum shellcheck
jq env true false ls chmod uname expr date"
for _tool in $_needed_tools; do
  _resolved="$(command -v "$_tool" 2>/dev/null || true)"
  case "$_resolved" in
    /*) ln -sf "$_resolved" "$CLEAN_BIN/$_tool" ;;
  esac
done
unset _tool _resolved _needed_tools

# Surprise #2 (see header): a deterministic no-op stub, not bare absence.
cat > "$CLEAN_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
exit 1
GHSTUB
chmod +x "$CLEAN_BIN/gh"

CLEAN_PATH="$CLEAN_BIN"

# --- Overlay: apply $REPO_ROOT's uncommitted validate.sh + rulesets/ onto
# the fixture (see the "Uncommitted-gate overlay" header note above for why).
# OVERLAY_SRC is a frozen snapshot taken once, right now — not a live
# reference to $REPO_ROOT — so a case that resets by re-applying the overlay
# is unaffected by any concurrent change to the real working tree during the
# run. apply_overlay() is idempotent; reset_fixture() (defined below) calls
# it on every reset for two distinct reasons: (1) rulesets/*.json is
# untracked in the fixture's own git repo (cp'd in, never `git add`ed there),
# so `git checkout -- .` cannot restore or re-create it — only re-copying
# from the snapshot can; (2) validate.sh IS a normally-tracked file left
# locally modified by the overlay, and `git checkout -- .` reverts every
# modified tracked file, so without the re-apply it would silently regress
# validate.sh back to the stale committed-HEAD version on every reset.
OVERLAY_SRC="$WORK/overlay-src"
mkdir -p "$OVERLAY_SRC"
cp "$REPO_ROOT/$VALIDATE_REL" "$OVERLAY_SRC/$VALIDATE_REL"
if [[ -d "$REPO_ROOT/rulesets" ]]; then
  cp -R "$REPO_ROOT/rulesets" "$OVERLAY_SRC/rulesets"
fi

apply_overlay() {
  cp "$OVERLAY_SRC/$VALIDATE_REL" "$FIXTURE/$VALIDATE_REL"
  rm -rf "$FIXTURE/rulesets"
  if [[ -d "$OVERLAY_SRC/rulesets" ]]; then
    cp -R "$OVERLAY_SRC/rulesets" "$FIXTURE/rulesets"
  fi
}
apply_overlay

# --- Run the fixture's own validate.sh; populate VALIDATE_OUT/VALIDATE_RC ---
# Optional $1 overrides PATH for this one run (default: $CLEAN_PATH) — used
# by the shellcheck-absent-from-PATH case to swap in a curated PATH lacking
# only the `shellcheck` symlink.
VALIDATE_OUT=""
VALIDATE_RC=0
run_validate() {
  local use_path="${1:-$CLEAN_PATH}"
  local rc=0
  VALIDATE_OUT="$(cd "$FIXTURE" && env -i PATH="$use_path" HOME="$FIXTURE_HOME" LANG=C LC_ALL=C bash "./$VALIDATE_REL" 2>&1)" || rc=$?
  VALIDATE_RC=$rc
}

# Revert tracked-file mutations, then remove any untracked paths a case
# created (repo-relative paths, relative to $FIXTURE).
# shellcheck disable=SC2329  # invoked from every case_*() function below
reset_fixture() {
  git -C "$FIXTURE" checkout -q -- . 2>/dev/null || true
  if [[ $# -gt 0 ]]; then
    git -C "$FIXTURE" clean -q -fdx -- "$@" 2>/dev/null || true
  fi
  # validate.sh is a normally-tracked file that the overlay (see above)
  # deliberately leaves locally modified relative to HEAD. The blanket
  # `git checkout -q -- .` above reverts EVERY modified tracked file,
  # validate.sh included — so every reset_fixture() call must re-apply the
  # overlay, or any case downstream of one silently regresses to the stale
  # committed-HEAD validate.sh (and loses check_ruleset_job_drift/the
  # WARN-not-SKIP check_shellcheck rewrite entirely). Cheap and idempotent.
  apply_overlay
}

# Assert VALIDATE_RC == expected exit code AND every remaining arg is present
# as a literal substring somewhere in VALIDATE_OUT (fixed-string match).
# shellcheck disable=SC2329  # invoked from every case_*() function below
assert_case() {
  local name="$1" expected_rc="$2"
  shift 2
  local rc_ok=1 substr_ok=1 pat
  [[ "$VALIDATE_RC" -eq "$expected_rc" ]] || rc_ok=0
  for pat in "$@"; do
    printf '%s' "$VALIDATE_OUT" | grep -qF -- "$pat" || substr_ok=0
  done
  if [[ $rc_ok -eq 1 && $substr_ok -eq 1 ]]; then
    ok "$name" "exit $VALIDATE_RC as expected; expected message(s) found"
  else
    err "$name" "assertion failed (expected exit $expected_rc, got $VALIDATE_RC; expected substring(s): $*)"
    errors=$((errors + 1))
    printf '%s\n' "$VALIDATE_OUT" | tail -25 | sed 's/^/      /' >&2
  fi
}

# --- Case 2: check_agent — missing `tools:` frontmatter field ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_missing_tools_field() {
  local f="agents/zz-test-agent.md"
  cat > "$FIXTURE/$f" <<'AGENT'
---
name: zz-test-agent
description: Harness-only fixture agent exercising check_agent's missing-field path. Never a real catalog entry.
model: sonnet
disable-model-invocation: true
---

# zz-test-agent (test fixture)

This file exists only inside the validate.sh regression harness fixture. It
intentionally omits the `tools:` frontmatter field to exercise check_agent's
required-field check. This padding text keeps the body at or above the
200-character minimum body-length check, so this case stays isolated to the
single field under test.
AGENT
  run_validate
  assert_case "check_agent-missing-tools" 1 \
    "ERROR [zz-test-agent] agent: missing required field 'tools'"
  reset_fixture "$f"
}

# --- Case 3: check_agent — missing disable-model-invocation: true ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_missing_disable_invocation() {
  local f="agents/zz-test-agent2.md"
  cat > "$FIXTURE/$f" <<'AGENT'
---
name: zz-test-agent2
description: Harness-only fixture agent exercising check_agent's ADR-074 disable-model-invocation check.
model: sonnet
tools: Read
---

# zz-test-agent2 (test fixture)

This file exists only inside the validate.sh regression harness fixture. It
intentionally omits `disable-model-invocation: true` to exercise the ADR-074
check. This padding text keeps the body at or above the 200-character
minimum body-length check, so this case stays isolated to the field under
test.
AGENT
  run_validate
  assert_case "check_agent-missing-disable-invocation" 1 \
    "ERROR [zz-test-agent2] agent: missing required field 'disable-model-invocation: true' (ADR-074)"
  reset_fixture "$f"
}

# --- Case 4: check_adrs — duplicate ADR number ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_duplicate_adr_number() {
  local src num dst_rel
  src="$(find "$FIXTURE/adrs" -maxdepth 1 -name '[0-9][0-9][0-9]-*.md' -type f | sort | tail -1)"
  if [[ -z "$src" ]]; then
    err "check_adrs-duplicate-number-setup" "no numbered ADR files found in fixture — case skipped"
    errors=$((errors + 1))
    return
  fi
  num="$(basename "$src" | cut -c1-3)"
  dst_rel="adrs/${num}-zz-test-duplicate.md"
  cp "$src" "$FIXTURE/$dst_rel"
  run_validate
  assert_case "check_adrs-duplicate-number" 1 \
    "duplicate ADR number ${num} — numbers must never be reused"
  reset_fixture "$dst_rel"
}

# --- Case 5: check_adrs — numbering gap is allowed (positive control) ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_adr_number_gap() {
  local f="adrs/999-zz-test-gap.md"
  cat > "$FIXTURE/$f" <<'ADR'
# ADR-999: Harness-only fixture ADR proving numbering gaps are allowed

**Status:** Accepted
**Date:** 2026-01-01

## Context and Problem Statement

This file exists only inside the validate.sh regression harness fixture. It
proves check_adrs does not flag a numbering gap as an error post-fork
(ADR-076) — only duplicate and out-of-order numbers are errors.

## Considered Options

* **Option A** — leave the gap unaddressed (chosen; gaps are allowed)
* **Option B** — renumber every ADR to close the gap (rejected; numbers must
  never be reused, so closing a gap after the fact is impossible without
  violating that rule)

## Decision Outcome

Chosen option: **Option A**, because ADR numbers are never reused, so a gap
left by a dropped or forked-out decision cannot be closed retroactively.

## More Information

None.
ADR
  run_validate
  if [[ "$VALIDATE_RC" -eq 0 ]] && printf '%s' "$VALIDATE_OUT" | grep -qF "PASS — 0 errors"; then
    ok "check_adrs-gap-allowed" "ADR numbering gap (999 after the prior highest) produced no error — gaps allowed (ADR-076)"
  else
    err "check_adrs-gap-allowed" "expected the numbering gap to be a no-op (exit 0, PASS — 0 errors); got exit $VALIDATE_RC"
    errors=$((errors + 1))
    printf '%s\n' "$VALIDATE_OUT" | tail -25 | sed 's/^/      /' >&2
  fi
  reset_fixture "$f"
}

# --- Case 6: check_readme_catalog — agent row removed from README ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_readme_missing_agent_row() {
  local target="ansible-expert"
  if ! grep -qF "| \`$target\` |" "$FIXTURE/README.md"; then
    err "check_readme_catalog-missing-row-setup" "expected README row for '$target' not found — case skipped"
    errors=$((errors + 1))
    return
  fi
  grep -vF "| \`$target\` |" "$FIXTURE/README.md" > "$FIXTURE/README.md.zztmp"
  mv "$FIXTURE/README.md.zztmp" "$FIXTURE/README.md"
  run_validate
  assert_case "check_readme_catalog-missing-row" 0 \
    "WARN  [readme-catalog] agents/${target}.md exists but not listed in README Current Agents"
  reset_fixture
}

# --- Case 7: check_shellcheck — shellcheck-detectable defect in a hook ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_shellcheck_defect() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "check_shellcheck-defect" "shellcheck not installed on this host — skipping"
    return
  fi
  local f="hooks/worktree-remove.sh"
  if [[ ! -f "$FIXTURE/$f" ]]; then
    err "check_shellcheck-defect-setup" "$f not found in fixture — case skipped"
    errors=$((errors + 1))
    return
  fi
  # shellcheck disable=SC2016  # unquoted $VAR is the injected defect (SC2086 bait), not an expansion of this script's own variable
  printf '\necho $ZZ_TEST_HARNESS_UNDECLARED_VAR >/dev/null 2>&1 || true\n' >> "$FIXTURE/$f"
  run_validate
  assert_case "check_shellcheck-defect" 1 "ERROR [shellcheck]" "SC2086"
  reset_fixture
}

# --- Case 8: check_lib_selftests — scripts/lib/log.sh self-test corrupted ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_lib_selftest_corruption() {
  local f="scripts/lib/log.sh"
  if [[ ! -f "$FIXTURE/$f" ]]; then
    err "check_lib_selftests-corruption-setup" "$f not found in fixture — case skipped"
    errors=$((errors + 1))
    return
  fi
  sed "s/printf '%sOK%s/printf '%sOKX%s/" "$FIXTURE/$f" > "$FIXTURE/$f.zztmp" \
    && mv "$FIXTURE/$f.zztmp" "$FIXTURE/$f"
  run_validate
  assert_case "check_lib_selftests-corruption" 1 \
    "ERROR [lib-selftest] log.sh — self-tests failed"
  reset_fixture
}

# --- Case 9: check_frozen_scripts — frozen script edited, hash not repinned ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_frozen_script_mismatch() {
  local f="scripts/wim/_lib.sh"
  if [[ ! -f "$FIXTURE/$f" ]]; then
    err "check_frozen_scripts-mismatch-setup" "$f not found in fixture — case skipped"
    errors=$((errors + 1))
    return
  fi
  printf '\n# zz-test-harness-mutation (unpinned edit)\n' >> "$FIXTURE/$f"
  run_validate
  assert_case "check_frozen_scripts-mismatch" 1 \
    "ERROR [frozen-scripts]" "SHA-256 mismatch" "frozen scripts must not be edited"
  reset_fixture
}

# --- Case 10: check_symlinks — HOME has no ~/.claude symlinks ---
# No mutation: FIXTURE_HOME is a fresh mktemp'd directory for the whole
# harness run (see header), so it never has ~/.claude symlinks in any case.
# This case asserts that inherent, harness-wide condition rather than
# injecting a further defect.
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_symlinks_missing() {
  run_validate
  assert_case "check_symlinks-missing" 0 \
    "WARN  [symlinks] ${FIXTURE_HOME}/.claude/agents is not a symlink — run setup.sh"
}

# --- Case 11: check_relative_links — dangling relative markdown link ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_dangling_relative_link() {
  local f="docs/zz-test-dangling-link.md"
  cat > "$FIXTURE/$f" <<'DOC'
# Harness fixture: dangling relative link

This file exists only inside the validate.sh regression harness fixture. It
exercises check_relative_links via a link to a target that does not exist.

See [missing target](./zz-test-does-not-exist.md) for details.
DOC
  run_validate
  assert_case "check_relative_links-dangling" 1 \
    "ERROR [links] docs/zz-test-dangling-link.md: broken link './zz-test-does-not-exist.md' — target not found"
  reset_fixture "$f"
}

# --- Case 12: check_documentation — code fence without a language tag ---
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_fence_without_language() {
  local f="docs/zz-test-fence.md"
  cat > "$FIXTURE/$f" <<DOC
# Harness fixture: code fence without a language tag

This file exists only inside the validate.sh regression harness fixture. It
exercises check_documentation's code-fence language-tag check.

\`\`\`
plain fence, no language tag
\`\`\`
DOC
  run_validate
  assert_case "check_documentation-fence-no-lang" 0 \
    "WARN  [docs] docs/zz-test-fence.md" "code fence without language tag"
  reset_fixture "$f"
}

# --- Case 13: check_ruleset_job_drift — ruleset context orphaned (ADR-086) ---
# Rename one required-status-check "context" inside a committed ruleset so it
# no longer matches any workflow job's effective name. rulesets/*.json is
# untracked in the fixture (overlay-applied, never `git add`ed there), so
# reset is apply_overlay(), not reset_fixture()/git checkout.
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_ruleset_context_orphaned() {
  local f="rulesets/protect-dev.json"
  if [[ ! -f "$FIXTURE/$f" ]]; then
    err "check_ruleset_job_drift-context-orphaned-setup" "$f not found in fixture (rulesets/ not adopted yet, or overlay source missing) — case skipped"
    errors=$((errors + 1))
    return
  fi
  if ! grep -qF '"context": "validate"' "$FIXTURE/$f"; then
    err "check_ruleset_job_drift-context-orphaned-setup" "no '\"context\": \"validate\"' entry found in $f — case skipped"
    errors=$((errors + 1))
    return
  fi
  sed 's/"context": "validate"/"context": "validate-zztest"/' "$FIXTURE/$f" > "$FIXTURE/$f.zztmp" \
    && mv "$FIXTURE/$f.zztmp" "$FIXTURE/$f"
  run_validate
  assert_case "check_ruleset_job_drift-context-orphaned" 1 \
    "ERROR [rulesets]" "matches no workflow job"
  apply_overlay
}

# --- Case 14: check_ruleset_job_drift — workflow job renamed (ADR-086) ---
# Same underlying defect as case 13 (a required context with no matching
# job) triggered from the other side: rename the job's `name:` field instead
# of the ruleset's context. .github/workflows/validate.yml is a normally
# tracked, unmodified-at-HEAD file, so reset_fixture() (git checkout, which
# also re-applies the overlay — see reset_fixture()'s own comment) is
# sufficient here.
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_ruleset_workflow_job_renamed() {
  local rf="rulesets/protect-dev.json" wf=".github/workflows/validate.yml"
  if [[ ! -f "$FIXTURE/$rf" ]]; then
    err "check_ruleset_job_drift-job-renamed-setup" "$rf not found in fixture (rulesets/ not adopted yet, or overlay source missing) — case skipped"
    errors=$((errors + 1))
    return
  fi
  if [[ ! -f "$FIXTURE/$wf" ]]; then
    err "check_ruleset_job_drift-job-renamed-setup" "$wf not found in fixture — case skipped"
    errors=$((errors + 1))
    return
  fi
  if ! grep -qxF '    name: validate' "$FIXTURE/$wf"; then
    err "check_ruleset_job_drift-job-renamed-setup" "no '    name: validate' job-name line found in $wf — case skipped"
    errors=$((errors + 1))
    return
  fi
  sed 's/^    name: validate$/    name: validate-zztest/' "$FIXTURE/$wf" > "$FIXTURE/$wf.zztmp" \
    && mv "$FIXTURE/$wf.zztmp" "$FIXTURE/$wf"
  run_validate
  assert_case "check_ruleset_job_drift-job-renamed" 1 \
    "ERROR [rulesets]" "matches no workflow job"
  reset_fixture "$wf"
}

# --- Case 15: check_ruleset_job_drift — rulesets/ absent entirely ---
# Deleting rulesets/ must SKIP the drift check (ruleset-as-code treated as
# not-adopted), never ERROR, and must not fail the overall run. assert_case
# only checks for substring PRESENCE, so this case is hand-rolled to also
# assert the ERROR line's ABSENCE — the property that matters most here.
# rulesets/ is untracked in the fixture, so reset is apply_overlay(), which
# also handles re-creating the directory apply_overlay() just removed.
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_ruleset_dir_absent() {
  if [[ ! -d "$FIXTURE/rulesets" ]]; then
    err "check_ruleset_job_drift-dir-absent-setup" "rulesets/ not present in fixture to begin with — case skipped"
    errors=$((errors + 1))
    return
  fi
  rm -rf "$FIXTURE/rulesets"
  run_validate
  local skip_found=0 error_found=0
  printf '%s' "$VALIDATE_OUT" | grep -qF "SKIP  [rulesets] rulesets/ not present" && skip_found=1
  printf '%s' "$VALIDATE_OUT" | grep -qF "ERROR [rulesets]" && error_found=1
  if [[ "$VALIDATE_RC" -eq 0 && $skip_found -eq 1 && $error_found -eq 0 ]]; then
    ok "check_ruleset_job_drift-dir-absent" "rulesets/ removed -> SKIP (not ERROR), exit 0"
  else
    err "check_ruleset_job_drift-dir-absent" "assertion failed (exit=$VALIDATE_RC, skip_found=$skip_found, error_found=$error_found)"
    errors=$((errors + 1))
    printf '%s\n' "$VALIDATE_OUT" | tail -25 | sed 's/^/      /' >&2
  fi
  apply_overlay
}

# --- Case 16: check_ruleset_job_drift — unrequired job warns (positive
# control) ---
# A brand-new workflow job that no committed ruleset requires must WARN
# (informational), not ERROR, and must not fail the run. Appends a trivial
# job to the tracked .github/workflows/validate.yml, so reset_fixture()
# (git checkout, which also re-applies the overlay) is sufficient.
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_ruleset_unrequired_job_warns() {
  local wf=".github/workflows/validate.yml"
  if [[ ! -f "$FIXTURE/$wf" ]]; then
    err "check_ruleset_job_drift-unrequired-warn-setup" "$wf not found in fixture — case skipped"
    errors=$((errors + 1))
    return
  fi
  cat >> "$FIXTURE/$wf" <<'JOB'

  zz-test-trivial-job:
    name: zz-test-trivial-job
    runs-on: ubuntu-24.04
    steps:
      - run: echo zz-test-harness-job
JOB
  run_validate
  assert_case "check_ruleset_job_drift-unrequired-warn" 0 \
    "WARN  [rulesets] job 'zz-test-trivial-job' is not required"
  reset_fixture "$wf"
}

# --- Case 17: check_shellcheck — shellcheck absent from PATH -> WARN not SKIP ---
# Reuses the harness's own curated-PATH machinery (CLEAN_BIN) rather than
# building a PATH from tool *directories* (e.g. `dirname "$(command -v
# bash)"`). A directory-based PATH is unsafe on exactly the kind of host this
# harness already runs on: Homebrew macOS installs bash and shellcheck into
# the SAME directory (/opt/homebrew/bin), so adding "bash's directory" to
# PATH would silently re-expose shellcheck and defeat the case — the
# colocation hazard this case must guard against. Copying CLEAN_BIN and
# deleting only its `shellcheck` symlink sidesteps that hazard structurally:
# the curated dir never has a file named `shellcheck`, regardless of which
# real directory shellcheck lives in on this host, and every other tool
# (jq, find, sha256sum, …) stays resolvable — so no separate SKIP-on-
# colocation branch is needed. The guard below instead SKIPs the narrower,
# still-real degenerate case where shellcheck was never resolvable on the
# host to begin with (nothing to prove absent-by-removal).
# shellcheck disable=SC2329  # invoked indirectly via the CASES registry
case_shellcheck_absent_from_path() {
  if [[ ! -e "$CLEAN_BIN/shellcheck" ]]; then
    skip "check_shellcheck-absent-warn" "shellcheck not installed on this host — nothing to remove to prove the absent-from-PATH path; skipping"
    return
  fi
  local nb="$WORK/bin-no-shellcheck"
  rm -rf "$nb"
  cp -R "$CLEAN_BIN" "$nb"
  rm -f "$nb/shellcheck"
  run_validate "$nb"
  assert_case "check_shellcheck-absent-warn" 0 \
    "WARN  [shellcheck] shellcheck not installed — lint skipped locally but ENFORCED in CI"
}

# --- Case registry (name:function), run in order after the precondition ---
CASES=(
  "check_agent-missing-tools:case_missing_tools_field"
  "check_agent-missing-disable-invocation:case_missing_disable_invocation"
  "check_adrs-duplicate-number:case_duplicate_adr_number"
  "check_adrs-gap-allowed:case_adr_number_gap"
  "check_readme_catalog-missing-row:case_readme_missing_agent_row"
  "check_shellcheck-defect:case_shellcheck_defect"
  "check_lib_selftests-corruption:case_lib_selftest_corruption"
  "check_frozen_scripts-mismatch:case_frozen_script_mismatch"
  "check_symlinks-missing:case_symlinks_missing"
  "check_relative_links-dangling:case_dangling_relative_link"
  "check_documentation-fence-no-lang:case_fence_without_language"
  "check_ruleset_job_drift-context-orphaned:case_ruleset_context_orphaned"
  "check_ruleset_job_drift-job-renamed:case_ruleset_workflow_job_renamed"
  "check_ruleset_job_drift-dir-absent:case_ruleset_dir_absent"
  "check_ruleset_job_drift-unrequired-warn:case_ruleset_unrequired_job_warns"
  "check_shellcheck-absent-warn:case_shellcheck_absent_from_path"
)
TOTAL_CASES=$((${#CASES[@]} + 1))

info "validate.sh clone-and-mutate regression harness — $TOTAL_CASES case(s)"

# --- Case 1: precondition — the unmutated fixture must cleanly PASS ---
info "Case 1/$TOTAL_CASES: clean baseline (precondition)"
run_validate
if [[ "$VALIDATE_RC" -eq 0 ]] && printf '%s' "$VALIDATE_OUT" | grep -qF "PASS — 0 errors"; then
  ok "baseline" "clean fixture passes validate.sh (exit 0, PASS — 0 errors)"
else
  err "baseline" "clean fixture did not pass validate.sh — every remaining case depends on a clean baseline; aborting"
  errors=$((errors + 1))
  printf '%s\n' "$VALIDATE_OUT" | tail -40 | sed 's/^/      /' >&2
  for entry in "${CASES[@]}"; do
    skip "${entry%%:*}" "skipped — precondition (clean baseline) failed"
  done
  echo "=================================="
  echo "FAIL — $errors error(s)"
  exit 1
fi

n=2
for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  fn="${entry##*:}"
  info "Case $n/$TOTAL_CASES: $name"
  "$fn"
  n=$((n + 1))
done

echo "=================================="
if [[ $errors -gt 0 ]]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
