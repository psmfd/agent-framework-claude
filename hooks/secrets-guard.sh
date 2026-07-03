#!/usr/bin/env bash
#
# secrets-guard.sh — Pre-commit hook
#
# Blocks commits containing unencrypted Ansible vault files and common secret
# patterns (PEM private keys, AWS access keys, GitHub personal access tokens,
# SSH private key file paths).
#
# This is a git pre-commit hook, not a Claude Code or Copilot hook.
# Git contract: exit 0 = allow commit, non-zero = block commit.
#
# All content checks read the STAGED BLOB (`git show ":<path>"`), never the
# working-tree file — so editing or removing a file after `git add` cannot hide
# a secret already in the index (ADR-059, supersedes ADR-047).
#
# Detection:
#   1. Vault-named files (**/vault*.yml, host_vars/group_vars vault files)
#      whose staged first line does not match $ANSIBLE_VAULT;<ver>;<cipher>
#   2. Staged content matching PEM/AWS/GitHub-PAT regex
#   3. Sensitive file paths (id_rsa, *.pem, *.key, etc.)
#
# Override mechanisms (lowest blast radius first):
#   - SKIP_SECRETS_GUARD=1                  one-shot env-var bypass
#   - .secrets-guard-allowlist (repo root)  per-path glob allowlist
#   - git commit --no-verify                emergency bypass (all hooks)
#
# Skip patterns: *.example, *.sample, *.template, *.j2; paths under molecule/,
# tests/, spec/; binary files; files staged for deletion.
#
# Output per rules/script-output-conventions.md (OK/WARN/ERROR labels).
# Exit codes:
#   0 — pass (no findings; commit proceeds)
#   1 — fail (one or more findings; commit blocked)
#   2 — environment failure (not a git repo, missing dependencies)
#
# Targets: bash 3.2+ (avoid declare -A, ${var,,}, BASH_REMATCH sub-captures).

set -euo pipefail

VERBOSE="${SECRETS_GUARD_VERBOSE:-${VERBOSE:-0}}"

ok()     { echo "OK    [$1] $2"; }
warn()   { echo "WARN  [$1] $2" >&2; }
err()    { echo "ERROR [$1] $2" >&2; }
detail() { if [[ "$VERBOSE" == "1" ]]; then echo "      $*"; fi; }

# --- One-shot env-var bypass ---
if [[ "${SKIP_SECRETS_GUARD:-}" == "1" ]]; then
  warn "skip" "SKIP_SECRETS_GUARD=1 set — secrets guard bypassed"
  exit 0
fi

# --- Environment checks ---
if ! command -v git >/dev/null 2>&1; then
  err "env" "git is required but not on PATH"
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  err "env" "not inside a git repository"
  exit 2
fi

# --- Allowlist ---
ALLOWLIST_FILE="$REPO_ROOT/.secrets-guard-allowlist"
ALLOWLIST_PATTERNS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments
    [[ -z "$line" ]] && continue
    case "$line" in
      \#*|[[:space:]]\#*) continue ;;
    esac
    ALLOWLIST_PATTERNS+=("$line")
  done < "$ALLOWLIST_FILE"
fi

is_allowlisted() {
  local path="$1"
  local pat
  for pat in ${ALLOWLIST_PATTERNS[@]+"${ALLOWLIST_PATTERNS[@]}"}; do
    # shellcheck disable=SC2254  # glob match against user-supplied allowlist pattern is intentional
    case "$path" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# --- Skip patterns (paths the hook does not scan) ---
is_skip_pattern() {
  local path="$1"
  case "$path" in
    *.example|*.sample|*.template|*.j2) return 0 ;;
    molecule/*|*/molecule/*) return 0 ;;
    tests/*|*/tests/*) return 0 ;;
    spec/*|*/spec/*) return 0 ;;
  esac
  return 1
}

# --- Vault-naming pattern ---
is_vault_named() {
  local path="$1"
  case "$path" in
    *vault.yml|*vault.yaml|*vault*.yml|*vault*.yaml) return 0 ;;
    */host_vars/*/vault*|*/group_vars/*/vault*) return 0 ;;
    host_vars/*/vault*|group_vars/*/vault*) return 0 ;;
  esac
  return 1
}

# --- Sensitive-name file paths (private-key files) ---
is_sensitive_path() {
  local path="$1"
  local base="${path##*/}"
  case "$base" in
    id_rsa|id_dsa|id_ecdsa|id_ed25519) return 0 ;;
    id_ecdsa_sk|id_ed25519_sk) return 0 ;;
    id_rsa.pem|id_dsa.pem|id_ecdsa.pem|id_ed25519.pem) return 0 ;;
  esac
  case "$path" in
    *.pem|*.key) return 0 ;;
  esac
  return 1
}

# --- Binary detection via git diff --numstat ---
# A binary diff line looks like "-\t-\t<path>"; a text diff has numeric counts.
is_binary() {
  local path="$1"
  local numstat
  numstat="$(git diff --cached --numstat -- "$path" 2>/dev/null | head -n 1)"
  case "$numstat" in
    -[[:space:]]*-[[:space:]]*) return 0 ;;
  esac
  return 1
}

# --- Vault encryption header (covers 1.1 and 1.2 with vault IDs) ---
# shellcheck disable=SC2016  # single quotes are intentional — this is a regex literal, not a shell expansion
VAULT_HEADER_RE='^\$ANSIBLE_VAULT;[0-9]+\.[0-9]+;[A-Z0-9]+'

