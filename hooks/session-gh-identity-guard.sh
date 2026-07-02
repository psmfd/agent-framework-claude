#!/usr/bin/env bash
#
# session-gh-identity-guard.sh — Global PreToolUse hook (layer 1 of the
# gh-identity guard)
#
# Denies Bash/execute tool calls that perform a MUTATING gh/git operation
# (gh <noun> <verb>, gh api with a mutating method, git push) while the active
# gh identity is wrong for the target github.com repo. Closes the in-session
# (agent Bash) vector; the companion git pre-push hook (gh-identity-guard.sh)
# closes the raw-shell vector. See ADR-054.
#
# Platforms: Claude Code (Bash + tool_input), Copilot (execute + toolInput).
#   VS Code ignores matchers, so the self-filter below is the gate.
# Contract: exit 0 = allow, exit 2 = deny. Stderr on deny is shown to the user.
#
# A cheap string pre-check runs first; the network identity probe fires ONLY
# when the command is actually a mutating gh/git op, so ordinary tool calls
# (and read-only gh/git) never probe or block.
#
# Signal model (hybrid — ADR-054): if <repo>/.gh-expected-identity exists, the
# active login must be one of its entries; otherwise fall back to accessibility
# of `origin`. Fail CLOSED on indeterminate identity (only affects the detected
# mutating op). Overrides: SKIP_GH_IDENTITY_GUARD=1 (env), .gh-identity-allowlist
# (command-substring allow), GH_IDENTITY_OVERRIDE=<login> (env only — the
# command-string prefix form is deliberately not honored; ADR-070).
#
# In-session scope note: checks against `origin`; the pre-push hook checks the
# actual push remote. Documented gaps (accepted): shell aliases, env-var-
# constructed commands, `curl` with a `gh auth token`, and an agent with
# Write/Edit tool access pre-writing a .gh-identity-allowlist entry (the write
# is visible in the activity stream; this guard gates Bash/execute only).
# Exit codes: 0 allow, 2 deny. Targets bash 3.2+.
#
# NOTE: identity helpers are duplicated from hooks/gh-identity-guard.sh by
# design (no shared sourced lib) — keep the two in lockstep. See ADR-054.

set -uo pipefail

sanitize() { printf '%s' "$1" | tr -d '\000-\037\177'; }

deny() {
  printf 'session-gh-identity-guard: denied — %s\n' "$1" >&2
  printf '%s\n' "Remediation: run 'gh auth switch' to the correct account, then retry. For a deliberate override, ask the user to add the command to .gh-identity-allowlist or to launch the session with GH_IDENTITY_OVERRIDE=<login> or SKIP_GH_IDENTITY_GUARD=1 — these are user decisions; do not edit the allowlist or set the variables yourself." >&2
  exit 2
}

# --- Session bypass (announced — never silent) -------------------------------
if [ "${SKIP_GH_IDENTITY_GUARD:-}" = "1" ]; then
  printf 'WARN  [skip] SKIP_GH_IDENTITY_GUARD=1 set — in-session gh-identity guard bypassed\n' >&2
  exit 0
fi

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# --- Dependency guard: jq is required to parse tool input (fail CLOSED) -------
# Without jq the TOOL_NAME / COMMAND parses below yield "" via `|| true`, the
# mutating-op pre-check sees an empty command and exits 0 — the in-session
# identity guard silently disables for every mutating gh/git op. A missing
# dependency is an indeterminate state and is denied, consistent with the
# fail-closed posture for indeterminate identity (ADR-054, #212, ADR-057). The
# SKIP_GH_IDENTITY_GUARD bypass above still works without jq.
command -v jq >/dev/null 2>&1 || deny "jq not on PATH — the in-session gh-identity guard requires jq to parse tool input. Install jq (apt install jq / brew install jq), or set SKIP_GH_IDENTITY_GUARD=1 for an announced one-shot bypass."

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // ""' 2>/dev/null || true)"
case "$TOOL_NAME" in
  Bash|execute) ;;
  *) exit 0 ;;
esac

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .toolInput.command // ""' 2>/dev/null || true)"
[ -z "$COMMAND" ] && exit 0

