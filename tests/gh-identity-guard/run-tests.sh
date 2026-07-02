#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for hooks/gh-identity-guard.sh (the git
# pre-push hook; layer 2 of the gh-identity guard, ADR-054)
#
# Contract under test: argv $1=remote-name $2=remote-url; stdin=ref lines
# (drained, not parsed). Exit 0 = allow, 1 = identity drift/misconfig,
# 2 = environment failure (fail-closed).
#
# Coverage:
#   1. non-github remote passes silently (exit 0, no output)
#   2. SKIP_GH_IDENTITY_GUARD=1 warns + allows
#   3. gh missing from PATH -> fail closed (exit 2)
#   4. gh probe error (FAKE_GH_FAIL) -> fail closed (exit 2)
#   5. GH_IDENTITY_OVERRIDE with invalid login format -> deny
#   6. GH_IDENTITY_OVERRIDE valid but mismatched -> deny
#   7. GH_TOKEN + FAKE_GH_ACCESS grants repo -> allow
#   8. GH_TOKEN + no access -> deny
#   9. .gh-expected-identity match -> allow
#  10. .gh-expected-identity mismatch -> deny
#  11. .gh-expected-identity with only comments/blanks -> deny
#  12. no pin file + accessibility ok -> allow
#  13. no pin file + accessibility fail -> deny
#  14-16. https / scp-style / ssh:// remote URL forms all parse the same
#         owner/repo (ssh:// case also carries a port, exercising the
#         host:port split in extract_host / parse_owner_repo)
#  17. host with trailing dot (absolute-DNS form) is still recognized as github.com
#  18. host is matched case-insensitively
#
# Each case builds a throwaway git repo (mktemp) — the real developer repo
# and $HOME are never touched. The hook is invoked with an explicit bash
# binary (resolved once, before any PATH manipulation) so PATH-restriction
# cases exercise only the hook's internal `command -v` lookups.
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (matches the hook's floor; no declare -A, no ${var,,},
# no mapfile). Run: bash tests/gh-identity-guard/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing
# case to report all results; failures are tracked via the `errors` counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/gh-identity-guard.sh"
FIXTURES_BIN="$REPO_ROOT/tests/fixtures/bin"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
skip() { echo "SKIP  [$1] $2"; }
info() { echo "INFO  $*"; }

errors=0
TMPDIRS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local d; for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

for cmd in git jq bash; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd is required but not on PATH"; exit 2; }
done
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }
[ -x "$FIXTURES_BIN/gh" ] || { err "env" "fake gh shim not found/executable at $FIXTURES_BIN/gh"; exit 2; }

# Resolve the interpreter ONCE, before any case restricts PATH, so
# PATH-restriction cases only affect the hook's own `command -v` lookups.
BASH_BIN="$(command -v bash)"

DEFAULT_PATH="$FIXTURES_BIN:$PATH"
DEFAULT_STDIN='refs/heads/main abc123 refs/heads/main def456'

# Build a synthetic PATH directory containing symlinks to the real resolved
# binaries named in $1 (space-separated command names), deliberately omitting
# $2. Real system directories routinely colocate git/jq/gh (e.g. Homebrew's
# bin, or /usr/bin on newer macOS), so searching existing directories for a
# "present but not that one" combination is host-layout-dependent and can
# fail to find any qualifying candidate. Symlinking exactly the wanted set
# into a throwaway directory is deterministic on any host. Prints the
# directory's path and returns 0; returns 1 only if a required command
# cannot be resolved on the real PATH at all (a genuine precondition gap,
# not a colocation artifact) — callers must SKIP the case in that fallback.
build_path_without() {
  local include="$1" exclude="$2" dir c src
  dir="$(mktemp -d)"
  TMPDIRS+=("$dir")
  for c in $include; do
    [ "$c" = "$exclude" ] && continue   # safety net: never symlink the excluded command
    src="$(command -v "$c" 2>/dev/null)" || return 1
    ln -s "$src" "$dir/$c"
  done
  printf '%s' "$dir"
}

new_repo() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "gh-identity-guard-test"
  printf '%s' "$d"
}

