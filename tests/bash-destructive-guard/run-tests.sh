#!/usr/bin/env bash
#
# run-tests.sh — fixture harness for hooks/bash-destructive-guard.sh (PreToolUse
# rm/mv/find-destructor guard)
#
# Drives the hook directly over its stdin JSON contract (Claude tool_name /
# tool_input.command, and the Copilot toolName / toolInput.command aliases)
# rather than any git or filesystem fixture — the hook's only external state is
# $HOME/.claude/bash-guard-safe-paths.conf, so every invocation below pins HOME
# to a throwaway directory and never touches the real developer config.
#
# Coverage:
#   Compound     — && / ; / newline segment splitting denies any rm/mv segment
#                  outright; rm appearing as an argument (not the verb) of a
#                  non-destructive command in a pipeline is not flagged
#   Wrapper-verb — env/sudo/env-VAR=val resolve through to the canonical verb;
#                  git rm / grep rm are not flagged (canonical verb is git/grep,
#                  not rm); the resolver's depth cap (8, read from the hook's
#                  `while (( guard < 8 ))`) is locked at both boundaries — 8
#                  stacked env wrappers still resolve to rm and deny; 9 (and
#                  far deeper) stacks exceed the cap and are denied outright
#                  as "wrapper chain too deep" (fail closed, fixed by #20 —
#                  previously the unresolved chain was silently allowed).
#   find         — -delete / -exec rm / -execdir rm denied; a plain find allowed
#   Safe-path    — default safe list is /tmp only; absolute paths outside it are
#                  denied; relative paths and .. traversal; shell-metacharacter
#                  paths (command substitution); a configured safe path is
#                  honored, including when comments/blank lines are interleaved
#                  in the conf file; shell-interpreter `-c` is denied outright
#   Plumbing     — jq absent fails CLOSED (exit 2); a non-Bash/execute tool_name
#                  is allowed immediately without inspecting the command; an
#                  empty command or empty stdin is allowed; the Copilot
#                  toolName/toolInput.command alias is honored
#
# Secret-shaped material is not applicable to this hook — no runtime-assembled
# fixtures are needed (contrast tests/secrets-guard, tests/session-secrets-guard).
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (the hook's floor). Run: bash tests/bash-destructive-guard/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing case
# to report all results; failures are tracked via the `errors` counter instead.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/bash-destructive-guard.sh"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
TMPDIRS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local d; for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

command -v jq >/dev/null 2>&1 || { err "env" "jq is required but not on PATH"; exit 2; }
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }

# --- Sandbox helpers ---

# A throwaway HOME with no ~/.claude/bash-guard-safe-paths.conf — the hook
# falls back to its built-in default safe list (/tmp only).
new_home() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  printf '%s' "$d"
}

# A throwaway HOME with a populated ~/.claude/bash-guard-safe-paths.conf
# containing $2 as its content.
new_home_with_conf() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  mkdir -p "$d/.claude"
  printf '%s' "$1" > "$d/.claude/bash-guard-safe-paths.conf"
  printf '%s' "$d"
}

# --- JSON fixture builders (jq -n handles escaping; no manual quoting) ---

json_bash()    { jq -nc --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'; }
json_execute() { jq -nc --arg cmd "$1" '{tool_name:"execute", toolInput:{command:$cmd}}'; }

# Repeats the literal token "env " $1 times (bash 3.2-safe arithmetic for-loop,
# no seq dependency) — used to probe the wrapper-verb resolver's depth cap.
repeat_env() {
  local n="$1" out="" i
  for ((i = 0; i < n; i++)); do out="${out}env "; done
  printf '%s' "$out"
}

# Runs the hook with HOME=$1 and stdin JSON $2. Sets globals RC and OUT (not a
# command substitution, so both survive into the caller).
RC=0
OUT=""
run_hook() {
  local home="$1" json="$2"
  RC=0
  OUT="$(HOME="$home" bash "$HOOK" <<<"$json" 2>&1)" || RC=$?
}

# Runs the hook with truly empty stdin (no JSON at all).
run_hook_empty_stdin() {
  local home="$1"
  RC=0
  OUT="$(HOME="$home" bash "$HOOK" < /dev/null 2>&1)" || RC=$?
}

expect_deny() {
  local name="$1" substr="$2"
  if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -qF "$substr"; then
    ok "$name" "denied (exit 2) with expected message"
  elif [ "$RC" = "2" ]; then
    err "$name" "denied (exit 2) but message did not contain '$substr' — got: $OUT"
    errors=$((errors + 1))
  else
    err "$name" "expected deny (exit 2), got exit $RC — out: $OUT"
    errors=$((errors + 1))
  fi
}

expect_allow() {
  local name="$1"
  if [ "$RC" = "0" ] && ! printf '%s' "$OUT" | grep -qF "denied"; then
    ok "$name" "allowed (exit 0), no denial message"
  else
    err "$name" "expected allow (exit 0, no denial), got exit $RC — out: $OUT"
    errors=$((errors + 1))
  fi
}

# ================================ Compound ==================================

case_compound_and() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'echo hi && rm /etc/passwd')"
  expect_deny "compound-and" "compound command contains 'rm'"
}

