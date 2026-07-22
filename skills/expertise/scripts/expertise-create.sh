#!/usr/bin/env bash
#
# expertise-create.sh — create-only write-back to the local agent-expertise-api
# (POST /expertise), for the /expertise skill (ADR-096; read path: ADR-094).
#
# POLICY (rules/no-mcp-servers.md, ADR-046): this script is only ever invoked
# as an explicit, visible Bash tool call, and only after the user approved the
# specific entry being created. Never wire it into a hook, background monitor,
# or session-start mechanism, and never invoke it autonomously.
#
# Usage: expertise-create.sh <domain> <title> <entryType> <severity> [source] [tags-csv]
#   body   — the entry body (markdown) on STDIN (heredoc); required, <= 64 KB
#   entryType — IssueFix | Caveat | Requirement | Pattern
#   severity  — Info | Warning | Critical
#   source    — optional, default "claude-session"
#   tags-csv  — optional comma-separated tag list
#
# Config (precedence: env > config file > default), file as in the read path
# (~/.config/expertise-search/config, KEY=VALUE, mode 600, user-provisioned):
#   EXPERTISE_SEARCH_URL           base URL (default http://127.0.0.1:8080)
#   EXPERTISE_SEARCH_API_KEY       bearer token (required)
#   EXPERTISE_ALLOW_LIMA_GATEWAY   =1 also allow host.lima.internal/192.168.5.2
#   EXPERTISE_ALLOW_WRITE          =1 enable create (required for any write)
#   EXPERTISE_ALLOW_WRITE_REMOTE   =1 additionally required when the host was
#                                  allowed via the Lima predicate (ADR-096)
#
# Exit codes (0-8 match expertise-search.sh):
#   0  success (created; stdout = verbatim response body)
#   2  config/precondition failure   7  other HTTP error
#   3  non-allowed base URL refused  8  network/transport failure
#   4  readiness check failed        9  write not enabled (opt-in missing)
#   5  auth failure (401/403)       10  secret detected in body — refused
#   6  rate limited (429)           11  near-duplicate (409; body suppressed)
#
# Token hygiene: key via -H @file, xtrace suppressed around every line that
# expands it; umask 077 covers every temp file; no redirects followed; the
# Idempotency-Key is random (never content-derived, never caller-supplied);
# the 409 body is never echoed (agent-expertise-api#209; relaxation: #97).
# The server's `tenant` field is deliberately never sent — it would bypass
# the draft/review queue. bash-3.2-safe (macOS system bash).

set -euo pipefail
umask 077

CONFIG_FILE="${HOME}/.config/expertise-search/config"
DEFAULT_BASE_URL="http://127.0.0.1:8080"
CONNECT_TIMEOUT="${EXPERTISE_SEARCH_CONNECT_TIMEOUT:-3}"
MAX_TIME="${EXPERTISE_SEARCH_MAX_TIME:-15}"
MAX_BODY_BYTES=65536

# Inline helper (rules/script-output-conventions.md): invoked through the
# ~/.claude/skills symlink from arbitrary working directories — must run
# standalone, cannot assume a resolvable scripts/lib/log.sh.
err() { printf 'ERROR [%s] %s\n' "$1" "$2" >&2; }

# --- Arguments ---------------------------------------------------------------

if [ $# -lt 4 ] || [ $# -gt 6 ]; then
  err "args" "usage: $0 <domain> <title> <entryType> <severity> [source] [tags-csv]  (body on stdin)"
  exit 2
fi
DOMAIN="$1"
TITLE="$2"
ENTRY_TYPE="$3"
SEVERITY="$4"
SOURCE="${5:-claude-session}"
TAGS_CSV="${6:-}"

[ -n "$DOMAIN" ] || { err "args" "domain must be non-empty"; exit 2; }
[ -n "$TITLE" ]  || { err "args" "title must be non-empty"; exit 2; }

# entryType/severity are always sent explicitly — the server silently
# mis-defaults omitted values (agent-expertise-api#489 class of bug).
case "$ENTRY_TYPE" in
  IssueFix|Caveat|Requirement|Pattern) : ;;
  *) err "args" "entryType must be one of: IssueFix Caveat Requirement Pattern (got: $ENTRY_TYPE)"; exit 2 ;;