# Unset every guard-relevant env var and reset CASE_PATH. Called at the top
# of every case so cases never leak env state into each other. CASE_PATH
# (not the harness's own PATH) is what run_hook hands to the hook process —
# a case that wants a restricted PATH sets CASE_PATH, never PATH itself,
# so the harness's own subsequent commands (tr, jq, …) keep working
# regardless of what a case is testing.
reset_case_env() {
  unset SKIP_GH_IDENTITY_GUARD GH_IDENTITY_OVERRIDE GH_TOKEN GITHUB_TOKEN \
        FAKE_GH_LOGIN FAKE_GH_FAIL FAKE_GH_ACCESS
  CASE_PATH="$DEFAULT_PATH"
  CASE_STDIN="$DEFAULT_STDIN"
}

# Run the hook in repo $1 with remote-name $2, remote-url $3. Sets globals
# OUT (combined stdout+stderr) and RC (exit code) — globals rather than a
# command substitution so RC survives under `set -u`/`pipefail` without a
# subshell dance, matching the WT/RC pattern in tests/worktree-guard. PATH is
# set only for the hook's own process (command prefix form), never assigned
# to the harness's PATH.
OUT="" RC=0
run_hook() {
  local d="$1" name="$2" url="$3"
  RC=0
  OUT="$( cd "$d" && printf '%s\n' "$CASE_STDIN" | PATH="$CASE_PATH" "$BASH_BIN" "$HOOK" "$name" "$url" 2>&1 )" || RC=$?
}

# Assert RC == expected and (if non-empty) OUT contains substr.
assert_result() {
  local name="$1" exp_rc="$2" substr="$3"
  if [ "$RC" != "$exp_rc" ]; then
    err "$name" "expected exit $exp_rc, got exit $RC — output: $(printf '%s' "$OUT" | tr '\n' '|')"
    errors=$((errors + 1))
    return
  fi
  if [ -n "$substr" ]; then
    case "$OUT" in
      *"$substr"*) ;;
      *)
        err "$name" "exit $RC as expected but missing substring '$substr' — output: $(printf '%s' "$OUT" | tr '\n' '|')"
        errors=$((errors + 1))
        return
        ;;
    esac
  fi
  ok "$name" "exit $RC as expected$( [ -n "$substr" ] && printf ' (substring: %s)' "$substr" )"
}

assert_silent_pass() {
  local name="$1"
  if [ "$RC" = "0" ] && [ -z "$OUT" ]; then
    ok "$name" "silent pass (exit 0, no output)"
  else
    err "$name" "expected silent pass, got exit $RC output: $(printf '%s' "$OUT" | tr '\n' '|')"
    errors=$((errors + 1))
  fi
}

# --- Case 1: non-github remote passes silently -------------------------------
case_non_github_silent() {
  reset_case_env
  local d; d="$(new_repo)"
  run_hook "$d" origin "https://gitlab.com/o/r.git"
  assert_silent_pass "non-github-silent"
}

# --- Case 2: SKIP_GH_IDENTITY_GUARD=1 warns + allows -------------------------
case_skip_bypass() {
  reset_case_env
  local d; d="$(new_repo)"
  export SKIP_GH_IDENTITY_GUARD=1
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "skip-bypass" 0 "SKIP_GH_IDENTITY_GUARD=1"
}

# --- Case 3: gh missing from PATH -> fail closed ------------------------------
case_gh_missing() {
  reset_case_env
  local no_gh_path
  if ! no_gh_path="$(build_path_without "git cat tr" "gh")"; then
    skip "gh-missing" "could not resolve git/cat/tr on the real PATH — cannot construct a gh-free PATH"
    return
  fi
  local d; d="$(new_repo)"
  CASE_PATH="$no_gh_path"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "gh-missing" 2 "gh not on PATH"
}

# --- Case 4: gh probe error (FAKE_GH_FAIL) -> fail closed --------------------
case_probe_error() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "probe-error" 2 "could not determine active gh identity"
}

# --- Case 5: GH_IDENTITY_OVERRIDE invalid login format -> deny ---------------
case_override_invalid() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export GH_IDENTITY_OVERRIDE="not a valid login!"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "override-invalid" 1 "is not a valid GitHub username"
}