# rm appears as an ARGUMENT to grep, not as the canonical verb of its segment —
# the pipeline must be allowed.
case_pipe_arg_not_verb() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'ls | grep rm')"
  expect_allow "pipe-arg-not-verb"
}

case_compound_semicolon() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'ls; rm /etc/passwd')"
  expect_deny "compound-semicolon" "compound command contains 'rm'"
}

case_newline_compound() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash $'echo hi\nrm /etc/passwd')"
  expect_deny "newline-compound" "compound command contains 'rm'"
}

# ============================== Wrapper-verb =================================

case_wrap_env() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'env rm /etc/passwd')"
  expect_deny "wrap-env" "path is outside safe list"
}

case_wrap_sudo() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'sudo rm /etc/passwd')"
  expect_deny "wrap-sudo" "path is outside safe list"
}

case_wrap_env_assignment() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'env FOO=bar rm /etc/passwd')"
  expect_deny "wrap-env-assignment" "path is outside safe list"
}

# The canonical verb is git, not rm — git's own subcommand named "rm" is not
# the destructive coreutils rm and must not be flagged.
case_git_rm_allowed() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'git rm somefile')"
  expect_allow "git-rm-allowed"
}

# The canonical verb is grep, not rm — "rm" here is grep's pattern argument.
case_grep_rm_allowed() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'grep rm file.txt')"
  expect_allow "grep-rm-allowed"
}

# Depth-cap boundary, AT the cap: the resolver's `while (( guard < 8 ))` loop
# (hooks/bash-destructive-guard.sh) resolves exactly 8 stacked wrapper verbs.
# 8 stacked `env` before `rm` still resolves the canonical verb to rm and denies.
case_wrap_depth_cap_at_limit() {
  local home cmd
  home="$(new_home)"
  cmd="$(repeat_env 8)rm /etc/passwd"
  run_hook "$home" "$(json_bash "$cmd")"
  expect_deny "wrap-depth-cap-at-limit" "path is outside safe list"
}

# Depth-cap boundary, EXCEEDED: 9 stacked `env` before `rm` overruns the
# resolver's 8-iteration cap, leaving cverb pointing at an unconsumed wrapper
# token. Fixed by #20: the hook now fails closed — an unresolved wrapper
# chain is denied as "wrapper chain too deep" instead of silently allowing
# the unreached `rm`.
case_wrap_depth_cap_exceeded() {
  local home cmd
  home="$(new_home)"
  cmd="$(repeat_env 9)rm /etc/passwd"
  run_hook "$home" "$(json_bash "$cmd")"
  expect_deny "wrap-depth-cap-exceeded" "wrapper chain too deep"
}

# Deep stack well past the boundary: proves the fail-closed deny is the cap
# behavior itself, not an off-by-one artifact specific to exactly 9 wrappers.
case_wrap_depth_cap_deep_stack() {
  local home cmd
  home="$(new_home)"
  cmd="$(repeat_env 20)rm /etc/passwd"
  run_hook "$home" "$(json_bash "$cmd")"
  expect_deny "wrap-depth-cap-deep-stack" "wrapper chain too deep"
}

# ================================== find ====================================

case_find_delete() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash "find /tmp -name '*.bak' -delete")"
  expect_deny "find-delete" "find -delete is not permitted"
}

case_find_exec_rm() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'find /tmp -exec rm {} \;')"
  expect_deny "find-exec-rm" "find -exec rm is not permitted"
}

case_find_execdir_rm() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'find . -execdir rm {} \;')"
  expect_deny "find-execdir-rm" "find -exec rm is not permitted"
}

case_find_plain_allowed() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash "find /tmp -name '*.txt'")"
  expect_allow "find-plain-allowed"
}

# ================================ Safe-path ==================================

# Default safe list (no config file) is /tmp only.
case_rm_tmp_default_safe() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'rm /tmp/foo')"
  expect_allow "rm-tmp-default-safe"
}

case_rm_etc_denied() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'rm /etc/passwd')"
  expect_deny "rm-etc-denied" "path is outside safe list"
}