esac
case "$SEVERITY" in
  Info|Warning|Critical) : ;;
  *) err "args" "severity must be one of: Info Warning Critical (got: $SEVERITY)"; exit 2 ;;
esac

command -v curl >/dev/null 2>&1 || { err "deps" "curl is required but not found"; exit 2; }

# --- Body (stdin, hard-capped — refused, never truncated) --------------------

BODY="$(head -c "$((MAX_BODY_BYTES + 1))")"
body_bytes="$(printf '%s' "$BODY" | wc -c | tr -d ' ')"
if [ "$body_bytes" -eq 0 ]; then
  err "body" "entry body must be provided on stdin (heredoc) and be non-empty"
  exit 2
fi
if [ "$body_bytes" -gt "$MAX_BODY_BYTES" ]; then
  err "body" "entry body exceeds ${MAX_BODY_BYTES} bytes — refusing (never truncated-then-sent)"
  exit 2
fi

# --- Config helpers ----------------------------------------------------------

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

# resolve_opt <ENV_NAME>: env value wins, else config file, else empty.
resolve_opt() {
  local v
  eval "v=\"\${$1:-}\""
  [ -n "$v" ] || v="$(config_get "$1" || true)"
  printf '%s' "$v"
}

# --- Host gates (keep in lockstep with expertise-search.sh) ------------------

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

# Fixed two-entry Lima host-gateway predicate (ADR-096). The set is closed by
# design — never extend it from config; a free-form host key would let a
# tampered config point the bearer token at an arbitrary host.
is_lima_gateway_host() {
  case "$1" in
    host.lima.internal|HOST.LIMA.INTERNAL) return 0 ;;
    192.168.5.2) return 0 ;;
  esac
  return 1
}

# --- Resolve config ----------------------------------------------------------

if [ -f "$CONFIG_FILE" ]; then
  check_config_perms "$CONFIG_FILE" || exit 2
fi

BASE_URL="${EXPERTISE_SEARCH_URL:-}"
[ -n "$BASE_URL" ] || BASE_URL="$(config_get EXPERTISE_SEARCH_URL || true)"
[ -n "$BASE_URL" ] || BASE_URL="$DEFAULT_BASE_URL"
BASE_URL="${BASE_URL%/}"

# Scheme allowlist: refuse anything but http/https BEFORE the host check, so a
# curl-supported smuggling scheme (gopher://, dict://, file://, …) can never
# reach curl even when its host component is allowed. Defense in depth with
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

HOST_VIA_LIMA=0
if ! is_loopback_host "$host"; then
  if [ "$(resolve_opt EXPERTISE_ALLOW_LIMA_GATEWAY)" = "1" ] && is_lima_gateway_host "$host"; then
    HOST_VIA_LIMA=1
  else
    err "loopback" "refusing base URL host: $host (loopback only, or the Lima host-gateway with EXPERTISE_ALLOW_LIMA_GATEWAY=1 — ADR-096)"
    exit 3
  fi
fi

# --- Write gates (before any network call) -----------------------------------

if [ "$(resolve_opt EXPERTISE_ALLOW_WRITE)" != "1" ]; then
  err "write-gate" "write-back is disabled. Set EXPERTISE_ALLOW_WRITE=1 in the config to opt in to create-only writes (ADR-096)."
  exit 9
fi
if [ "$HOST_VIA_LIMA" = "1" ] && [ "$(resolve_opt EXPERTISE_ALLOW_WRITE_REMOTE)" != "1" ]; then
  err "write-gate" "writes over the Lima host-gateway require EXPERTISE_ALLOW_WRITE_REMOTE=1 in addition to EXPERTISE_ALLOW_WRITE=1 (ADR-096)."
  exit 9
fi

# --- Secret scan (fail-closed, category-only; before any network call) -------

