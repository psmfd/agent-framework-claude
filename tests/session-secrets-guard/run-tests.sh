#!/usr/bin/env bash
#
# run-tests.sh — fixture harness for hooks/session-secrets-guard.sh (PreToolUse
# in-session secrets guard, layer 2 of ADR-053)
#
# Drives the hook directly over its stdin JSON contract (Claude tool_name /
# tool_input, and the Copilot toolName / toolInput aliases) rather than
# git-staged content — the hook has no git dependency of its own except the
# allowlist lookup (git rev-parse --show-toplevel), so most cases run in a
# plain throwaway directory; only the allowlist case needs a git repo.
#
# Coverage:
#   Bash branch    — inline secret literal, sensitive credential-file read
#                     (incl. ~/.config/expertise-search/config, ADR-094),
#                     JWT + Authorization:Bearer literals incl. lowercase
#                     casing (ADR-095), bearer placeholder passes,
#                     clean command passes, secret beyond the 512 KB scan cap
#                     is NOT caught (documented accepted gap, ADR-053)
#   Write branch   — sensitive path (id_rsa) blocked regardless of content,
#                     Authorization:Bearer content blocked (ADR-095),
#                     vault-named file without/with the $ANSIBLE_VAULT header,
#                     PKCS#8 ENCRYPTED PRIVATE KEY content, missing file_path
#                     fails CLOSED, .secrets-guard-allowlist and skip-pattern
#                     overrides
#   Edit branch    — secret in new_string denied; secret ONLY in old_string
#                     (replaced text) is never scanned and must ALLOW — this
#                     locks the "removal is never blocked" design
#   MultiEdit      — a secret in any edit's new_string denies the whole call
#   NotebookEdit   — edit_mode=delete short-circuits before the content scan
#                     (allows even with a secret in new_source); insert mode
#                     scans new_source normally
#   Cross-cutting  — SKIP_SECRETS_GUARD=1 bypass, jq-absent fails CLOSED
#                     (exit 2), tool_name Read bypassed immediately, Copilot
#                     alias tool names (execute/create_file), empty stdin
#
# Secret material (AWS access key ID, PKCS#8 encrypted-key header) is
# assembled at runtime — no secret-shaped literal appears in this source file
# — mirroring tests/secrets-guard/run-tests.sh, since this repo's own guards
# scan committed content.
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (the hook's floor). Run: bash tests/session-secrets-guard/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing case
# to report all results; failures are tracked via the `errors` counter instead.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/session-secrets-guard.sh"

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
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }

# --- Sandbox helpers ---

new_plain_dir() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  printf '%s' "$d"
}

new_repo() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "session-secrets-guard-test"
  printf '%s' "$d"
}

# Stdin payload file, reused across the (sequential) runner calls. Feed the
# hook via file redirection, never `printf | hook`: on the SKIP_SECRETS_GUARD
# path the hook exits before `INPUT="$(cat)"`, so under pipefail the printf
# side can lose the pipe-close race (EPIPE) and poison the pipeline result —
# the bash-3.2 CI failure diagnosed in PR #59 and swept in #60 (this sibling
# suite was missed; hardened per the pre-v0.4.0 review).
INFILE="$(mktemp)"
TMPDIRS+=("$INFILE")

# Run the hook in dir $1 with stdin JSON $2. Prints the exit code.
run_hook() {
  local d="$1" json="$2" rc=0
  printf '%s' "$json" > "$INFILE"
  ( cd "$d" && bash "$HOOK" < "$INFILE" >/dev/null 2>&1 ) || rc=$?
  printf '%s' "$rc"
}

# Run the hook in dir $1 with stdin JSON $2 and one extra env assignment $3
# (e.g. "SKIP_SECRETS_GUARD=1"). Prints the exit code.
run_hook_env() {
  local d="$1" json="$2" envset="$3" rc=0
  printf '%s' "$json" > "$INFILE"
  ( cd "$d" && env "$envset" bash "$HOOK" < "$INFILE" >/dev/null 2>&1 ) || rc=$?
  printf '%s' "$rc"
}

expect_deny() {
  local name="$1" rc="$2"
  if [ "$rc" = "2" ]; then ok "$name" "denied (exit 2) as expected"
  else err "$name" "expected deny (exit 2), got exit $rc"; errors=$((errors+1)); fi
}

expect_allow() {
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then ok "$name" "allowed (exit 0) as expected"
  else err "$name" "expected allow (exit 0), got exit $rc"; errors=$((errors+1)); fi
}

# --- Runtime-assembled fake secrets (no secret-shaped literal in source) ---

# Fake AWS access key id (matches the AWS pattern). Brace expansion avoids a
# `seq` dependency so the suite runs on minimal images.
aws_fake() { printf 'AKIA%s' "$(printf 'A%.0s' {1..16})"; }

