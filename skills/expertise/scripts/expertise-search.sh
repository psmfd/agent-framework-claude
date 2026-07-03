#!/usr/bin/env bash
#
# expertise-search.sh — read-only semantic search against the local
# agent-expertise-api (GET /expertise/search/semantic), for the /expertise
# skill (ADR-094).
#
# POLICY (rules/no-mcp-servers.md, ADR-046): this script is only ever invoked
# as an explicit, visible Bash tool call; its stdout is untrusted tool output.
# Never wire it into a hook, background monitor, or session-start mechanism —
# that recreates the injection surface ADR-046 removed.
#
# Usage: expertise-search.sh <query> [limit]
#   query  — one shell argument (quote multi-word queries)
#   limit  — integer 1-100, default 10 (server clamps regardless)
#
# Config (precedence: env > config file > default):
#   EXPERTISE_SEARCH_URL      base URL, loopback only (default http://127.0.0.1:8080)
#   EXPERTISE_SEARCH_API_KEY  bearer token (no default; required)
#   Config file: ~/.config/expertise-search/config, KEY=VALUE lines, mode 600,
#   user-provisioned out-of-band. This script never writes it.
#
# Output: stdout = verbatim API response body on success (hygiene envelope
# preserved — never parsed or stripped); all diagnostics to stderr per
# rules/script-output-conventions.md.
#
# Exit codes:
#   0  success                       5  auth failure (401/403)
#   2  config/precondition failure   6  rate limited (429; do not retry now)
#   3  non-loopback URL refused      7  other HTTP error
#   4  readiness check failed        8  network/transport failure
#
# Token hygiene: the key is passed to curl via -H @file (never argv, so never
# visible in ps); every line that expands it runs with xtrace suppressed, so
# `bash -x` cannot leak it. No redirects are followed (-H headers would be
# resent cross-host). bash-3.2-safe (macOS system bash).

set -euo pipefail

CONFIG_FILE="${HOME}/.config/expertise-search/config"
DEFAULT_BASE_URL="http://127.0.0.1:8080"
CONNECT_TIMEOUT="${EXPERTISE_SEARCH_CONNECT_TIMEOUT:-3}"
MAX_TIME="${EXPERTISE_SEARCH_MAX_TIME:-15}"

# Inline helper (rules/script-output-conventions.md): this script is invoked
# through the ~/.claude/skills symlink from arbitrary working directories and
# must run standalone — it cannot assume a resolvable scripts/lib/log.sh.
err() { printf 'ERROR [%s] %s\n' "$1" "$2" >&2; }

# --- Arguments -------------------------------------------------------------

if [ $# -lt 1 ]; then
  err "args" "usage: $0 <query> [limit]"
  exit 2
fi
QUERY="$1"
LIMIT="${2:-10}"
if [ $# -gt 2 ]; then
  err "args" "unexpected extra argument(s) after limit — did you forget to quote the query? usage: $0 \"<query>\" [limit]"
  exit 2
fi
case "$LIMIT" in
  ''|*[!0-9]*) err "args" "limit must be an integer 1-100, got: $LIMIT"; exit 2 ;;
esac
if [ "$LIMIT" -lt 1 ] || [ "$LIMIT" -gt 100 ]; then
  err "args" "limit must be 1-100, got: $LIMIT"
  exit 2
fi

command -v curl >/dev/null 2>&1 || { err "deps" "curl is required but not found"; exit 2; }

# --- Config helpers ---------------------------------------------------------

# Parse the config file as data (never source it — a sourced config file is
# arbitrary code execution). Recognizes only the named key.
config_get() {
  [ -f "$CONFIG_FILE" ] || return 1
  awk -F'=' -v k="$1" '$1==k { sub(/^[^=]*=/,""); print; found=1 } END{ exit(found?0:1) }' "$CONFIG_FILE"
}

perm_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

check_config_perms() {
  local p
  p="$(perm_of "$1")" || { err "config" "cannot stat $1"; return 1; }
  case "$p" in
    *00) return 0 ;;  # group and other have zero bits (600, 400, ...)
    *)   err "config" "$1 is mode $p — refusing (chmod 600 \"$1\")"; return 1 ;;
  esac
}

# --- Loopback gate ----------------------------------------------------------

is_loopback_host() {
  case "$1" in
    localhost|LOCALHOST) return 0 ;;
    127.*)
      case "$1" in *[!0-9.]*) return 1 ;; esac
      return 0 ;;
    ::1|\[::1\]) return 0 ;;
  esac
  return 1
}

# --- Resolve config ---------------------------------------------------------

if [ -f "$CONFIG_FILE" ]; then
  check_config_perms "$CONFIG_FILE" || exit 2
fi

BASE_URL="${EXPERTISE_SEARCH_URL:-}"
[ -n "$BASE_URL" ] || BASE_URL="$(config_get EXPERTISE_SEARCH_URL || true)"
[ -n "$BASE_URL" ] || BASE_URL="$DEFAULT_BASE_URL"
BASE_URL="${BASE_URL%/}"