# Keep in lockstep with hooks/secrets-guard.sh and
# hooks/session-secrets-guard.sh SECRET_PATTERNS (ADR-095; validate.sh
# check_lockstep_duplication enforces byte-identity). The PEM alternative uses
# the optional-group form because BSD grep rejects empty alternation (ADR-053).
SECRET_PATTERNS='-----BEGIN (RSA |EC |OPENSSH |DSA |PGP |ENCRYPTED )?PRIVATE KEY|(^|[^A-Z0-9])(AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}([^A-Z0-9]|$)|gh[oprsu]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{82,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|[Aa]uthorization: [Bb]earer [A-Za-z0-9._~+/=-]{20,}'

# One concatenated buffer of every string field closes the same-call
# field-splitting gap (ADR-096). All probes are boolean (`grep -q`): the
# matched text never enters a variable and is never echoed — do not ever
# replace these with -o/sed extraction for diagnostics.
SCAN_BUFFER="${DOMAIN}
${TITLE}
${BODY}
${SOURCE}
${TAGS_CSV}"

if printf '%s' "$SCAN_BUFFER" | grep -qE -- "$SECRET_PATTERNS"; then
  categories=""
  printf '%s' "$SCAN_BUFFER" | grep -qE -- '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP |ENCRYPTED )?PRIVATE KEY' && categories="$categories pem-private-key"
  printf '%s' "$SCAN_BUFFER" | grep -qE -- '(^|[^A-Z0-9])(AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}([^A-Z0-9]|$)' && categories="$categories aws-access-key"
  printf '%s' "$SCAN_BUFFER" | grep -qE -- 'gh[oprsu]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{82,}' && categories="$categories github-token"
  printf '%s' "$SCAN_BUFFER" | grep -qE -- 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' && categories="$categories signed-jwt"
  printf '%s' "$SCAN_BUFFER" | grep -qE -- '[Aa]uthorization: [Bb]earer [A-Za-z0-9._~+/=-]{20,}' && categories="$categories authorization-bearer"
  err "secret-scan" "entry content appears to contain a credential (${categories# }). Refusing to publish a secret into an expertise entry — remove it and retry."
  exit 10
fi

# --- JSON construction (pure bash 3.2; fail closed on residual controls) -----

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# RFC 8259 requires escaping all C0 controls; we escape \t \r \n and refuse
# anything else rather than emit invalid JSON.
has_residual_ctrl() {
  [ -n "$(printf '%s' "$1" | tr -d '\t\r\n' | LC_ALL=C tr -dc '[:cntrl:]')" ]
}

for _f in "$DOMAIN" "$TITLE" "$BODY" "$SOURCE" "$TAGS_CSV"; do
  if has_residual_ctrl "$_f"; then
    err "body" "a field contains a control character that cannot be JSON-escaped — refusing"
    exit 2
  fi
done

TAGS_JSON=""
if [ -n "$TAGS_CSV" ]; then
  _sep=""
  _rest="$TAGS_CSV,"
  while [ -n "$_rest" ]; do
    _tag="${_rest%%,*}"
    _rest="${_rest#*,}"
    # trim surrounding spaces
    _tag="${_tag#"${_tag%%[![:space:]]*}"}"
    _tag="${_tag%"${_tag##*[![:space:]]}"}"
    [ -n "$_tag" ] || continue
    TAGS_JSON="${TAGS_JSON}${_sep}\"$(json_escape "$_tag")\""
    _sep=","
  done
fi

# --- Idempotency-Key (random, never content-derived or caller-supplied) ------

gen_idempotency_key() {
  local hex vh
  if command -v uuidgen >/dev/null 2>&1; then uuidgen; return 0; fi
  if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid; return 0; fi
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    hex="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
    [ "${#hex}" -eq 32 ] || return 1
    # RFC 4122 v4 fixup: version nibble = 4, variant top bits = 10
    vh="$(printf '%x' $(( (0x${hex:16:1} & 0x3) | 0x8 )))"
    printf '%s-%s-4%s-%s%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "$vh" "${hex:17:3}" "${hex:20:12}"
    return 0
  fi
  return 1
}

IDEM_KEY="$(gen_idempotency_key)" || {
  err "idempotency" "no usable random source for the Idempotency-Key (uuidgen, /proc, /dev/urandom all unavailable) — refusing"
  exit 2
}

# --- Resolve the API key (xtrace suppressed for every expanding line) --------

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

# Literal live-key check: a bare opaque token matches no ADR-095 pattern, so
# scan for the script's own key as a substring (still xtrace-suppressed).
case "$SCAN_BUFFER" in
  *"$API_KEY"*)
    restore_xtrace
    err "secret-scan" "entry content contains this script's own API key. Refusing to publish a secret into an expertise entry — remove it and retry."
    exit 10
    ;;
