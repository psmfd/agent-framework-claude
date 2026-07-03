#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for hooks/secrets-guard.sh staged-blob scanning
#
# Proves the staged-blob scan (ADR-059, supersedes ADR-047) catches
# stage-then-clean bypasses that the prior working-tree scan would miss:
#   1. staged secret with a cleaned working-tree copy
#   2. staged secret then removed from the working tree
#   3. vault file staged without a header, working tree given a valid header
#   4. file renamed into a vault name with an unencrypted body (ACMR filter)
#   5. PKCS#8 encrypted private-key header (the ENCRYPTED PRIVATE KEY alternative)
# Plus a positive control: a clean staged file must pass (no false positive).
#
# Each case builds a throwaway git repo and runs the hook against the staged
# state. Secret material is assembled at runtime — no secret literal in source.
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (the hook's floor). Run: bash tests/secrets-guard/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing case
# to report all results; failures are tracked via the `errors` counter instead.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/secrets-guard.sh"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
TMPDIRS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local d; for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

command -v git >/dev/null 2>&1 || { err "env" "git is required but not on PATH"; exit 2; }
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }

new_repo() {
  local d
  d="$(mktemp -d)"
  TMPDIRS+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "secrets-guard-test"
  printf '%s' "$d"
}

# Run the hook inside repo $1; print its exit code.
run_hook() {
  local d="$1" rc=0
  ( cd "$d" && bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
  printf '%s' "$rc"
}

# Fake AWS access key id assembled at runtime (matches the AWS pattern; no
# secret literal appears in this source file). Brace expansion avoids a `seq`
# dependency so the suite runs on minimal images.
aws_fake() { printf 'AKIA%s' "$(printf 'A%.0s' {1..16})"; }

# Fake PKCS#8 encrypted private-key header assembled at runtime (matches the
# `ENCRYPTED ` PEM alternative; the `-----BEGIN ENCRYPTED PRIVATE KEY` literal is
# not contiguous in this source — the word is interpolated via %s).
pkcs8_fake() { printf -- '-----BEGIN %s PRIVATE KEY-----\nMIICfiller0000\n-----END %s PRIVATE KEY-----\n' "ENCRYPTED" "ENCRYPTED"; }

# Fake signed JWT assembled at runtime (three base64url segments; the eyJ
# prefixes are interpolated via %s so no JWT-shaped literal appears in this
# source — which also keeps CI gitleaks' own JWT rule off the suite). ADR-095.
jwt_fake() { printf '%sJhbGciOiJIUzI1NiJ9.%sJzdWIiOiIxMjM0In0.c2lnbmF0dXJlc2ln\n' "ey" "ey"; }

# Fake bearer header (header name interpolated via %s for the same
# no-contiguous-literal reason). ADR-095.
bearer_fake() { printf '%s: Bearer abcdef1234567890ABCDEF12345\n' "Authorization"; }

expect_block() {
  local name="$1" rc="$2"
  if [ "$rc" = "1" ]; then ok "$name" "blocked (exit 1) as expected"
  else err "$name" "expected block (exit 1), got exit $rc — bypass not closed"; errors=$((errors+1)); fi
}

# Case 1 — staged secret, working-tree copy cleaned (not re-staged).
case_staged_clean() {
  local d; d="$(new_repo)"
  aws_fake > "$d/keys.txt"
  git -C "$d" add keys.txt
  printf 'no secret here\n' > "$d/keys.txt"
  expect_block "staged-clean" "$(run_hook "$d")"
}

# Case 2 — staged secret then removed from the working tree.
case_staged_deleted() {
  local d; d="$(new_repo)"
  aws_fake > "$d/keys.txt"
  git -C "$d" add keys.txt
  rm -f "$d/keys.txt"
  expect_block "staged-deleted" "$(run_hook "$d")"
}

# Case 3 — vault file staged WITHOUT a header; working tree given a valid header.
case_vault_header() {
  local d; d="$(new_repo)"
  printf 'db_password: hunter2\n' > "$d/vault.yml"
  git -C "$d" add vault.yml
  # shellcheck disable=SC2016  # literal $ANSIBLE_VAULT header text, not an expansion
  printf '$ANSIBLE_VAULT;1.1;AES256\n66653136\n' > "$d/vault.yml"
  expect_block "vault-header" "$(run_hook "$d")"
}

# Case 4 — file renamed into a vault name with an unencrypted body (ACMR).
case_rename_vault() {
  local d; d="$(new_repo)"
  printf 'db_password: hunter2\n' > "$d/data.txt"
  git -C "$d" add data.txt
  git -C "$d" commit -qm init
  git -C "$d" mv data.txt vault_prod.yml
  expect_block "rename-vault" "$(run_hook "$d")"
}

# Case 5 — PKCS#8 encrypted private-key header. Non-.pem filename so this exercises
# the SECRET_PATTERNS content match (the ENCRYPTED alternative), not the path rule.
case_pkcs8_encrypted() {
  local d; d="$(new_repo)"
  pkcs8_fake > "$d/notes.txt"
  git -C "$d" add notes.txt
  expect_block "pkcs8-encrypted" "$(run_hook "$d")"
}

# Case 7 — staged signed JWT (ADR-095).
case_jwt_blocked() {
  local d; d="$(new_repo)"
  jwt_fake > "$d/token.txt"
  git -C "$d" add token.txt
  expect_block "jwt-blocked" "$(run_hook "$d")"
}

# Case 8 — staged Authorization: Bearer literal (ADR-095).
case_bearer_blocked() {
  local d; d="$(new_repo)"
  bearer_fake > "$d/snippet.txt"
  git -C "$d" add snippet.txt
  expect_block "bearer-blocked" "$(run_hook "$d")"
}

# Case 9 — bearer format placeholders must NOT match (false-positive control).
case_bearer_placeholder_passes() {
  local d rc; d="$(new_repo)"
  printf '%s: Bearer %%s\n%s: Bearer <your-key>\n' "Authorization" "Authorization" > "$d/doc.md"
  git -C "$d" add doc.md
  rc="$(run_hook "$d")"
  if [ "$rc" = "0" ]; then ok "bearer-placeholder-pass" "placeholders pass (exit 0)"
  else err "bearer-placeholder-pass" "expected pass (exit 0), got exit $rc"; errors=$((errors+1)); fi
}

# Positive control — a clean staged file must pass (no false positive).
case_clean_passes() {
  local d rc; d="$(new_repo)"
  printf '# just a readme\n' > "$d/README.md"
  git -C "$d" add README.md
  rc="$(run_hook "$d")"
  if [ "$rc" = "0" ]; then ok "clean-pass" "clean staged file passes (exit 0)"
  else err "clean-pass" "expected pass (exit 0), got exit $rc"; errors=$((errors+1)); fi
}

info "secrets-guard staged-blob acceptance tests"
case_staged_clean
case_staged_deleted
case_vault_header
case_rename_vault
case_pkcs8_encrypted
case_jwt_blocked
case_bearer_blocked
case_bearer_placeholder_passes
case_clean_passes

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
