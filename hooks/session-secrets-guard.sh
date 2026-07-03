#!/usr/bin/env bash
#
# session-secrets-guard.sh — Global PreToolUse hook
#
# In-session interception layer (layer 2) for secrets. Denies tool calls that
# would SURFACE a secret in-session — before it is ever written to disk or
# echoed to a command — complementing the git pre-commit hook of the same name
# (hooks/secrets-guard.sh, layer 1), which only fires at commit time.
#
# Fires on every Bash/Write/Edit/MultiEdit/NotebookEdit tool call across all
# agents and sessions. See ADR-053.
#
# Platforms: Claude Code (Bash/Write/Edit/MultiEdit/NotebookEdit + tool_input),
#   VS Code Copilot + Copilot CLI (execute/create_file/replace_string_in_file +
#   toolInput). VS Code ignores matchers, so the self-filter below is the gate.
# Contract: exit 0 = allow, exit 2 = deny. Stderr on deny is shown to the user.
#
# What it blocks:
#   - Bash:        inline secret literals (PEM/AWS/GitHub-PAT) in the command,
#                  and reads of sensitive credential files (~/.aws/credentials,
#                  ~/.ssh/id_*, ~/.kube/config, ~/.netrc, ~/.pgpass, ...).
#   - Write:       writes to a sensitive path (id_rsa, *.pem, *.key), vault-named
#                  files without the $ANSIBLE_VAULT header, or content matching
#                  a secret pattern.
#   - Edit/MultiEdit/NotebookEdit: NEW content (new_string / new_source) matching
#                  a secret pattern. Old/replaced text is NOT scanned, so edits
#                  that REMOVE a secret are never blocked.
#
# Fail posture: write-capable tools fail CLOSED — if tool_input is parseable as a
#   known write tool but the target path cannot be extracted, the call is denied
#   as a precaution (a secrets guard must not be defeatable by a malformed
#   payload). Bash with an empty command and unrecognized tools fail OPEN (no-op).
#
# Override mechanisms (lowest blast radius first):
#   - SKIP_SECRETS_GUARD=1                  one-shot env-var bypass (announced)
#   - .secrets-guard-allowlist (repo root)  per-path glob allowlist (Write/Edit)
#
# Known gaps (documented, accepted): base64-encoded secrets; secrets injected at
#   runtime via shell variable expansion (e.g. `export T=$X; curl -H "$T"`) where
#   the literal is not in the command string; NUL bytes truncate the scanned
#   sample. The content scan is capped at 512 KB, matching the git hook.
#
# Exit codes:
#   0 — allowed (not a secret-surfacing action, or skipped/allowlisted)
#   2 — denied (secret literal, sensitive path, or unverifiable write tool)
#
# Targets: bash 3.2+ (no declare -A, no ${var,,}, no BASH_REMATCH sub-captures).

set -uo pipefail

# --- One-shot env-var bypass (announced — never silent, per ADR-053 / ADR-0022 §Q5) ---
if [[ "${SKIP_SECRETS_GUARD:-}" == "1" ]]; then
  echo "WARN  [skip] SKIP_SECRETS_GUARD=1 set — in-session secrets guard bypassed" >&2
  exit 0
fi

INPUT="$(cat)"
[[ -z "$INPUT" ]] && exit 0

# --- Dependency guard: jq is required to parse tool input (fail CLOSED) ---
# Without jq every jq call below yields "" via `|| true`, the tool-name filter
# falls through to the default *) exit 0, and the entire in-session secrets
# layer silently disables. A guard that cannot inspect its input is not a
# guard, so a missing dependency is treated as an indeterminate state and
# denied — consistent with the write-path fail-closed posture (ADR-053, #212,
# ADR-057). The SKIP_SECRETS_GUARD bypass above still works without jq.
# Inlined (not via deny(), which is defined later) so the guard is self-
# contained before the helper block is reached at runtime.
if ! command -v jq >/dev/null 2>&1; then
  printf 'session-secrets-guard: denied — %s\n' "jq not on PATH — the in-session secrets guard requires jq to parse tool input" >&2
  printf '%s\n' "Remediation: install jq (apt install jq / brew install jq), or set SKIP_SECRETS_GUARD=1 for an announced one-shot bypass." >&2
  exit 2