# --- Combined secret-content patterns (single grep -E) ---
# The PEM alternative uses an OPTIONAL group `(...)?` rather than an empty
# alternation `(...|)`: BSD grep (macOS) rejects an empty sub-expression with
# "empty (sub)expression", which invalidates the WHOLE pattern and silently
# fails the content scan open. The optional-group form is semantically
# identical and portable across BSD + GNU grep. Keep in lockstep with
# hooks/session-secrets-guard.sh (#201, #183, ADR-053, ADR-057).
# GitHub tokens: gh[oprsu]_ covers all five documented prefixes — ghp_ (classic
# PAT), gho_ (OAuth), ghu_ (user-to-server), ghs_ (server-to-server / Actions
# GITHUB_TOKEN), ghr_ (refresh). The body bound is OPEN ({36,}, {82,}) because
# GitHub treats tokens as opaque and is rolling out a longer ghs_ format
# (~520 chars) — a fixed length would silently miss new tokens (#211, ADR-057).
# JWT: signed tokens only (header.payload.signature, both segments base64url
# starting eyJ = '{"'); unsigned/alg:none tokens are out of scope (#64,
# ADR-095). Bearer: a high-entropy literal after "Authorization: Bearer " —
# placeholders (%s, <key>, $VAR) don't match the 20+ token-char requirement.
SECRET_PATTERNS='-----BEGIN (RSA |EC |OPENSSH |DSA |PGP |ENCRYPTED )?PRIVATE KEY|(^|[^A-Z0-9])(AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}([^A-Z0-9]|$)|gh[oprsu]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{82,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|Authorization: Bearer [A-Za-z0-9._~+/=-]{20,}'

# --- Counters ---
errors=0
warnings=0
scanned=0
skipped_count=0

# --- Read NUL-delimited list of staged paths ---
# Filter ACMR: Added, Copied, Modified, Renamed. Renames (R) are included so a
# file renamed into a vault/sensitive name with a secret-bearing body is still
# scanned — git emits only the destination path for R, which the scan logic
# below handles unchanged. Deletions (D) are excluded (cannot introduce a
# secret). All checks below read the STAGED BLOB (`git show ":<path>"`), not the
# working-tree file, so a file cleaned or removed from the working tree after
# staging is still caught (ADR-059, supersedes ADR-047).
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACMR -z 2>/dev/null)

if [[ ${#files[@]} -eq 0 ]]; then
  ok "scan" "no staged files to check"
  echo "=================================="
  echo "PASS — 0 errors, 0 warnings"
  exit 0
fi

# --- Per-file scan ---
for staged_path in "${files[@]}"; do
  # All content reads below use the staged blob via `git show ":$staged_path"`,
  # never the working-tree file — see the diff-filter comment above (ADR-059).

  # Allowlist takes precedence over all other checks
  if is_allowlisted "$staged_path"; then
    warn "allowlist" "$staged_path matches allowlist — skipped"
    ((warnings++)) || true
    ((skipped_count++)) || true
    continue
  fi

  # Skip patterns
  if is_skip_pattern "$staged_path"; then
    detail "skip $staged_path (skip-pattern)"
    ((skipped_count++)) || true
    continue
  fi

  # Past the early skips — this file is being examined by the guard.
  ((scanned++)) || true

  # Sensitive path is a hard block regardless of content
  if is_sensitive_path "$staged_path"; then
    err "sensitive-path" "$staged_path looks like a private key or sensitive file"
    ((errors++)) || true
    continue
  fi

  # Vault check — header-based; no content scan needed if encrypted.
  # Reads the staged blob's first line, not the working-tree file.
  if is_vault_named "$staged_path"; then
    if ! git cat-file -e ":$staged_path" 2>/dev/null; then
      detail "vault $staged_path not in index (skipped)"
      continue
    fi
    first_line="$(git show ":$staged_path" 2>/dev/null | head -n 1 || true)"
    if [[ "$first_line" =~ $VAULT_HEADER_RE ]]; then
      detail "vault $staged_path is encrypted"
      continue
    fi
    err "vault" "$staged_path matches vault-naming pattern but is not encrypted"
    ((errors++)) || true
    continue
  fi

  # Skip binary files for content scan
  if is_binary "$staged_path"; then
    detail "skip $staged_path (binary)"
    continue
  fi

  if ! git cat-file -e ":$staged_path" 2>/dev/null; then
    detail "skip $staged_path (not in index)"
    continue
  fi

  # Content scan of the STAGED BLOB, capped at 512 KB. The leading `--` is
  # required because the combined regex starts with `-----BEGIN ... PRIVATE KEY`
  # — without it grep interprets the pattern as an option flag and silently
  # fails. Scanning `git show ":<path>"` (not the working-tree file) is what
  # closes the stage-then-clean bypass (ADR-059).
  if git show ":$staged_path" 2>/dev/null | head -c 524288 | grep -qE -- "$SECRET_PATTERNS"; then
    err "secret" "$staged_path contains a secret pattern"
    ((errors++)) || true
  fi
done

# --- Summary ---
echo "=================================="
if (( errors > 0 )); then
  echo "FAIL — $errors errors, $warnings warnings ($scanned files scanned, $skipped_count skipped)"
  echo ""
  echo "Override options (lowest blast radius first):"
  echo "  SKIP_SECRETS_GUARD=1 git commit ...    one-shot bypass (auditable)"
  echo "  Add path to .secrets-guard-allowlist   known false positives"
  echo "  git commit --no-verify                 emergency bypass (all hooks)"
  exit 1
fi
echo "PASS — 0 errors, $warnings warnings ($scanned files scanned, $skipped_count skipped)"
exit 0