# Fake PKCS#8 encrypted private-key header — the `-----BEGIN ENCRYPTED
# PRIVATE KEY` literal is not contiguous in this source; the word is
# interpolated via %s.
pkcs8_fake() { printf -- '-----BEGIN %s PRIVATE KEY-----\nMIICfiller0000\n-----END %s PRIVATE KEY-----\n' "ENCRYPTED" "ENCRYPTED"; }

# Fake signed JWT assembled at runtime (the eyJ prefixes are interpolated via
# %s so no JWT-shaped literal appears in this source — which also keeps CI
# gitleaks' own JWT rule off the suite). ADR-095.
jwt_fake() { printf '%sJhbGciOiJIUzI1NiJ9.%sJzdWIiOiIxMjM0In0.c2lnbmF0dXJlc2ln' "ey" "ey"; }

# Fake bearer header (header name interpolated via %s for the same reason). ADR-095.
bearer_fake() { printf '%s: Bearer abcdef1234567890ABCDEF12345' "Authorization"; }

# --- JSON fixture builders (jq -n handles escaping; no manual quoting) ---

json_bash()            { jq -nc --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'; }
json_write()           { jq -nc --arg fp "$1" --arg content "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$content}}'; }
json_write_nopath()    { jq -nc --arg content "$1" '{tool_name:"Write", tool_input:{content:$content}}'; }
json_edit()            { jq -nc --arg fp "$1" --arg old "$2" --arg new "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$old, new_string:$new}}'; }
json_multiedit()       { jq -nc --arg fp "$1" --arg o1 "$2" --arg n1 "$3" --arg o2 "$4" --arg n2 "$5" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:$o1,new_string:$n1},{old_string:$o2,new_string:$n2}]}}'; }
json_notebook()        { jq -nc --arg np "$1" --arg mode "$2" --arg src "$3" '{tool_name:"NotebookEdit", tool_input:{notebook_path:$np, edit_mode:$mode, new_source:$src}}'; }
json_read()            { jq -nc --arg fp "$1" '{tool_name:"Read", tool_input:{file_path:$fp}}'; }
json_execute()         { jq -nc --arg cmd "$1" '{tool_name:"execute", toolInput:{command:$cmd}}'; }
json_create_file()     { jq -nc --arg fp "$1" --arg content "$2" '{tool_name:"create_file", toolInput:{file_path:$fp, content:$content}}'; }

# ============================== Bash branch ================================

case_bash_aws_key() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_bash "echo $(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "bash-aws-key" "$rc"
}

case_bash_sensitive_path() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_bash 'cat ~/.aws/credentials')"
  rc="$(run_hook "$d" "$json")"
  expect_deny "bash-sensitive-path" "$rc"
}

case_bash_clean() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_bash 'echo hello world')"
  rc="$(run_hook "$d" "$json")"
  expect_allow "bash-clean" "$rc"
}

# The /expertise credential file is a sensitive path (ADR-094); reading it in a
# Bash command must be denied like the other credential-file classes.
case_bash_expertise_config() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_bash 'cat ~/.config/expertise-search/config')"
  rc="$(run_hook "$d" "$json")"
  expect_deny "bash-expertise-config" "$rc"
}

# Lowercase header/scheme casing must still match (RFC 7230 header names are
# case-insensitive; the Bearer detector was made case-tolerant in the
# pre-v0.4.0 review).
case_bash_bearer_lowercase() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_bash 'echo "authorization: bearer abcdef1234567890ABCDEF12345"')"
  rc="$(run_hook "$d" "$json")"
  expect_deny "bash-bearer-lowercase" "$rc"
}

# Documented accepted gap (ADR-053): contains_secret scans only the first
# 512 KB. A secret positioned after that boundary is NOT caught. This case
# locks the gap as known/expected rather than an unnoticed regression.
case_bash_secret_beyond_cap() {
  local d json rc pad cmd
  d="$(new_plain_dir)"
  pad="$(head -c 600000 /dev/zero | tr '\0' 'a')"
  cmd="echo ${pad} $(aws_fake)"
  json="$(json_bash "$cmd")"
  rc="$(run_hook "$d" "$json")"
  expect_allow "bash-beyond-cap" "$rc"
}

case_bash_jwt() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_bash "curl -H '$(jwt_fake)' http://127.0.0.1:8080/x")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "bash-jwt" "$rc"
}

# Placeholder-shaped bearer construction must NOT deny (false-positive control):
# the command builds the header from a variable, so no 20+ token-char literal
# follows "Bearer" in the command string (ADR-095).
case_bash_bearer_placeholder() {
  local d json rc
  d="$(new_plain_dir)"
  # shellcheck disable=SC2016  # single quotes intentional — literal $TOKEN placeholder for the false-positive control
  json="$(json_bash 'printf "%s: Bearer %s" Authorization "$TOKEN"')"
  rc="$(run_hook "$d" "$json")"
  expect_allow "bash-bearer-placeholder" "$rc"
}

# ============================== Write branch ================================

case_write_bearer() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_write "$d/notes.md" "auth header: $(bearer_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "write-bearer" "$rc"
}

case_write_id_rsa() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_write "$d/home/.ssh/id_rsa" "just some innocuous text")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "write-id-rsa" "$rc"
}

