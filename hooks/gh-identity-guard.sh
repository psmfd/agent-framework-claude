#!/usr/bin/env bash
#
# gh-identity-guard.sh — git pre-push hook (layer 2 of the gh-identity guard)
#
# Blocks a push when the active gh identity is wrong for a github.com remote,
# closing the raw-shell-outside-an-agent gap (plain terminal, IDE git client,
# scripts) that the in-session PreToolUse hook (session-gh-identity-guard.sh)
# cannot see. Companion to that hook; see ADR-054. This is a GIT-NATIVE hook —
# it has no Claude Code / Copilot config equivalent.
#
# Signal model (hybrid — ADR-054):
#   1. If <repo>/.gh-expected-identity exists, the active login MUST be one of
#      its entries (strict login compare; catches a wrong-but-also-authorized
#      account). One login per line; '#' comments and blanks ignored.
#   2. Otherwise fall back to ACCESSIBILITY: the active account must be able to
#      reach the push remote (`gh api repos/OWNER/REPO`). Consistent with
#      ADR-052; no per-repo config required.
#
# Scope: github.com remotes only (exact host match). Pushes to Azure DevOps,
#   GitLab, Bitbucket, and self-hosted hosts pass through silently.
#
# Fail posture: fail CLOSED — an unverifiable push identity (gh missing, probe
#   error, network failure, inaccessible remote) blocks the push. The cost of a
#   false block is one `gh auth switch` or an override; the cost of a false
#   allow is a wrong-account push (hard to reverse).
#
# Overrides (lowest blast radius first):
#   GH_IDENTITY_OVERRIDE=<login> git push   expect <login> for this push only
#                                           (validated against the gh username regex)
#   SKIP_GH_IDENTITY_GUARD=1 git push       bypass this guard for this push
#   git push --no-verify                    native: bypass ALL pre-push hooks
#
# Exit codes: 0 pass · 1 identity drift / misconfig · 2 environment failure
# Targets bash 3.2+ (no declare -A, no ${var,,}, no BASH_REMATCH sub-captures).
#
# NOTE: the identity helpers below (extract_host, is_valid_login, sanitize,
# probe + hybrid resolution) are intentionally duplicated in
# hooks/session-gh-identity-guard.sh rather than sourced from a shared lib —
# keep the two in lockstep. See ADR-054 and the #184 shell-expert review.

set -uo pipefail

ok()   { printf 'OK    [%s] %s\n' "$1" "$2"; }
warn() { printf 'WARN  [%s] %s\n' "$1" "$2" >&2; }
err()  { printf 'ERROR [%s] %s\n' "$1" "$2" >&2; }

# Strip control bytes from untrusted strings before echoing to the terminal.
sanitize() { printf '%s' "$1" | tr -d '\000-\037\177'; }

# Extract the host from a remote URL and lowercase it. Splits host from path
# before handling userinfo so an '@' in the path or a double-'@' in userinfo
# cannot misdirect the split; strips a trailing dot (absolute-DNS form).
extract_host() {
  local url="$1" host host_part
  case "$url" in *://*) url="${url#*://}" ;; esac
  host_part="${url%%/*}"
  case "$host_part" in *@*) host_part="${host_part##*@}" ;; esac
  host="${host_part%%[:]*}"
  host="${host%.}"
  printf '%s' "$host" | tr '[:upper:]' '[:lower:]'
}

# GitHub username: 1-39 chars, alphanumeric with non-consecutive single
# dashes, optional EMU _<shortcode> suffix (3-8 alnum).
GH_LOGIN_RE='^[a-zA-Z0-9]([a-zA-Z0-9]|-[a-zA-Z0-9]){0,38}(_[a-zA-Z0-9]{3,8})?$'
is_valid_login() { [ "${#1}" -le 39 ] && [[ "$1" =~ $GH_LOGIN_RE ]]; }

# Parse owner/repo from a github.com remote URL (https, scp-style, ssh://).
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

# --- pre-push contract: $1=remote name, $2=remote URL; stdin=ref lines -------
REMOTE_NAME="${1:-}"
REMOTE_URL="${2:-}"
[ ! -t 0 ] && cat >/dev/null   # drain stdin (identity-scoped, not ref-scoped)

# --- Scope: github.com only --------------------------------------------------
case "$(extract_host "$REMOTE_URL")" in
  github.com) : ;;
  *) exit 0 ;;
esac

# --- Session bypass (after scope so non-GitHub pushes stay silent) -----------
if [ "${SKIP_GH_IDENTITY_GUARD:-}" = "1" ]; then
  warn skip "SKIP_GH_IDENTITY_GUARD=1 — gh-identity-guard bypassed for this push"
  exit 0