esac

header_file="$(mktemp "${TMPDIR:-/tmp}/expertise-create-h.XXXXXX")" || {
  restore_xtrace
  err "tmp" "mktemp failed"; exit 2
}
payload_file="$(mktemp "${TMPDIR:-/tmp}/expertise-create-p.XXXXXX")" || {
  rm -f "$header_file"
  restore_xtrace
  err "tmp" "mktemp failed"; exit 2
}
body_file="$(mktemp "${TMPDIR:-/tmp}/expertise-create-b.XXXXXX")" || {
  rm -f "$header_file" "$payload_file"
  restore_xtrace
  err "tmp" "mktemp failed"; exit 2
}
resp_headers_file="$(mktemp "${TMPDIR:-/tmp}/expertise-create-r.XXXXXX")" || {
  rm -f "$header_file" "$payload_file" "$body_file"
  restore_xtrace
  err "tmp" "mktemp failed"; exit 2
}
trap 'rm -f "$header_file" "$payload_file" "$body_file" "$resp_headers_file"' EXIT
printf 'Authorization: Bearer %s\n' "$API_KEY" > "$header_file"
unset API_KEY

restore_xtrace

# --- Payload (no tenant field, ever — ADR-096) --------------------------------

{
  printf '{'
  printf '"domain":"%s",' "$(json_escape "$DOMAIN")"
  printf '"title":"%s",' "$(json_escape "$TITLE")"
  printf '"body":"%s",' "$(json_escape "$BODY")"
  printf '"entryType":"%s",' "$ENTRY_TYPE"
  printf '"severity":"%s",' "$SEVERITY"
  if [ -n "$TAGS_JSON" ]; then
    printf '"tags":[%s],' "$TAGS_JSON"
  fi
  printf '"source":"%s"' "$(json_escape "$SOURCE")"
  printf '}'
} > "$payload_file"

# --- Readiness gate (unauthenticated; never burns the rate budget) -----------

ready_code="$(curl -sS --proto '=http,https' -o /dev/null -w '%{http_code}' \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$CONNECT_TIMEOUT" \
  "${BASE_URL}/health/ready" 2>/dev/null)" || ready_code=""
if [ "$ready_code" != "200" ]; then
  err "readiness" "API not ready at ${BASE_URL} (/health/ready returned ${ready_code:-no response})"
  exit 4
fi

# --- Create -------------------------------------------------------------------

curl_rc=0
http_code="$(curl -sS --proto '=http,https' \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  -H @"$header_file" \
  -H 'Content-Type: application/json' \
  -H 'X-Actor-Class: agent' \
  -H "Idempotency-Key: ${IDEM_KEY}" \
  --data-binary @"$payload_file" \
  -D "$resp_headers_file" -o "$body_file" -w '%{http_code}' \
  "${BASE_URL}/expertise")" || curl_rc=$?

if [ "$curl_rc" -ne 0 ]; then
  err "network" "curl transport failure (rc=$curl_rc) against ${BASE_URL}"
  exit 8
fi

case "$http_code" in
  200|201)
    cat "$body_file"
    exit 0
    ;;
  401|403)
    err "auth" "HTTP $http_code — API key invalid, expired, or missing the expertise.write.draft scope"
    cat "$body_file" >&2
    exit 5
    ;;
  409)
    # Deliberately suppressed: a 409 body may contain another principal's
    # stored entry (agent-expertise-api#209). Never echo it; relaxation
    # tracked in #97.
    err "duplicate" "HTTP 409 — an equivalent entry already exists (near-duplicate). Do not retry; find and reuse it via /expertise search."
    exit 11
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
    err "http" "HTTP $http_code from ${BASE_URL}/expertise"
    cat "$body_file" >&2
    exit 7
    ;;
esac
