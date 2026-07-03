#!/usr/bin/env bash
#
# run-tests.sh — fixture harness for scripts/rulesets.sh (ruleset-as-code for
# GitHub branch-protection rulesets, ADR-086)
#
# Drives the script directly against a throwaway git repo (rulesets/*.json)
# and a fake `gh` shim on PATH (tests/rulesets/fixtures/bin/gh) that serves
# canned "live" GitHub API responses — no network, no real gh, no real
# repository is ever touched.
#
# Coverage:
#   Normalization  — the NORMALIZE jq filter (explicit field allowlist +
#                     context sorting) is idempotent, and its output on a
#                     server-shaped raw ruleset matches a frozen fixture
#                     (regression, not re-derivation)
#   --check        — SKIPs cleanly when gh is absent from PATH; reports OK
#                     when live matches committed; reports ERROR + exit 1 on
#                     drift and on a committed name with no live match
#   --apply        — --dry-run never mutates (empty calls log); refuses
#                     non-interactively without --yes; with --yes issues
#                     exactly one PUT to the right url with the right body
#   --pull         — writes the normalized live state to a new file
#
# The fake gh (tests/rulesets/fixtures/bin/gh) is a NEW shim distinct from
# tests/fixtures/bin/gh (the hook-test shim) — it models the specific argv
# shapes rulesets.sh emits (repo view, api .../rulesets --jq, api
# .../rulesets/<id>, api --method PUT|POST --input).
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (the script's floor). Run: bash tests/rulesets/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing case
# to report all results; failures are tracked via the `errors` counter instead.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULESETS="$SCRIPT_DIR/../../scripts/rulesets.sh"
FIXTURES="$SCRIPT_DIR/fixtures"
GH_BIN="$FIXTURES/bin"
RAW_CLEAN="$FIXTURES/raw-ruleset.json"
RAW_DRIFTED="$FIXTURES/raw-ruleset-drifted.json"
NORMALIZED="$FIXTURES/normalized-ruleset.json"
FAKE_REPO="octo/repo"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
TMPDIRS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local d; for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

for cmd in git jq; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd is required but not on PATH"; exit 2; }
done
[ -f "$RULESETS" ] || { err "env" "script not found at $RULESETS"; exit 2; }
[ -x "$GH_BIN/gh" ] || { err "env" "fake gh shim not found or not executable at $GH_BIN/gh"; exit 2; }
for f in "$RAW_CLEAN" "$RAW_DRIFTED" "$NORMALIZED"; do
  [ -f "$f" ] || { err "env" "fixture not found: $f"; exit 2; }
done

# --- Sandbox helpers ---

# A throwaway git repo with an empty rulesets/ dir. Prints the repo path.
new_repo() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  # Resolve to the physical path: git rev-parse --show-toplevel (which the
  # script uses for REPO_ROOT) resolves symlinks, e.g. macOS's /tmp ->
  # /private/tmp — without this, path comparisons below would mismatch.
  d="$(cd "$d" && pwd -P)"
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "rulesets-test"
  mkdir -p "$d/rulesets"
  printf '%s' "$d"
}

# Build the fake-gh "live" fixtures for one ruleset: an index file (id<TAB>name)
# and a rulesets-dir/<id>.json body. Sets LIST_FILE, RS_DIR, CALLS_LOG globals.
LIST_FILE="" RS_DIR="" CALLS_LOG=""
new_live() {  # $1=id $2=name $3=raw-body-file
  local id="$1" name="$2" body="$3" d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  LIST_FILE="$d/list.tsv"
  printf '%s\t%s\n' "$id" "$name" > "$LIST_FILE"
  RS_DIR="$d/live-rulesets"
  mkdir -p "$RS_DIR"
  cp "$body" "$RS_DIR/$id.json"
  CALLS_LOG="$d/calls.log"
  : > "$CALLS_LOG"
}

# Run rulesets.sh in repo dir $1 with args $2.. against the current
# LIST_FILE/RS_DIR/CALLS_LOG live fixtures. stdin is /dev/null (deterministic
# non-tty) so --yes-less confirm() prompts abort rather than block. Sets OUT
# (combined stdout+stderr) and RC (exit code) globals.
OUT="" RC=0
run_ruleset() {
  local d="$1"
  shift
  OUT="$(
    cd "$d" && \
    FAKE_GH_REPO="$FAKE_REPO" \
    FAKE_GH_RULESETS_LIST_OUTPUT="$LIST_FILE" \
    FAKE_GH_RULESETS_DIR="$RS_DIR" \
    FAKE_GH_CALLS_LOG="$CALLS_LOG" \
    PATH="$GH_BIN:$PATH" \
    bash "$RULESETS" "$@" </dev/null 2>&1
  )"
  RC=$?
}