case_write_vault_no_header() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_write "config/vault.yml" 'db_password: hunter2')"
  rc="$(run_hook "$d" "$json")"
  expect_deny "write-vault-no-header" "$rc"
}

case_write_vault_with_header() {
  local d json rc content
  d="$(new_plain_dir)"
  content=$'$ANSIBLE_VAULT;1.1;AES256\n66653136\n'
  json="$(json_write "config/vault.yml" "$content")"
  rc="$(run_hook "$d" "$json")"
  expect_allow "write-vault-with-header" "$rc"
}

case_write_pkcs8_pem() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_write "notes.txt" "$(pkcs8_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "write-pkcs8-pem" "$rc"
}

case_write_missing_path() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_write_nopath "hello")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "write-missing-path" "$rc"
}

case_allowlist_match() {
  local d json rc
  d="$(new_repo)"
  printf 'secrets/*.txt\n' > "$d/.secrets-guard-allowlist"
  json="$(json_write "secrets/found.txt" "$(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_allow "allowlist-match" "$rc"
}

case_skip_pattern() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_write "config/creds.example" "$(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_allow "skip-pattern" "$rc"
}

# ============================== Edit branch ================================

case_edit_secret_new() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_edit "app.py" "old clean text" "$(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "edit-secret-new" "$rc"
}

# Locks the "removal is never blocked" design: old_string carries the secret
# (the thing being deleted), new_string is clean — must ALLOW.
case_edit_secret_old_only() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_edit "app.py" "$(aws_fake)" "clean replacement text")"
  rc="$(run_hook "$d" "$json")"
  expect_allow "edit-secret-old-only" "$rc"
}

# ============================== MultiEdit branch ============================

case_multiedit_second_secret() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_multiedit "app.py" "old1" "clean new text" "old2" "$(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "multiedit-second-secret" "$rc"
}

# ============================== NotebookEdit branch =========================

case_notebook_delete_secret() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_notebook "nb.ipynb" "delete" "$(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_allow "notebook-delete-secret" "$rc"
}

case_notebook_insert_secret() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_notebook "nb.ipynb" "insert" "$(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "notebook-insert-secret" "$rc"
}

# ============================== Cross-cutting ===============================

case_read_bypass() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_read "$d/home/.ssh/id_rsa")"
  rc="$(run_hook "$d" "$json")"
  expect_allow "read-bypass" "$rc"
}

case_copilot_execute_secret() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_execute "echo $(aws_fake)")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "copilot-execute-secret" "$rc"
}

case_copilot_create_file_sensitive() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_create_file "$d/home/.ssh/id_rsa" "innocuous content")"
  rc="$(run_hook "$d" "$json")"
  expect_deny "copilot-create-file-sensitive" "$rc"
}

case_empty_stdin() {
  local d rc
  d="$(new_plain_dir)"
  rc="$(run_hook "$d" "")"
  expect_allow "empty-stdin" "$rc"
}

case_skip_env() {
  local d json rc
  d="$(new_plain_dir)"
  json="$(json_write "$d/home/.ssh/id_rsa" "$(aws_fake)")"
  rc="$(run_hook_env "$d" "$json" "SKIP_SECRETS_GUARD=1")"
  expect_allow "skip-env" "$rc"
}

# jq missing from PATH must fail CLOSED (exit 2), not fail open. Builds a
# minimal PATH containing only `cat` (the one external tool the hook invokes
# before the jq dependency check) so `bash` and `git` remain resolvable via
# their absolute paths, but `jq` is unresolvable.
case_jq_absent() {
  local d json rc bashbin fakebin
  d="$(new_plain_dir)"
  bashbin="$(command -v bash)"
  fakebin="$(mktemp -d)"
  TMPDIRS+=("$fakebin")
  ln -s "$(command -v cat)" "$fakebin/cat"
  json="$(json_write "$d/home/.ssh/id_rsa" "hello")"
  rc=0
  printf '%s' "$json" > "$INFILE"
  ( cd "$d" && env -i PATH="$fakebin" "$bashbin" "$HOOK" < "$INFILE" >/dev/null 2>&1 ) || rc=$?
  expect_deny "jq-absent" "$rc"
}

info "session-secrets-guard PreToolUse fixture tests"

case_bash_aws_key
case_bash_sensitive_path
case_bash_clean
case_bash_expertise_config
case_bash_bearer_lowercase
case_bash_secret_beyond_cap
case_bash_jwt
case_bash_bearer_placeholder
case_write_bearer
case_write_id_rsa
case_write_vault_no_header
case_write_vault_with_header
case_write_pkcs8_pem
case_write_missing_path
case_allowlist_match
case_skip_pattern
case_edit_secret_new
case_edit_secret_old_only
case_multiedit_second_secret
case_notebook_delete_secret
case_notebook_insert_secret
case_read_bypass
case_copilot_execute_secret
case_copilot_create_file_sensitive
case_empty_stdin
case_skip_env
case_jq_absent

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