# Relative paths are allowed outright (the .. traversal check runs first and
# would still deny a relative path that traverses upward).
case_rm_relative_allowed() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'rm foo.txt')"
  expect_allow "rm-relative-allowed"
}

case_rm_traversal_denied() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'rm ../../etc/passwd')"
  expect_deny "rm-traversal-denied" "contains '..' traversal"
}

# Command-substitution backticks in a path argument are a shell metacharacter.
case_rm_backtick_metachar_denied() {
  local home
  home="$(new_home)"
  # shellcheck disable=SC2016  # literal backtick text intended as data, not a
  # command substitution — it must not expand in this shell before reaching jq.
  run_hook "$home" "$(json_bash 'rm `id`')"
  expect_deny "rm-backtick-metachar-denied" "contains shell metacharacters"
}

case_bash_c_interpreter_denied() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_bash 'bash -c "rm -rf /"')"
  expect_deny "bash-c-interpreter-denied" "shell interpreter with -c is not permitted"
}

# A path under a configured safe directory is allowed.
case_rm_configured_safepath_allowed() {
  local home
  home="$(new_home_with_conf $'/opt/myproject\n')"
  run_hook "$home" "$(json_bash 'rm /opt/myproject/x')"
  expect_allow "rm-configured-safepath-allowed"
}

# Comments and blank lines interleaved before/after the real entry must not
# break the config parse — a different safe path, at a nested depth, still
# resolves correctly.
case_rm_configured_safepath_comments_blanks() {
  local home conf
  conf=$'# top comment\n\n   \n/srv/data\n# trailing comment\n\n'
  home="$(new_home_with_conf "$conf")"
  run_hook "$home" "$(json_bash 'rm /srv/data/nested/thing.txt')"
  expect_allow "rm-configured-safepath-comments-blanks"
}

# ================================ Plumbing ===================================

# jq missing from PATH must fail CLOSED (exit 2), not fail open. Builds a
# minimal PATH containing only `cat` (the one external tool the hook invokes
# before the jq dependency check) so `bash` remains resolvable via its
# absolute path, but `jq` is unresolvable.
case_jq_absent() {
  local home bashbin fakebin
  home="$(new_home)"
  bashbin="$(command -v bash)"
  fakebin="$(mktemp -d)"
  TMPDIRS+=("$fakebin")
  ln -s "$(command -v cat)" "$fakebin/cat"
  RC=0
  OUT="$(printf '%s' "$(json_bash 'rm /etc/passwd')" | env -i PATH="$fakebin" HOME="$home" "$bashbin" "$HOOK" 2>&1)" || RC=$?
  expect_deny "jq-absent" "jq not on PATH"
}

# A tool_name other than Bash/execute is allowed immediately — the command is
# never even inspected.
case_toolname_write_allowed() {
  local home
  home="$(new_home)"
  run_hook "$home" '{"tool_name":"Write","tool_input":{"command":"rm /etc/passwd"}}'
  expect_allow "toolname-write-allowed"
}

case_empty_command_allowed() {
  local home
  home="$(new_home)"
  run_hook "$home" '{"tool_name":"Bash","tool_input":{"command":""}}'
  expect_allow "empty-command-allowed"
}

case_empty_stdin_allowed() {
  local home
  home="$(new_home)"
  run_hook_empty_stdin "$home"
  expect_allow "empty-stdin-allowed"
}

# Copilot's execute/toolInput.command alias must be honored identically to
# Claude's Bash/tool_input.command.
case_copilot_execute_alias_denied() {
  local home
  home="$(new_home)"
  run_hook "$home" "$(json_execute 'rm /etc/passwd')"
  expect_deny "copilot-execute-alias-denied" "path is outside safe list"
}

info "bash-destructive-guard PreToolUse fixture tests"

case_compound_and
case_pipe_arg_not_verb
case_compound_semicolon
case_newline_compound
case_wrap_env
case_wrap_sudo
case_wrap_env_assignment
case_git_rm_allowed
case_grep_rm_allowed
case_wrap_depth_cap_at_limit
case_wrap_depth_cap_exceeded
case_wrap_depth_cap_deep_stack
case_find_delete
case_find_exec_rm
case_find_execdir_rm
case_find_plain_allowed
case_rm_tmp_default_safe
case_rm_etc_denied
case_rm_relative_allowed
case_rm_traversal_denied
case_rm_backtick_metachar_denied
case_bash_c_interpreter_denied
case_rm_configured_safepath_allowed
case_rm_configured_safepath_comments_blanks
case_jq_absent
case_toolname_write_allowed
case_empty_command_allowed
case_empty_stdin_allowed
case_copilot_execute_alias_denied

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