fi

# --- Tool-name self-filter (Claude tool_name / Copilot toolName) ---
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // ""' 2>/dev/null || true)"
case "$TOOL_NAME" in
  Bash|execute)                  BRANCH="bash" ;;
  Write|create_file)             BRANCH="write" ;;
  Edit|replace_string_in_file)   BRANCH="edit" ;;
  MultiEdit)                     BRANCH="multiedit" ;;
  NotebookEdit)                  BRANCH="notebook" ;;
  *)                             exit 0 ;;
esac

# --- Shared pattern set ---
# Keep in lockstep with hooks/secrets-guard.sh SECRET_PATTERNS and the pi
# secrets-guard extension. A change here MUST be mirrored there (no shared
# source by design — see ADR-053 and shell-expert review of #183).
# NOTE: the PEM alternative uses an OPTIONAL group `(...)?` rather than an empty
# alternation `(RSA |...|)`. They are semantically identical, but BSD grep
# (macOS) rejects an empty sub-expression with "empty (sub)expression", which
# would make the content scan silently fail-open. Both bash hooks use this
# portable form (hooks/secrets-guard.sh was aligned in #201).
# GitHub tokens: gh[oprsu]_ covers all five documented prefixes — ghp_ (classic
# PAT), gho_ (OAuth), ghu_ (user-to-server), ghs_ (server-to-server / Actions
# GITHUB_TOKEN), ghr_ (refresh). The body bound is OPEN ({36,}, {82,}) because
# GitHub treats tokens as opaque and is rolling out a longer ghs_ format
# (~520 chars) — a fixed length would silently miss new tokens (#211, ADR-057).
# JWT: signed tokens only (header.payload.signature, both segments base64url
# starting eyJ = '{"'); unsigned/alg:none tokens are out of scope (#64,
# ADR-095). Bearer: a high-entropy literal after "Authorization: Bearer " —
# placeholders (%s, <key>, $VAR) don't match the 20+ token-char requirement.
# shellcheck disable=SC2016  # single quotes intentional — regex literal, not expansion
SECRET_PATTERNS='-----BEGIN (RSA |EC |OPENSSH |DSA |PGP |ENCRYPTED )?PRIVATE KEY|(^|[^A-Z0-9])(AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}([^A-Z0-9]|$)|gh[oprsu]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{82,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|Authorization: Bearer [A-Za-z0-9._~+/=-]{20,}'

# Sensitive credential-file reads in bash commands. POSIX ERE (grep -E): \s ->
# [[:space:]]; forward slashes are not special; $ and { are literal here.
# shellcheck disable=SC2016
BASH_SENSITIVE_PATH_RE='(^|[^a-zA-Z0-9_/])(\$HOME|~|\$\{HOME\})?/?(\.?)(aws/credentials|aws/config|ssh/id_(rsa|dsa|ecdsa|ed25519|ecdsa_sk|ed25519_sk)(\.pub)?|kube/config|netrc|pgpass|docker/config\.json)([[:space:]]|$|;|\||&)'

# shellcheck disable=SC2016
VAULT_HEADER_RE='^\$ANSIBLE_VAULT;[0-9]+\.[0-9]+;[A-Z0-9]+'

# --- Helpers ---

# Scan a string for any secret pattern. Size-capped at 512 KB. The leading `--`
# is required because SECRET_PATTERNS begins with `-----BEGIN`.
contains_secret() {
  printf '%s' "$1" | head -c 524288 | grep -qE -- "$SECRET_PATTERNS"
}

is_skip_pattern() {
  case "$1" in
    *.example|*.sample|*.template|*.j2) return 0 ;;
    molecule/*|*/molecule/*) return 0 ;;
    tests/*|*/tests/*) return 0 ;;
    spec/*|*/spec/*) return 0 ;;
    fixtures/*|*/fixtures/*) return 0 ;;
  esac
  return 1
}

is_sensitive_path() {
  local base="${1##*/}"
  case "$base" in
    id_rsa|id_dsa|id_ecdsa|id_ed25519) return 0 ;;
    id_ecdsa_sk|id_ed25519_sk) return 0 ;;
    id_rsa.pem|id_dsa.pem|id_ecdsa.pem|id_ed25519.pem) return 0 ;;
  esac
  case "$1" in
    *.pem|*.key) return 0 ;;
  esac
  return 1
}

