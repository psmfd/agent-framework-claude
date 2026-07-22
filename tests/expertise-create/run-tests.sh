#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for skills/expertise/scripts/expertise-create.sh
# (the /expertise skill's create-only write-back helper, ADR-096)
#
# Contract under test: expertise-create.sh <domain> <title> <entryType>
# <severity> [source] [tags-csv] with the body on stdin; stdout is the
# verbatim API response on success, diagnostics on stderr, exit codes
# 0/2/3/4/5/6/7/8/9/10/11 per the script header.
#
# Coverage:
#   1. bad argument counts            -> exit 2
#   2. invalid entryType/severity     -> exit 2
#   3. empty body on stdin            -> exit 2
#   4. oversize body (>64 KB)         -> exit 2, refusal (never truncated)
#   5. unescapable control char       -> exit 2
#   6. non-loopback, non-Lima URL     -> exit 3
#   7. Lima host without opt-in       -> exit 3
#   8. loopback, no ALLOW_WRITE       -> exit 9 (before any network call)
#   9. Lima host, no ALLOW_WRITE_REMOTE -> exit 9
#  10. secret in body (fake AWS key)  -> exit 10, category named, literal absent
#  11. body containing the live API key -> exit 10
#  12. success against stub server    -> exit 0; UUID-shaped Idempotency-Key,
#      JSON-escaped body, tags array, no "tenant" field; second call gets a
#      distinct Idempotency-Key
#  13. 401 from stub                  -> exit 5
#  14. 409 from stub                  -> exit 11, stored-entry sentinel suppressed
#  15. 429 from stub                  -> exit 6, Retry-After surfaced
#  16. 500 from stub                  -> exit 7
#  17. bash -x run leaks no token     -> token absent from all trace output
#  18. temp files cleaned up          -> no expertise-create-* left in TMPDIR
#  19. --check-only (ADR-098)         -> clean candidate exit 0 (even with a
#      non-loopback URL and no key: config/gates/key/network never reached);
#      bad enum exit 2; secret exit 10 category-only; oversize exit 2
#  (12-16, 18 SKIP when python3 is unavailable)
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
# Targets bash 3.2+ (the script's floor). Run: bash tests/expertise-create/run-tests.sh

# -e omitted: the runner must continue past a failing case to report all
# results; failures are tracked via the `errors` counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/../../skills/expertise/scripts/expertise-create.sh"