# --- Cheap pre-check: is this a mutating gh/git op? (no fork, case-glob) ------
is_mutating_op() {
  local c="$1"
  # Note: --dry-run / -n invocations are intentionally NOT skipped — probing
  # identity on a dry run is harmless and keeps this classifier simple. Do not
  # add a return-0 skip here; it would become a guard bypass.
  case "$c" in
    *"git push"*) return 0 ;;
  esac
  case "$c" in
    *"gh pr create"*|*"gh pr merge"*|*"gh pr close"*|*"gh pr edit"*|*"gh pr reopen"*|*"gh pr review"*|*"gh pr ready"*|*"gh pr comment"*) return 0 ;;
    *"gh issue create"*|*"gh issue edit"*|*"gh issue close"*|*"gh issue reopen"*|*"gh issue delete"*|*"gh issue comment"*|*"gh issue transfer"*) return 0 ;;
    *"gh release create"*|*"gh release upload"*|*"gh release delete"*|*"gh release edit"*) return 0 ;;
    *"gh repo create"*|*"gh repo delete"*|*"gh repo edit"*|*"gh repo rename"*|*"gh repo fork"*|*"gh repo sync"*|*"gh repo archive"*) return 0 ;;
    *"gh label create"*|*"gh label edit"*|*"gh label delete"*|*"gh label clone"*) return 0 ;;
    *"gh secret set"*|*"gh secret delete"*|*"gh variable set"*|*"gh variable delete"*) return 0 ;;
    *"gh workflow run"*|*"gh workflow enable"*|*"gh workflow disable"*) return 0 ;;
    *"gh run rerun"*|*"gh run cancel"*|*"gh run delete"*|*"gh cache delete"*) return 0 ;;
    *"gh gist create"*|*"gh gist edit"*|*"gh gist delete"*) return 0 ;;
    *"gh ruleset create"*|*"gh ruleset edit"*|*"gh ruleset delete"*) return 0 ;;
  esac
  # gh api with a mutating HTTP method (-X/-XMETHOD/--method, space or =)
  case "$c" in
    *"gh api"*) ;;
    *) return 1 ;;
  esac
  case "$c" in
    *"-X POST"*|*"-X PATCH"*|*"-X PUT"*|*"-X DELETE"*|*"-XPOST"*|*"-XPATCH"*|*"-XPUT"*|*"-XDELETE"*) return 0 ;;
    *"--method POST"*|*"--method PATCH"*|*"--method PUT"*|*"--method DELETE"*|*"--method=POST"*|*"--method=PATCH"*|*"--method=PUT"*|*"--method=DELETE"*) return 0 ;;
  esac
  # gh api with a body flag and NO explicit method defaults to POST — an implicit
  # mutation (e.g. `gh api repos/o/r/dispatches --input p.json`). We are already
  # inside a `gh api` command here, so any body flag implies a write. Covers the
  # spaced and `=` forms of --input/-f/--raw-field/-F/--field.
  case "$c" in
    *" --input "*|*" --input="*|*" -f "*|*" --raw-field "*|*" --raw-field="*|*" -F "*|*" --field "*|*" --field="*) return 0 ;;
  esac
  return 1
}
is_mutating_op "$COMMAND" || exit 0

# --- .gh-identity-allowlist (command-substring allow) ------------------------
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$repo_root" ] && [ -f "$repo_root/.gh-identity-allowlist" ]; then
  while IFS= read -r pat || [ -n "$pat" ]; do
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    case "$COMMAND" in *"$pat"*) exit 0 ;; esac
  done < "$repo_root/.gh-identity-allowlist"
fi

# --- gh availability (fail closed for the mutating op) -----------------------
command -v gh >/dev/null 2>&1 || deny "gh not on PATH — cannot verify identity for a mutating gh/git operation"

GH_LOGIN_RE='^[a-zA-Z0-9]([a-zA-Z0-9]|-[a-zA-Z0-9]){0,38}(_[a-zA-Z0-9]{3,8})?$'
is_valid_login() { [ "${#1}" -le 39 ] && [[ "$1" =~ $GH_LOGIN_RE ]]; }