# Scheme allowlist: refuse anything but http/https BEFORE the host check, so a
# curl-supported smuggling scheme (gopher://, dict://, file://, …) can never
# reach curl even when its host component is loopback. Defense in depth with
# --proto on the curl calls below.
case "$BASE_URL" in
  http://*|https://*) : ;;
  *://*) err "config" "unsupported URL scheme in EXPERTISE_SEARCH_URL (http/https only): $BASE_URL"; exit 3 ;;
  *)     err "config" "EXPERTISE_SEARCH_URL has no scheme: $BASE_URL"; exit 2 ;;
esac

host_port="${BASE_URL#*://}"
host_port="${host_port%%/*}"        # strip path first so a '@' in the path is not read as userinfo
case "$host_port" in
  *@*) err "config" "userinfo in EXPERTISE_SEARCH_URL is not supported"; exit 3 ;;
esac
case "$host_port" in
  \[*\]*) host="${host_port%%\]*}]" ;;      # [::1] or [::1]:8080
  *)      host="${host_port%%:*}" ;;
esac
if ! is_loopback_host "$host"; then
  err "loopback" "refusing non-loopback base URL host: $host (loopback only by design — ADR-094)"
  exit 3
fi

# --- Resolve the API key (xtrace suppressed for every expanding line) -------

case $- in *x*) WAS_TRACING=1 ;; *) WAS_TRACING=0 ;; esac
{ set +x; } 2>/dev/null

restore_xtrace() {
  if [ "$WAS_TRACING" = 1 ]; then { set -x; } 2>/dev/null; fi
}

API_KEY="${EXPERTISE_SEARCH_API_KEY:-}"
[ -n "$API_KEY" ] || API_KEY="$(config_get EXPERTISE_SEARCH_API_KEY || true)"
if [ -z "$API_KEY" ]; then
  restore_xtrace
  err "config" "no API key: set EXPERTISE_SEARCH_API_KEY or provision $CONFIG_FILE (mode 600)"
  exit 2
fi

header_file="$(mktemp "${TMPDIR:-/tmp}/expertise-search-h.XXXXXX")" || {
  restore_xtrace
  err "tmp" "mktemp failed"; exit 2
}
body_file="$(mktemp "${TMPDIR:-/tmp}/expertise-search-b.XXXXXX")" || {
  rm -f "$header_file"
  restore_xtrace
  err "tmp" "mktemp failed"; exit 2
}
resp_headers_file="$(mktemp "${TMPDIR:-/tmp}/expertise-search-r.XXXXXX")" || {
  rm -f "$header_file" "$body_file"
  restore_xtrace
  err "tmp" "mktemp failed"; exit 2
}
trap 'rm -f "$header_file" "$body_file" "$resp_headers_file"' EXIT
chmod 600 "$header_file"
printf 'Authorization: Bearer %s\n' "$API_KEY" > "$header_file"
unset API_KEY

restore_xtrace

# --- Readiness gate (unauthenticated; never burns the rate budget) ----------

ready_code="$(curl -sS --proto '=http,https' -o /dev/null -w '%{http_code}' \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$CONNECT_TIMEOUT" \
  "${BASE_URL}/health/ready" 2>/dev/null)" || ready_code=""
if [ "$ready_code" != "200" ]; then
  err "readiness" "API not ready at ${BASE_URL} (/health/ready returned ${ready_code:-no response})"
  exit 4
fi

# --- Search -----------------------------------------------------------------

curl_rc=0
http_code="$(curl -sS -G --proto '=http,https' \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  -H @"$header_file" \
  --data-urlencode "q=${QUERY}" \
  --data-urlencode "limit=${LIMIT}" \
  -D "$resp_headers_file" -o "$body_file" -w '%{http_code}' \
  "${BASE_URL}/expertise/search/semantic")" || curl_rc=$?

if [ "$curl_rc" -ne 0 ]; then
  err "network" "curl transport failure (rc=$curl_rc) against ${BASE_URL}"
  exit 8
fi

case "$http_code" in
  200)
    cat "$body_file"
    exit 0
    ;;
  401|403)
    err "auth" "HTTP $http_code — API key invalid, expired, or missing required scope"
    cat "$body_file" >&2
    exit 5
    ;;
  429)
    retry_after="$(awk 'tolower($1)=="retry-after:" { gsub(/\r/,"",$2); print $2; exit }' "$resp_headers_file")"
    if [ -n "$retry_after" ]; then
      err "rate-limit" "HTTP 429 — rate limited; retry after ${retry_after}s (per the server's Retry-After header). Do not retry immediately."
    else
      err "rate-limit" "HTTP 429 — rate limited by the server. Do not retry immediately."
    fi
    cat "$body_file" >&2
    exit 6
    ;;
  *)
    err "http" "HTTP $http_code from ${BASE_URL}/expertise/search/semantic"
    cat "$body_file" >&2
    exit 7
    ;;
esac