is_vault_named() {
  case "$1" in
    *vault.yml|*vault.yaml|*vault*.yml|*vault*.yaml) return 0 ;;
    */host_vars/*/vault*|*/group_vars/*/vault*) return 0 ;;
    host_vars/*/vault*|group_vars/*/vault*) return 0 ;;
  esac
  return 1
}

ALLOWLIST_PATTERNS=()
load_allowlist() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "$root" || ! -f "$root/.secrets-guard-allowlist" ]] && return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    case "$line" in \#*|[[:space:]]\#*) continue ;; esac
    ALLOWLIST_PATTERNS+=("$line")
  done < "$root/.secrets-guard-allowlist"
}

is_allowlisted() {
  local pat
  for pat in ${ALLOWLIST_PATTERNS[@]+"${ALLOWLIST_PATTERNS[@]}"}; do
    # shellcheck disable=SC2254  # glob match against user-supplied allowlist is intentional
    case "$1" in $pat) return 0 ;; esac
  done
  return 1
}

deny() {
  printf 'session-secrets-guard: denied — %s\n' "$1" >&2
  printf '%s\n' "Remediation: regenerate the content without the secret literal (use a placeholder or an env-var reference), or for a genuine false positive add the path to .secrets-guard-allowlist. Do not retry a sensitive-path read with a different verb — this rule is path-based." >&2
  exit 2
}

jqv() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null || true; }

# --- Branch: Bash ---
if [[ "$BRANCH" == "bash" ]]; then
  COMMAND="$(jqv '.tool_input.command // .toolInput.command // ""')"
  [[ -z "$COMMAND" ]] && exit 0
  if contains_secret "$COMMAND"; then
    deny "bash command contains an inline secret literal"
  fi
  if printf '%s' "$COMMAND" | grep -qE -- "$BASH_SENSITIVE_PATH_RE"; then
    deny "bash command references a sensitive credential file path"
  fi
  exit 0
fi

# --- Resolve file path for write-capable branches ---
FILE_PATH="$(jqv '.tool_input.file_path // .tool_input.notebook_path // .toolInput.file_path // .toolInput.filePath // .toolInput.notebook_path // ""')"

# Fail CLOSED: a known write tool with no extractable path is unverifiable.
if [[ -z "$FILE_PATH" ]]; then
  deny "could not determine target path for a $TOOL_NAME call — blocking as a precaution"
fi

load_allowlist
is_allowlisted "$FILE_PATH" && exit 0
is_skip_pattern "$FILE_PATH" && exit 0

# Writing to a sensitive path is a hard block regardless of content.
if [[ "$BRANCH" == "write" ]] && is_sensitive_path "$FILE_PATH"; then
  deny "writing to a sensitive file path: $FILE_PATH"
fi

# --- Extract NEW content per branch (never the replaced/old text) ---
case "$BRANCH" in
  write)
    CONTENT="$(jqv '.tool_input.content // .toolInput.content // ""')"
    if is_vault_named "$FILE_PATH"; then
      first_line="$(printf '%s' "$CONTENT" | head -n 1)"
      if [[ ! "$first_line" =~ $VAULT_HEADER_RE ]]; then
        deny "vault-named file written without an \$ANSIBLE_VAULT encryption header: $FILE_PATH"
      fi
      exit 0
    fi
    ;;
  edit)
    CONTENT="$(jqv '.tool_input.new_string // .toolInput.newString // ""')"
    ;;
  multiedit)
    CONTENT="$(jqv '[(.tool_input.edits // .toolInput.edits // [])[] | (.new_string // .newString // "")] | join("\n")')"
    ;;
  notebook)
    EDIT_MODE="$(jqv '.tool_input.edit_mode // .toolInput.edit_mode // ""')"
    [[ "$EDIT_MODE" == "delete" ]] && exit 0
    CONTENT="$(jqv '.tool_input.new_source // .tool_input.source // .toolInput.newSource // ""')"
    ;;
esac

if contains_secret "${CONTENT:-}"; then
  deny "${TOOL_NAME} content contains a secret pattern: $FILE_PATH"
fi

exit 0