parse_owner_repo() {
  local url="$1" path
  case "$url" in
    *://*) path="${url#*://}"; path="${path#*/}" ;;   # strip scheme + host[:port]/
    *:*)   path="${url#*:}" ;;                          # scp-style host:owner/repo
    *)     return 1 ;;
  esac
  path="${path%.git}"; path="${path%/}"
  case "$path" in */*) printf '%s' "$path" ;; *) return 1 ;; esac
}

# --- Per-invocation override: GH_IDENTITY_OVERRIDE env var ONLY --------------
# The command-string prefix form (`GH_IDENTITY_OVERRIDE=x gh ...`) is
# deliberately NOT parsed: the command string is agent-controlled, so honoring
# it would let an injected command self-certify the active login and defeat
# the .gh-expected-identity pin (ADR-070). The env var is read from the hook
# process environment, which only the user (at session launch) controls.
override="${GH_IDENTITY_OVERRIDE:-}"
# INVARIANT: every code path that expands ALLOWED_LOGINS later must first
# guarantee it is non-empty — bash 3.2 + set -u aborts on expanding an empty
# array. Today the pin-file/override/fallback resolution below ensures this.
ALLOWED_LOGINS=()
if [ -n "$override" ]; then
  case "$override" in \"*\") override="${override#\"}"; override="${override%\"}" ;; \'*\') override="${override#\'}"; override="${override%\'}" ;; esac
  is_valid_login "$override" || deny "GH_IDENTITY_OVERRIDE='$(sanitize "$override")' is not a valid GitHub username"
  ALLOWED_LOGINS=("$override")
fi

# --- Probe active login (authoritative) --------------------------------------
active_login="$(gh api user --jq .login 2>/dev/null || true)"
[ -z "$active_login" ] && deny "could not determine active gh identity (unauthenticated, network, or API error)"

origin_url="$(git remote get-url origin 2>/dev/null || true)"

# --- GH_TOKEN/GITHUB_TOKEN (CI/bot): accessibility under the token -----------
# An explicit GH_IDENTITY_OVERRIDE is deliberate intent and wins over the token
# carve-out, so this only runs when no override populated ALLOWED_LOGINS.
if [ "${#ALLOWED_LOGINS[@]}" -eq 0 ] && [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  if owner_repo="$(parse_owner_repo "$origin_url")"; then
    gh api "repos/${owner_repo}" --silent >/dev/null 2>&1 && exit 0
    deny "token identity cannot access ${owner_repo}"
  fi
  exit 0   # token set but origin unparseable/non-github — not our gate
fi

# --- Resolve expected identity: pin file, else accessibility -----------------
if [ "${#ALLOWED_LOGINS[@]}" -eq 0 ]; then
  if [ -n "$repo_root" ] && [ -f "$repo_root/.gh-expected-identity" ]; then
    # Pin file present → strict login compare. Fail CLOSED if it yields no
    # valid login (matches the pre-push hook; a corrupt/empty pin must not
    # silently downgrade to the weaker accessibility signal).
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"; line="${line%%#*}"
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      is_valid_login "$line" && ALLOWED_LOGINS+=("$line")
    done < "$repo_root/.gh-expected-identity"
    if [ "${#ALLOWED_LOGINS[@]}" -eq 0 ]; then
      deny ".gh-expected-identity exists but contains no valid GitHub login"
    fi
  else
    # No pin file → hybrid accessibility fallback against origin.
    if owner_repo="$(parse_owner_repo "$origin_url")"; then
      gh api "repos/${owner_repo}" --silent >/dev/null 2>&1 && exit 0
      deny "active gh user '$(sanitize "$active_login")' cannot access ${owner_repo}"
    fi
    exit 0   # no origin / non-github — nothing to gate in-session
  fi
fi

# --- Strict compare ----------------------------------------------------------
for candidate in "${ALLOWED_LOGINS[@]}"; do
  [ "$active_login" = "$candidate" ] && exit 0
done
deny "identity drift: active gh user is '$(sanitize "$active_login")', expected one of: ${ALLOWED_LOGINS[*]}"