# A curated PATH with symlinks to only the tools rulesets.sh needs, minus gh —
# so `command -v gh` fails deterministically regardless of what real
# directories (possibly containing a real gh alongside jq/git) are on the
# ambient PATH. Mirrors the jq-absent technique in
# tests/session-secrets-guard/run-tests.sh.
no_gh_bindir() {
  local d t p
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  for t in bash dirname cat jq git awk sed diff basename mkdir grep; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    ln -s "$p" "$d/$t"
  done
  printf '%s' "$d"
}

# ============================== Normalization ===============================

# Idempotency: pull the live (clean) fixture into a fresh repo, snapshot the
# written file, pull again (unchanged live) — the second pull must report
# "already in sync" (no rewrite) and the file bytes must be unchanged. Since
# the first pull's file content IS normalize(raw), and the second pull's
# equality check recomputes jq -S NORMALIZE on both the committed file and a
# fresh live fetch, an "already in sync" result together with byte-identical
# content proves NORMALIZE(NORMALIZE(raw)) == NORMALIZE(raw).
case_normalize_idempotent() {
  local d f before after out1 rc1
  d="$(new_repo)"
  new_live 42 sample-ruleset "$RAW_CLEAN"
  f="$d/rulesets/sample-ruleset.json"
  run_ruleset "$d" --pull sample-ruleset --yes
  out1="$OUT"; rc1="$RC"
  if [ "$rc1" != "0" ] || ! printf '%s' "$out1" | grep -q 'wrote'; then
    err "normalize-idempotent" "first --pull did not write as expected (rc=$rc1): $out1"
    errors=$((errors+1))
    return
  fi
  before="$(cat "$f")"
  run_ruleset "$d" --pull sample-ruleset --yes
  after="$(cat "$f")"
  if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'already in sync' && [ "$before" = "$after" ]; then
    ok "normalize-idempotent" "second --pull is a no-op; file bytes unchanged"
  else
    err "normalize-idempotent" "expected no-op + unchanged bytes, got rc=$RC out=$OUT"
    errors=$((errors+1))
  fi
}

# Strips server-only fields and sorts contexts: --pull the raw fixture and
# diff the written file against the frozen expected-normalized fixture.
case_normalize_strips_and_sorts() {
  local d f
  d="$(new_repo)"
  new_live 42 sample-ruleset "$RAW_CLEAN"
  run_ruleset "$d" --pull sample-ruleset --yes
  f="$d/rulesets/sample-ruleset.json"
  if [ "$RC" = "0" ] && [ -f "$f" ] && diff -q "$NORMALIZED" "$f" >/dev/null 2>&1; then
    ok "normalize-strips-and-sorts" "pulled file matches frozen normalized fixture exactly"
  else
    err "normalize-strips-and-sorts" "pulled file diverges from frozen fixture (rc=$RC)"
    errors=$((errors+1))
    [ -f "$f" ] && diff "$NORMALIZED" "$f" | sed 's/^/      /' >&2
  fi
}

# ================================= --check ==================================

case_check_no_gh() {
  local d bindir
  d="$(new_repo)"
  cp "$NORMALIZED" "$d/rulesets/sample-ruleset.json"
  bindir="$(no_gh_bindir)"
  OUT="$( cd "$d" && PATH="$bindir" bash "$RULESETS" --check </dev/null 2>&1 )"
  RC=$?
  if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'SKIP.*gh not on PATH'; then
    ok "check-no-gh" "SKIPs cleanly and exits 0 when gh is absent"
  else
    err "check-no-gh" "expected SKIP + exit 0, got rc=$RC out=$OUT"
    errors=$((errors+1))
  fi
}

case_check_no_drift() {
  local d
  d="$(new_repo)"
  cp "$NORMALIZED" "$d/rulesets/sample-ruleset.json"
  new_live 42 sample-ruleset "$RAW_CLEAN"
  run_ruleset "$d" --check
  if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'OK    \[rulesets\] sample-ruleset matches live state'; then
    ok "check-no-drift" "reports match and exits 0"
  else
    err "check-no-drift" "expected OK match + exit 0, got rc=$RC out=$OUT"
    errors=$((errors+1))
  fi
}