ok()   { echo "OK    [$1] $2"; }
skip() { echo "SKIP  [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
WORK="$(mktemp -d "${TMPDIR:-/tmp}/expertise-create-tests.XXXXXX")"
STUB_PID=""
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() {
  [ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

[ -f "$SUT" ] || { err "env" "script not found at $SUT"; exit 2; }
command -v curl >/dev/null 2>&1 || { err "env" "curl is required but not on PATH"; exit 2; }
BASH_BIN="$(command -v bash)"

TEST_TOKEN="test-token-123"
LOOP_URL="http://127.0.0.1:1"
LIMA_URL="http://host.lima.internal:1"

printf 'test body\n' > "$WORK/body"

# run_sut <expected-rc> <label> <stdin-file> [env VAR=VAL ...] -- <args...>
# Captures stdout/stderr to $WORK/out and $WORK/errout.
run_sut() {
  expected="$1"; label="$2"; stdin_file="$3"; shift 3
  envs=""
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    envs="$envs $1"; shift
  done
  [ "${1:-}" = "--" ] && shift
  rc=0
  # shellcheck disable=SC2086  # envs is a deliberately word-split VAR=VAL list
  env HOME="$WORK/home" $envs "$BASH_BIN" "$SUT" "$@" \
    <"$stdin_file" >"$WORK/out" 2>"$WORK/errout" || rc=$?
  if [ "$rc" -eq "$expected" ]; then
    ok "$label" "exit $rc as expected"
  else
    err "$label" "expected exit $expected, got $rc (stderr: $(head -1 "$WORK/errout" 2>/dev/null))"
    errors=$((errors + 1))
  fi
}

mkdir -p "$WORK/home"

info "1-2: argument validation"
run_sut 2 "too-few-args" "$WORK/body" -- "d" "t" "Pattern"
run_sut 2 "too-many-args" "$WORK/body" -- "d" "t" "Pattern" "Info" "s" "tags" "extra"
run_sut 2 "bad-entrytype" "$WORK/body" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Wisdom" "Info"
run_sut 2 "bad-severity" "$WORK/body" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Fatal"

info "3-5: body validation"
run_sut 2 "empty-body" /dev/null EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Info"
# 70 KB of 'a' — over the 64 KB cap; must refuse, never truncate-and-send
head -c 71680 /dev/zero | tr '\0' 'a' > "$WORK/bigbody"
run_sut 2 "oversize-body" "$WORK/bigbody" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Info"
grep -q "refusing" "$WORK/errout" || { err "oversize-body" "refusal message missing"; errors=$((errors + 1)); }
printf 'bad \001 control\n' > "$WORK/ctrlbody"
run_sut 2 "ctrl-char-body" "$WORK/ctrlbody" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Info"

info "6-7: URL gate"
run_sut 3 "non-loopback" "$WORK/body" EXPERTISE_SEARCH_URL="http://example.com:8080" -- "d" "t" "Pattern" "Info"
run_sut 3 "lima-no-optin" "$WORK/body" EXPERTISE_SEARCH_URL="$LIMA_URL" -- "d" "t" "Pattern" "Info"
run_sut 3 "nonlima-with-optin" "$WORK/body" EXPERTISE_SEARCH_URL="http://example.com:8080" EXPERTISE_ALLOW_LIMA_GATEWAY=1 -- "d" "t" "Pattern" "Info"

info "8-9: write gates (fire before any network call — port 1 is never contacted)"
run_sut 9 "no-allow-write" "$WORK/body" EXPERTISE_SEARCH_URL="$LOOP_URL" -- "d" "t" "Pattern" "Info"
grep -q "EXPERTISE_ALLOW_WRITE=1" "$WORK/errout" || { err "no-allow-write" "refusal does not name the opt-in key"; errors=$((errors + 1)); }
run_sut 9 "lima-no-write-remote" "$WORK/body" EXPERTISE_SEARCH_URL="$LIMA_URL" EXPERTISE_ALLOW_LIMA_GATEWAY=1 EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Info"
grep -q "EXPERTISE_ALLOW_WRITE_REMOTE=1" "$WORK/errout" || { err "lima-no-write-remote" "refusal does not name the remote opt-in key"; errors=$((errors + 1)); }

info "10-11: secret scan (category-only, fail-closed, before any network call)"
FAKE_AWS_KEY="AKIAIOSFODNN7EXAMPLE"
printf 'creds: %s in body\n' "$FAKE_AWS_KEY" > "$WORK/secretbody"
run_sut 10 "secret-in-body" "$WORK/secretbody" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$LOOP_URL" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Info"
grep -q "aws-access-key" "$WORK/errout" || { err "secret-in-body" "category not named in refusal"; errors=$((errors + 1)); }
if grep -q "$FAKE_AWS_KEY" "$WORK/out" "$WORK/errout"; then
  err "secret-in-body" "the matched secret literal was echoed"
  errors=$((errors + 1))
else
  ok "secret-not-echoed" "matched literal absent from all output"
fi
printf 'my key is %s here\n' "$TEST_TOKEN" > "$WORK/keybody"
run_sut 10 "own-key-in-body" "$WORK/keybody" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$LOOP_URL" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Info"

info "19: --check-only mode (ADR-098 — exits before config, gates, key, network)"
# Non-loopback URL + no API key + no write opt-in: every one of those would
# fail the full path (3/2/9) — check-only must still pass, proving it never
# reaches those stages.
run_sut 0 "check-only-clean" "$WORK/body" EXPERTISE_SEARCH_URL="http://example.com:8080" -- --check-only "d" "t" "Pattern" "Info"
grep -q "check-only" "$WORK/out" || { err "check-only-clean" "OK [check-only] line missing from stdout"; errors=$((errors + 1)); }
run_sut 2 "check-only-bad-enum" "$WORK/body" -- --check-only "d" "t" "Wisdom" "Info"
run_sut 2 "check-only-oversize" "$WORK/bigbody" -- --check-only "d" "t" "Pattern" "Info"
run_sut 10 "check-only-secret" "$WORK/secretbody" -- --check-only "d" "t" "Pattern" "Info"
grep -q "aws-access-key" "$WORK/errout" || { err "check-only-secret" "category not named in refusal"; errors=$((errors + 1)); }
if grep -q "$FAKE_AWS_KEY" "$WORK/out" "$WORK/errout"; then
  err "check-only-secret" "the matched secret literal was echoed"
  errors=$((errors + 1))
else
  ok "check-only-secret-not-echoed" "matched literal absent from all output"
fi
run_sut 2 "check-only-ctrl-char" "$WORK/ctrlbody" -- --check-only "d" "t" "Pattern" "Info"

# --- HTTP cases against a local stub (SKIP without python3) ------------------
if command -v python3 >/dev/null 2>&1; then
  cat > "$WORK/stub.py" <<'PYEOF'
import http.server, socketserver, json

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        if self.path == '/health/ready':
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok'); return
        self.send_response(404); self.end_headers()
    def do_POST(self):
        if self.path != '/expertise':
            self.send_response(404); self.end_headers(); return
        n = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(n).decode('utf-8', 'replace')
        try:
            body = json.loads(raw)
        except ValueError:
            self.send_response(400); self.end_headers()
            self.wfile.write(b'{"error":"invalid json"}'); return
        title = body.get('title', '')
        if self.headers.get('Authorization', '') != 'Bearer test-token-123':
            self.send_response(401); self.end_headers()
            self.wfile.write(b'{"error":"bad token"}'); return
        if title == 'dup-entry':
            self.send_response(409); self.end_headers()
            self.wfile.write(b'{"id":7,"body":"SENTINEL-FOREIGN-ENTRY"}'); return
        if title == 'rate-limit':
            self.send_response(429); self.send_header('Retry-After', '42')
            self.end_headers(); self.wfile.write(b'{"error":"rate"}'); return
        if title == 'server-err':
            self.send_response(500); self.end_headers()
            self.wfile.write(b'{"error":"boom"}'); return
        resp = json.dumps({
            'id': 42,
            'idem': self.headers.get('Idempotency-Key', ''),
            'ctype': self.headers.get('Content-Type', ''),
            'actor': self.headers.get('X-Actor-Class', ''),
            'echo': body,
        }).encode('utf-8')
        self.send_response(201)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(resp)

with socketserver.TCPServer(('127.0.0.1', 0), H) as srv:
    print(srv.server_address[1], flush=True)
    srv.serve_forever()
PYEOF
  python3 "$WORK/stub.py" > "$WORK/port" 2>/dev/null &
  STUB_PID=$!
  tries=0
  while [ ! -s "$WORK/port" ] && [ "$tries" -lt 50 ]; do
    tries=$((tries + 1)); sleep 0.1
  done
  PORT="$(cat "$WORK/port" 2>/dev/null || true)"
  if [ -z "$PORT" ]; then
    err "stub" "stub server failed to start"
    errors=$((errors + 1))
  else
    STUB_URL="http://127.0.0.1:$PORT"
    info "12-16: HTTP cases against stub on port $PORT"
    export TMPDIR="$WORK/tmp"; mkdir -p "$TMPDIR"

    printf 'line one\nline "two" with quotes\n' > "$WORK/mdbody"
    run_sut 0 "success" "$WORK/mdbody" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" EXPERTISE_ALLOW_WRITE=1 -- "test-domain" "test title" "Pattern" "Info" "test-suite" "one, two"
    idem1="$(awk -F'"idem": "' 'NF>1 { split($2,a,"\""); print a[1] }' "$WORK/out")"
    if printf '%s' "$idem1" | grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
      ok "idem-shape" "Idempotency-Key is UUID-shaped"
    else
      err "idem-shape" "Idempotency-Key not UUID-shaped: $idem1"
      errors=$((errors + 1))
    fi
    grep -q '"domain": "test-domain"' "$WORK/out" || { err "payload-domain" "domain missing from echoed payload"; errors=$((errors + 1)); }
    grep -q 'line \\"two\\" with quotes' "$WORK/out" || { err "payload-escape" "escaped multi-line body not round-tripped"; errors=$((errors + 1)); }
    grep -q '"tags": \["one", "two"\]' "$WORK/out" || { err "payload-tags" "tags array missing or malformed"; errors=$((errors + 1)); }
    grep -q '"entryType": "Pattern"' "$WORK/out" || { err "payload-enum" "entryType missing from echoed payload"; errors=$((errors + 1)); }
    grep -q '"actor": "agent"' "$WORK/out" || { err "actor-class" "X-Actor-Class: agent header missing"; errors=$((errors + 1)); }
    if grep -q '"tenant"' "$WORK/out"; then
      err "no-tenant" "payload contains a tenant field — it must never be sent"
      errors=$((errors + 1))
    else
      ok "no-tenant" "tenant field absent from payload"
    fi

    run_sut 0 "success-2" "$WORK/mdbody" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" EXPERTISE_ALLOW_WRITE=1 -- "test-domain" "second title" "Caveat" "Warning"
    idem2="$(awk -F'"idem": "' 'NF>1 { split($2,a,"\""); print a[1] }' "$WORK/out")"
    if [ -n "$idem1" ] && [ "$idem1" != "$idem2" ]; then
      ok "idem-unique" "fresh Idempotency-Key per invocation"
    else
      err "idem-unique" "Idempotency-Key repeated across invocations"
      errors=$((errors + 1))
    fi

    run_sut 5 "auth-fail" "$WORK/body" EXPERTISE_SEARCH_API_KEY="wrong-token-9999" EXPERTISE_SEARCH_URL="$STUB_URL" EXPERTISE_ALLOW_WRITE=1 -- "d" "t" "Pattern" "Info"
    run_sut 11 "near-duplicate" "$WORK/body" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" EXPERTISE_ALLOW_WRITE=1 -- "d" "dup-entry" "Pattern" "Info"
    if grep -q "SENTINEL-FOREIGN-ENTRY" "$WORK/out" "$WORK/errout"; then
      err "409-suppressed" "409 response body was echoed — must be suppressed (#97)"
      errors=$((errors + 1))
    else
      ok "409-suppressed" "409 body suppressed as designed"
    fi
    run_sut 6 "rate-limit" "$WORK/body" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" EXPERTISE_ALLOW_WRITE=1 -- "d" "rate-limit" "Pattern" "Info"
    grep -q "retry after 42s" "$WORK/errout" || { err "rate-limit" "Retry-After value not surfaced"; errors=$((errors + 1)); }
    run_sut 7 "server-err" "$WORK/body" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" EXPERTISE_ALLOW_WRITE=1 -- "d" "server-err" "Pattern" "Info"

    info "18: temp file cleanup"
    leftovers="$(find "$TMPDIR" -name 'expertise-create-*' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$leftovers" = "0" ]; then
      ok "tmp-cleanup" "no temp files left behind"
    else
      err "tmp-cleanup" "$leftovers expertise-create-* file(s) left in TMPDIR"
      errors=$((errors + 1))
    fi
    unset TMPDIR
  fi
else
  skip "http-cases" "python3 not available — stub-server cases 12-16/18 skipped"
fi

info "17: xtrace never leaks the token"
rc=0
env HOME="$WORK/home" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" \
    EXPERTISE_SEARCH_URL="$LOOP_URL" EXPERTISE_ALLOW_WRITE=1 \
    "$BASH_BIN" -x "$SUT" "d" "t" "Pattern" "Info" <"$WORK/body" >"$WORK/out" 2>"$WORK/errout" || rc=$?
if grep -q "$TEST_TOKEN" "$WORK/out" "$WORK/errout"; then
  err "xtrace-leak" "token appeared in bash -x output"
  errors=$((errors + 1))
else
  ok "xtrace-leak" "token absent from bash -x trace (exit $rc)"
fi

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors errors, 0 warnings"
  exit 1
else
  echo "PASS — 0 errors, 0 warnings"
  exit 0
fi
