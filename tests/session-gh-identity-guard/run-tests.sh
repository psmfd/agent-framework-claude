#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for hooks/session-gh-identity-guard.sh (the
# PreToolUse hook; layer 1 of the gh-identity guard, ADR-054)
#
# Contract under test: stdin=JSON {"tool_name":"Bash","tool_input":{"command":
# "..."}}. Exit 0 = allow, 2 = deny (fail-closed on indeterminate identity).
#
# Coverage:
#   1. non-mutating `gh pr list` -> allow, AND proves no probe happened
#      (FAKE_GH_FAIL=1 set — a probe would flip this to deny if it fired)
#   2. `git push` mismatched identity (accessibility fail) -> deny
#   3. `gh pr create` mismatched identity (pin mismatch) -> deny
#   4. `gh api ... -X POST` is gated (FAKE_GH_FAIL flips it to deny -> proves
#      the identity probe actually ran)
#   5. `gh api ... --input file` (implicit POST) is gated, same technique
#   6. plain `gh api repos/o/r` GET -> allow without probe (FAKE_GH_FAIL set)
#   7. `git push --dry-run` is still gated (locks in documented behavior)
#   8. jq absent from PATH -> deny (fail closed)
#   9. SKIP_GH_IDENTITY_GUARD=1 -> allow with WARN
#  10. .gh-identity-allowlist command-substring match -> allow
#  11. GH_IDENTITY_OVERRIDE exported env var, matching login -> allow
#  12. GH_IDENTITY_OVERRIDE embedded as a literal (non-exported) command-string
#      prefix, mismatched -> MUST still deny (ADR-070 boundary: the command
#      string must not be able to self-certify the active login)
#  13. tool_name "Write" -> allow immediately (not a Bash/execute call)
#  14. empty tool_input.command -> allow
#  15. empty stdin -> allow
#  16. gh missing from PATH -> deny (fail closed)
#  17. GH_TOKEN + FAKE_GH_ACCESS grants repo -> allow
#  18. GH_TOKEN + no access -> deny
#  19. non-GitHub origin + mutating `git push` -> silent allow without probe
#      (host scoping via extract_host, fixed by #17; FAKE_GH_FAIL set)
#
# Each case builds a throwaway git repo (mktemp) with an `origin` remote set
# to the URL the case needs — the real developer repo and $HOME are never
# touched. The hook is invoked with an explicit bash binary (resolved once,
# before any PATH manipulation) so PATH-restriction cases exercise only the
# hook's own `command -v` lookups.
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (matches the hook's floor; no declare -A, no ${var,,},
# no mapfile). Run: bash tests/session-gh-identity-guard/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing
# case to report all results; failures are tracked via the `errors` counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-gh-identity-guard.sh"
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

# Build a synthetic PATH directory containing symlinks to the real resolved
# binaries named in $1 (space-separated command names — "gh" resolves to the
# fake gh shim, never the real gh), deliberately omitting $2. Real system
# directories routinely colocate git/jq/gh (e.g. Homebrew's bin, or /usr/bin
# on newer macOS), so searching existing directories for a "present but not
# that one" combination is host-layout-dependent and can fail to find any
# qualifying candidate. Symlinking exactly the wanted set into a throwaway
# directory is deterministic on any host. Prints the directory's path and
# returns 0; returns 1 only if a required command cannot be resolved at all
# (a genuine precondition gap, not a colocation artifact) — callers must SKIP
# the case in that fallback.
build_path_without() {
  local include="$1" exclude="$2" dir c src
  dir="$(mktemp -d)"
  TMPDIRS+=("$dir")
  for c in $include; do
    [ "$c" = "$exclude" ] && continue   # safety net: never symlink the excluded command
    if [ "$c" = "gh" ]; then
      src="$FIXTURES_BIN/gh"
    else
      src="$(command -v "$c" 2>/dev/null)" || return 1
    fi
    ln -s "$src" "$dir/$c"
  done
  printf '%s' "$dir"
}

new_repo() {
  # $1 = origin URL (default: a github.com https remote)
  local url="${1:-https://github.com/o/r.git}" d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "session-gh-identity-guard-test"
  git -C "$d" remote add origin "$url"
  printf '%s' "$d"
}

# Unset every guard-relevant env var and reset CASE_PATH. Called at the top
# of every case so cases never leak env state into each other. CASE_PATH
# (not the harness's own PATH) is what run_hook hands to the hook process —
# a case that wants a restricted PATH sets CASE_PATH, never PATH itself, so
# the harness's own subsequent commands (jq, tr, …) keep working regardless
# of what a case is testing.
reset_case_env() {
  unset SKIP_GH_IDENTITY_GUARD GH_IDENTITY_OVERRIDE GH_TOKEN GITHUB_TOKEN \
        FAKE_GH_LOGIN FAKE_GH_FAIL FAKE_GH_ACCESS
  CASE_PATH="$DEFAULT_PATH"
}

# Build the {"tool_name":...,"tool_input":{"command":...}} JSON payload via
# jq -n (the harness's real jq, unaffected by CASE_PATH) so command strings
# needing quotes/backslashes (case 12) are escaped correctly rather than
# hand-interpolated into a JSON literal.
mk_input() {
  local tool_name="$1" command="${2-}"
  jq -n --arg tn "$tool_name" --arg cmd "$command" '{tool_name: $tn, tool_input: {command: $cmd}}'
}

# Run the hook in repo $1 with stdin payload $2. Sets globals OUT (combined
# stdout+stderr) and RC (exit code). PATH is set only for the hook's own
# process (command prefix form), never assigned to the harness's PATH.
OUT="" RC=0
run_hook() {
  local d="$1" payload="$2"
  RC=0
  OUT="$( cd "$d" && printf '%s' "$payload" | PATH="$CASE_PATH" "$BASH_BIN" "$HOOK" 2>&1 )" || RC=$?
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

assert_silent_allow() {
  local name="$1"
  if [ "$RC" = "0" ] && [ -z "$OUT" ]; then
    ok "$name" "silent allow (exit 0, no output)"
  else
    err "$name" "expected silent allow, got exit $RC output: $(printf '%s' "$OUT" | tr '\n' '|')"
    errors=$((errors + 1))
  fi
}

# --- Case 1: non-mutating gh pr list -> allow; proves no probe happened -----
case_non_mutating_allow() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1   # a probe, if it fired, would flip this to deny
  run_hook "$d" "$(mk_input Bash 'gh pr list')"
  assert_silent_allow "non-mutating-no-probe"
}

# --- Case 2: git push, mismatched via accessibility fail -> deny ------------
case_git_push_mismatched() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export FAKE_GH_ACCESS=""
  run_hook "$d" "$(mk_input Bash 'git push origin main')"
  assert_result "git-push-mismatched" 2 "cannot access"
}