# --- Case 6: GH_IDENTITY_OVERRIDE valid but mismatched -> deny ---------------
case_override_mismatch() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export GH_IDENTITY_OVERRIDE="someone-else"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "override-mismatch" 1 "identity drift"
}

# --- Case 7: GH_TOKEN + FAKE_GH_ACCESS grants repo -> allow ------------------
case_token_access_allow() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export GH_TOKEN="fake-token"
  export FAKE_GH_ACCESS="o/r"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "token-access-allow" 0 "token identity can access"
}

# --- Case 8: GH_TOKEN + no access -> deny ------------------------------------
case_token_access_deny() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export GH_TOKEN="fake-token"
  export FAKE_GH_ACCESS="other/repo"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "token-access-deny" 1 "token identity cannot access"
}

# --- Case 9: .gh-expected-identity match -> allow -----------------------------
case_pin_match() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  printf 'octocat\n' > "$d/.gh-expected-identity"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "pin-match" 0 "matches expected"
}

# --- Case 10: .gh-expected-identity mismatch -> deny --------------------------
case_pin_mismatch() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  printf 'someone-else\n' > "$d/.gh-expected-identity"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "pin-mismatch" 1 "identity drift"
}

# --- Case 11: pin file with only comments/blanks -> deny ---------------------
case_pin_comments_only() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  printf '# just a comment\n\n   \n' > "$d/.gh-expected-identity"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "pin-comments-only" 1 "contains no valid GitHub login"
}

# --- Case 12: no pin file + accessibility ok -> allow -------------------------
case_no_pin_accessible() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export FAKE_GH_ACCESS="o/r"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "no-pin-accessible" 0 "accessibility check"
}

# --- Case 13: no pin file + accessibility fail -> deny ------------------------
case_no_pin_inaccessible() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export FAKE_GH_ACCESS=""
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "no-pin-inaccessible" 1 "cannot access"
}

# --- Cases 14-16: remote URL forms parse to the same owner/repo -------------
case_url_form_https() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export FAKE_GH_ACCESS="o/r"
  run_hook "$d" origin "https://github.com/o/r.git"
  assert_result "url-form-https" 0 "accessibility check"
}

case_url_form_scp() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export FAKE_GH_ACCESS="o/r"
  run_hook "$d" origin "git@github.com:o/r.git"
  assert_result "url-form-scp" 0 "accessibility check"
}

# ssh:// form also carries an explicit port, exercising the host:port split
# in extract_host()/parse_owner_repo() at the same time.
case_url_form_ssh() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export FAKE_GH_ACCESS="o/r"
  run_hook "$d" origin "ssh://git@github.com:22/o/r"
  assert_result "url-form-ssh-port" 0 "accessibility check"
}

# --- Case 17: trailing-dot host (absolute DNS form) is still github.com -----
# Uses the SKIP bypass as a probe-free way to distinguish "recognized as
# github.com and gated" (WARN + exit 0) from "not recognized, silent exit 0"
# (case 1's assertion) — both return exit 0, but only the gated path prints.
case_host_trailing_dot() {
  reset_case_env
  local d; d="$(new_repo)"
  export SKIP_GH_IDENTITY_GUARD=1
  run_hook "$d" origin "https://github.com./o/r.git"
  assert_result "host-trailing-dot" 0 "SKIP_GH_IDENTITY_GUARD=1"
}

# --- Case 18: host matched case-insensitively --------------------------------
case_host_case_insensitive() {
  reset_case_env
  local d; d="$(new_repo)"
  export SKIP_GH_IDENTITY_GUARD=1
  run_hook "$d" origin "https://GitHub.COM/o/r.git"
  assert_result "host-case-insensitive" 0 "SKIP_GH_IDENTITY_GUARD=1"
}

info "gh-identity-guard.sh (pre-push hook) acceptance tests"
case_non_github_silent
case_skip_bypass
case_gh_missing
case_probe_error
case_override_invalid
case_override_mismatch
case_token_access_allow
case_token_access_deny
case_pin_match
case_pin_mismatch
case_pin_comments_only
case_no_pin_accessible
case_no_pin_inaccessible
case_url_form_https
case_url_form_scp
case_url_form_ssh
case_host_trailing_dot
case_host_case_insensitive

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