case_check_drift() {
  local d
  d="$(new_repo)"
  cp "$NORMALIZED" "$d/rulesets/sample-ruleset.json"
  new_live 42 sample-ruleset "$RAW_DRIFTED"
  run_ruleset "$d" --check
  if [ "$RC" = "1" ] && printf '%s' "$OUT" | grep -q 'ERROR.*sample-ruleset drifted from live state'; then
    ok "check-drift" "reports drift and exits 1"
  else
    err "check-drift" "expected drift ERROR + exit 1, got rc=$RC out=$OUT"
    errors=$((errors+1))
  fi
}

case_check_missing_live() {
  local d
  d="$(new_repo)"
  cp "$NORMALIZED" "$d/rulesets/other-ruleset.json"
  new_live 42 sample-ruleset "$RAW_CLEAN"
  run_ruleset "$d" --check
  if [ "$RC" = "1" ] && printf '%s' "$OUT" | grep -q "ERROR.*'other-ruleset' has no matching live ruleset"; then
    ok "check-missing-live" "reports no matching live ruleset and exits 1"
  else
    err "check-missing-live" "expected missing-live ERROR + exit 1, got rc=$RC out=$OUT"
    errors=$((errors+1))
  fi
}

# ================================= --apply ==================================

case_apply_dry_run() {
  local d
  d="$(new_repo)"
  cp "$NORMALIZED" "$d/rulesets/sample-ruleset.json"
  new_live 42 sample-ruleset "$RAW_DRIFTED"
  run_ruleset "$d" --apply sample-ruleset --dry-run
  if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'would:' && [ ! -s "$CALLS_LOG" ]; then
    ok "apply-dry-run" "prints intended action, issues no calls, exits 0"
  else
    err "apply-dry-run" "expected 'would:' + empty calls log + exit 0, got rc=$RC out=$OUT calls=$(cat "$CALLS_LOG" 2>/dev/null)"
    errors=$((errors+1))
  fi
}

case_apply_non_interactive_aborts() {
  local d
  d="$(new_repo)"
  cp "$NORMALIZED" "$d/rulesets/sample-ruleset.json"
  new_live 42 sample-ruleset "$RAW_DRIFTED"
  run_ruleset "$d" --apply sample-ruleset
  if [ "$RC" != "0" ] && [ ! -s "$CALLS_LOG" ]; then
    ok "apply-non-interactive-aborts" "refuses without --yes on non-tty stdin (rc=$RC), issues no calls"
  else
    err "apply-non-interactive-aborts" "expected non-zero exit + empty calls log, got rc=$RC out=$OUT"
    errors=$((errors+1))
  fi
}

case_apply_yes_puts() {
  local d f expected_line
  d="$(new_repo)"
  f="$d/rulesets/sample-ruleset.json"
  cp "$NORMALIZED" "$f"
  new_live 42 sample-ruleset "$RAW_DRIFTED"
  run_ruleset "$d" --apply sample-ruleset --yes
  expected_line="$(printf 'PUT\trepos/%s/rulesets/42\t%s' "$FAKE_REPO" "$f")"
  if [ "$RC" = "0" ] && [ "$(wc -l < "$CALLS_LOG" | tr -d ' ')" = "1" ] && [ "$(cat "$CALLS_LOG")" = "$expected_line" ]; then
    ok "apply-yes-puts" "issues exactly one PUT with the right url and input path"
  else
    err "apply-yes-puts" "expected one matching PUT line, got rc=$RC calls=$(cat "$CALLS_LOG" 2>/dev/null) out=$OUT"
    errors=$((errors+1))
  fi
}

# ================================= --pull ===================================

case_pull_writes() {
  local d f
  d="$(new_repo)"
  new_live 42 sample-ruleset "$RAW_CLEAN"
  f="$d/rulesets/sample-ruleset.json"
  run_ruleset "$d" --pull sample-ruleset --yes
  if [ "$RC" = "0" ] && [ -f "$f" ] && diff -q "$NORMALIZED" "$f" >/dev/null 2>&1; then
    ok "pull-writes" "creates the file matching the frozen normalized fixture"
  else
    err "pull-writes" "expected new file matching fixture, got rc=$RC out=$OUT"
    errors=$((errors+1))
    [ -f "$f" ] && diff "$NORMALIZED" "$f" | sed 's/^/      /' >&2
  fi
}

info "rulesets.sh fixture tests"

case_normalize_idempotent
case_normalize_strips_and_sorts
case_check_no_gh
case_check_no_drift
case_check_drift
case_check_missing_live
case_apply_dry_run
case_apply_non_interactive_aborts
case_apply_yes_puts
case_pull_writes

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