# --- Case 3: gh pr create, mismatched via pin file -> deny -------------------
case_pr_create_mismatched() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  printf 'someone-else\n' > "$d/.gh-expected-identity"
  run_hook "$d" "$(mk_input Bash 'gh pr create --title "x" --body "y"')"
  assert_result "pr-create-mismatched" 2 "identity drift"
}

# --- Case 4: gh api ... -X POST is gated ------------------------------------
# FAKE_GH_FAIL flips this to deny — the only way it can deny is if the
# mutating-op classifier fired and the hook actually probed identity.
case_api_post_gated() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1
  run_hook "$d" "$(mk_input Bash 'gh api repos/o/r/dispatches -X POST')"
  assert_result "api-post-gated" 2 "could not determine active gh identity"
}

# --- Case 5: gh api ... --input file (implicit POST) is gated --------------
case_api_implicit_post_gated() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1
  run_hook "$d" "$(mk_input Bash 'gh api repos/o/r/dispatches --input payload.json')"
  assert_result "api-implicit-post-gated" 2 "could not determine active gh identity"
}

# --- Case 6: plain gh api GET -> allow without probe ------------------------
case_api_get_not_gated() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1   # would flip to deny if a probe fired
  run_hook "$d" "$(mk_input Bash 'gh api repos/o/r')"
  assert_silent_allow "api-get-not-gated"
}

# --- Case 7: git push --dry-run is still gated ------------------------------
case_dry_run_still_gated() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export FAKE_GH_ACCESS=""
  run_hook "$d" "$(mk_input Bash 'git push --dry-run origin main')"
  assert_result "dry-run-still-gated" 2 "cannot access"
}

# --- Case 8: jq absent from PATH -> deny (fail closed) ----------------------
case_jq_missing() {
  reset_case_env
  local no_jq_path
  if ! no_jq_path="$(build_path_without "git cat gh" "jq")"; then
    skip "jq-missing" "could not resolve git/cat on the real PATH — cannot construct a jq-free PATH"
    return
  fi
  local d; d="$(new_repo)"
  CASE_PATH="$no_jq_path"
  run_hook "$d" "$(jq -n '{tool_name:"Bash",tool_input:{command:"git push origin main"}}')"
  assert_result "jq-missing" 2 "jq not on PATH"
}

# --- Case 9: SKIP_GH_IDENTITY_GUARD=1 -> allow with WARN --------------------
case_skip_bypass() {
  reset_case_env
  local d; d="$(new_repo)"
  export SKIP_GH_IDENTITY_GUARD=1
  run_hook "$d" "$(mk_input Bash 'git push origin main')"
  assert_result "skip-bypass" 0 "SKIP_GH_IDENTITY_GUARD=1"
}

# --- Case 10: .gh-identity-allowlist substring match -> allow ---------------
case_allowlist_match() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1   # would flip to deny if a probe fired
  printf 'special-allowed-op\n' > "$d/.gh-identity-allowlist"
  run_hook "$d" "$(mk_input Bash 'git push origin special-allowed-op-branch')"
  assert_silent_allow "allowlist-match"
}