fi

# --- gh availability (fail closed: gh is a declared dependency) --------------
if ! command -v gh >/dev/null 2>&1; then
  err env "gh not on PATH — cannot verify push identity (fail-closed)"
  err env "install gh, or bypass with SKIP_GH_IDENTITY_GUARD=1 / git push --no-verify"
  exit 2
fi

# --- Probe the active login (authoritative; gh auth status is not) -----------
active_login="$(gh api user --jq .login 2>/dev/null || true)"
if [ -z "$active_login" ]; then
  err probe "could not determine active gh identity (unauthenticated, network, or API error)"
  err probe "run 'gh auth status'; bypass with SKIP_GH_IDENTITY_GUARD=1 if intentional"
  exit 2
fi

# --- Per-invocation override --------------------------------------------------
ALLOWED_LOGINS=()
if [ -n "${GH_IDENTITY_OVERRIDE:-}" ]; then
  ov="$GH_IDENTITY_OVERRIDE"
  case "$ov" in \"*\") ov="${ov#\"}"; ov="${ov%\"}" ;; \'*\') ov="${ov#\'}"; ov="${ov%\'}" ;; esac
  if ! is_valid_login "$ov"; then
    err override "GH_IDENTITY_OVERRIDE='$(sanitize "$GH_IDENTITY_OVERRIDE")' is not a valid GitHub username"
    exit 1
  fi
  ALLOWED_LOGINS=("$ov")
  warn override "GH_IDENTITY_OVERRIDE applied — expecting '$ov' for this push"
fi

# --- GH_TOKEN/GITHUB_TOKEN (CI/bot): verify access under the token (ADR-054) -
# A scoped token IS the identity, so verify repo access rather than comparing
# logins (a bot actor like github-actions[bot] never matches a human pin). An
# explicit GH_IDENTITY_OVERRIDE wins over this (it is deliberate intent), so
# this only runs when no override was given.
if [ "${#ALLOWED_LOGINS[@]}" -eq 0 ] && [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  if owner_repo="$(parse_owner_repo "$REMOTE_URL")"; then
    if gh api "repos/${owner_repo}" --silent >/dev/null 2>&1; then
      ok identity "token identity can access ${owner_repo} (CI/bot access check)"
      exit 0
    fi
    err drift "token identity cannot access ${owner_repo} — check the token's scope/repo access"
    exit 1
  fi
  exit 0  # token set but remote unparseable / non-github — not our gate
fi

# --- Resolve expected identity: pin file, else accessibility fallback --------
if [ "${#ALLOWED_LOGINS[@]}" -eq 0 ]; then
  pin=""
  if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    pin="${repo_root}/.gh-expected-identity"
  fi
  if [ -n "$pin" ] && [ -f "$pin" ]; then
    # Strict pinned-login compare.
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"; line="${line%%#*}"
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      is_valid_login "$line" && ALLOWED_LOGINS+=("$line")
    done < "$pin"
    if [ "${#ALLOWED_LOGINS[@]}" -eq 0 ]; then
      err config ".gh-expected-identity exists but contains no valid GitHub login"
      exit 1
    fi
  else
    # Hybrid fallback: accessibility — the active account must reach the remote.
    if owner_repo="$(parse_owner_repo "$REMOTE_URL")"; then
      if gh api "repos/${owner_repo}" --silent >/dev/null 2>&1; then
        ok identity "active gh user '${active_login}' can access ${owner_repo} (accessibility check)"
        exit 0
      fi
      err drift "active gh user '$(sanitize "$active_login")' cannot access ${owner_repo}"
      err drift "this push would fail or target the wrong account; run 'gh auth switch'"
      err drift "or pin the expected login in .gh-expected-identity / use GH_IDENTITY_OVERRIDE=<login>"
      exit 1
    fi
    err config "could not parse owner/repo from remote URL: $(sanitize "$REMOTE_URL")"
    exit 1
  fi
fi

# --- Strict compare against the pinned/overridden login set ------------------
for candidate in "${ALLOWED_LOGINS[@]}"; do
  if [ "$active_login" = "$candidate" ]; then
    ok identity "active gh user '${active_login}' matches expected for ${REMOTE_NAME:-origin}"
    exit 0
  fi
done

err drift "identity drift: active gh user is '$(sanitize "$active_login")', expected one of: ${ALLOWED_LOGINS[*]}"
err drift "remediate with: gh auth switch   (then re-run push)"
err drift "or, if intentional: GH_IDENTITY_OVERRIDE='${active_login}' git push"
exit 1