# --- Case 11: GH_IDENTITY_OVERRIDE exported env var, matching -> allow -----
case_override_env_match() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export GH_IDENTITY_OVERRIDE="octocat"
  run_hook "$d" "$(mk_input Bash 'git push origin main')"
  assert_silent_allow "override-env-match"
}

# --- Case 12: GH_IDENTITY_OVERRIDE as a literal (non-exported) command-string
# prefix, mismatched -> MUST still deny (ADR-070). The override is embedded
# in the COMMAND STRING ONLY — never exported into this process's env — so
# the hook parses it as ordinary command text, not as an env assignment.
case_override_string_prefix_denied() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="someone-else"   # deliberately not "octocat"
  export FAKE_GH_ACCESS=""
  # GH_IDENTITY_OVERRIDE is NOT exported above — it appears only inside the
  # command string passed to the hook.
  run_hook "$d" "$(mk_input Bash 'GH_IDENTITY_OVERRIDE=octocat git push origin main')"
  assert_result "override-string-prefix-denied" 2 "cannot access"
}

# --- Case 13: tool_name "Write" -> allow immediately ------------------------
case_non_bash_tool_allowed() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1   # would flip to deny if the hook engaged at all
  run_hook "$d" '{"tool_name":"Write","tool_input":{"file_path":"x","content":"git push"}}'
  assert_silent_allow "non-bash-tool-allowed"
}

# --- Case 14: empty tool_input.command -> allow -----------------------------
case_empty_command_allowed() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1
  run_hook "$d" "$(mk_input Bash '')"
  assert_silent_allow "empty-command-allowed"
}

# --- Case 15: empty stdin -> allow ------------------------------------------
case_empty_stdin_allowed() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_FAIL=1
  run_hook "$d" ""
  assert_silent_allow "empty-stdin-allowed"
}

# --- Case 16: gh missing from PATH -> deny (fail closed) --------------------
case_gh_missing() {
  reset_case_env
  local no_gh_path
  # tr is required since #17: the host-scope check (extract_host) runs before
  # the gh-availability check and pipes through tr — without it the scope
  # check cannot classify the origin and the deny under test is never reached.
  if ! no_gh_path="$(build_path_without "git jq cat tr" "gh")"; then
    skip "gh-missing" "could not resolve git/jq/cat/tr on the real PATH — cannot construct a gh-free PATH"
    return
  fi
  local d; d="$(new_repo)"
  CASE_PATH="$no_gh_path"
  run_hook "$d" "$(jq -n '{tool_name:"Bash",tool_input:{command:"git push origin main"}}')"
  assert_result "gh-missing" 2 "gh not on PATH"
}

# --- Case 17: GH_TOKEN + FAKE_GH_ACCESS grants repo -> allow ----------------
case_token_access_allow() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export GH_TOKEN="fake-token"
  export FAKE_GH_ACCESS="o/r"
  run_hook "$d" "$(mk_input Bash 'git push origin main')"
  assert_silent_allow "token-access-allow"
}

# --- Case 18: GH_TOKEN + no access -> deny -----------------------------------
case_token_access_deny() {
  reset_case_env
  local d; d="$(new_repo)"
  export FAKE_GH_LOGIN="octocat"
  export GH_TOKEN="fake-token"
  export FAKE_GH_ACCESS="other/repo"
  run_hook "$d" "$(mk_input Bash 'git push origin main')"
  assert_result "token-access-deny" 2 "token identity cannot access"
}

# --- Case 19: non-GitHub origin + mutating git push -> silent allow ---------
#
# Fixed by #17: the session hook now scopes itself to github.com origins via
# extract_host() (byte-identical with the pre-push hook's copy — enforced by
# the ADR-083 lockstep-duplication gate in validate.sh) before any identity
# resolution. A mutating op against a GitLab / Azure DevOps / self-hosted
# origin passes through silently instead of being probed against github.com's
# API for a same-named repo that does not live there.
#
# FAKE_GH_FAIL=1 is the proof mechanism (same technique as cases 1, 6, 10,
# 13, 14, 15): any gh probe would flip this to a deny, so a silent allow
# proves extract_host short-circuited before any gh call fired.
case_special_non_github_origin() {
  reset_case_env
  local d; d="$(new_repo "git@gitlab.example.com:owner/repo.git")"
  export FAKE_GH_FAIL=1   # a probe, if it fired, would flip this to deny
  run_hook "$d" "$(mk_input Bash 'git push origin main')"
  assert_silent_allow "special-non-github-origin"
}

info "session-gh-identity-guard.sh (PreToolUse hook) acceptance tests"
case_non_mutating_allow
case_git_push_mismatched
case_pr_create_mismatched
case_api_post_gated
case_api_implicit_post_gated
case_api_get_not_gated
case_dry_run_still_gated
case_jq_missing
case_skip_bypass
case_allowlist_match
case_override_env_match
case_override_string_prefix_denied
case_non_bash_tool_allowed
case_empty_command_allowed
case_empty_stdin_allowed
case_gh_missing
case_token_access_allow
case_token_access_deny
case_special_non_github_origin

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
