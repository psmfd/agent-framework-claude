#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for skills/expertise/scripts/expertise-search.sh
# (the /expertise skill's bundled helper, ADR-094)
#
# Contract under test: expertise-search.sh <query> [limit]; stdout is the
# verbatim API body on success, diagnostics on stderr, exit codes
# 0/2/3/4/5/6/7/8 per the script header.
#
# Coverage:
#   1. no arguments                    -> exit 2, usage on stderr
#   2. extra args (unquoted query)     -> exit 2, quoting hint
#   3. non-integer limit               -> exit 2
#   4. out-of-range limit (0, 101)     -> exit 2
#   5. non-loopback base URL           -> exit 3 (gate fires before key check);
#      Lima host-gateway pair refused without EXPERTISE_ALLOW_LIMA_GATEWAY=1,
#      passes the gate with it (ADR-096), arbitrary hosts refused regardless
#   6. scheme-less base URL            -> exit 2
#   7. userinfo in base URL            -> exit 3
#   8. config file with open perms     -> exit 2, refusal names chmod 600
#   9. no API key anywhere             -> exit 2
#  10. API down (closed loopback port) -> exit 4
#  11. bash -x run leaks no token      -> token absent from all trace output
#  12. success against stub server     -> exit 0, stdout is the exact body
#  13. 401 from stub                   -> exit 5
#  14. 429 from stub                   -> exit 6, Retry-After surfaced
#  15. 500 from stub                   -> exit 7
#  16. temp header files cleaned up    -> no expertise-search-* left in TMPDIR
#  (12-16 SKIP when python3 is unavailable)
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
# Targets bash 3.2+ (the script's floor). Run: bash tests/expertise-search/run-tests.sh

# -e omitted: the runner must continue past a failing case to report all
# results; failures are tracked via the `errors` counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/../../skills/expertise/scripts/expertise-search.sh"

ok()   { echo "OK    [$1] $2"; }
skip() { echo "SKIP  [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
WORK="$(mktemp -d "${TMPDIR:-/tmp}/expertise-tests.XXXXXX")"
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

# run_sut <expected-rc> <label> [env VAR=VAL ...] -- <args...>
# Captures stdout/stderr to $WORK/out and $WORK/errout.
run_sut() {
  expected="$1"; label="$2"; shift 2
  envs=""
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    envs="$envs $1"; shift
  done
  [ "${1:-}" = "--" ] && shift
  rc=0
  # shellcheck disable=SC2086  # envs is a deliberately word-split VAR=VAL list
  env HOME="$WORK/home" $envs "$BASH_BIN" "$SUT" "$@" \
    >"$WORK/out" 2>"$WORK/errout" || rc=$?
  if [ "$rc" -eq "$expected" ]; then
    ok "$label" "exit $rc as expected"
  else
    err "$label" "expected exit $expected, got $rc (stderr: $(head -1 "$WORK/errout" 2>/dev/null))"
    errors=$((errors + 1))
  fi
}

mkdir -p "$WORK/home"

info "1-4: argument validation"
run_sut 2 "no-args" --
run_sut 2 "extra-args" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" -- unquoted query words
grep -q "quote the query" "$WORK/errout" || { err "extra-args" "missing quoting hint"; errors=$((errors + 1)); }
run_sut 2 "limit-nonint" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" -- "q" "ten"
run_sut 2 "limit-zero" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" -- "q" "0"
run_sut 2 "limit-101" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" -- "q" "101"

info "5-7: base URL gates"
run_sut 3 "non-loopback" EXPERTISE_SEARCH_URL="http://example.com:8080" -- "q"
run_sut 2 "no-scheme" EXPERTISE_SEARCH_URL="127.0.0.1:8080" -- "q"
run_sut 3 "userinfo" EXPERTISE_SEARCH_URL="http://user@127.0.0.1:8080" -- "q"
# Non-http(s) scheme must be refused (exit 3) even when the host is loopback —
# blocks curl-supported smuggling schemes (gopher/dict/file) reaching curl.
run_sut 3 "scheme-gopher" EXPERTISE_SEARCH_URL="gopher://127.0.0.1:6379/x" -- "q"
run_sut 3 "scheme-file" EXPERTISE_SEARCH_URL="file://127.0.0.1/etc/passwd" -- "q"
# A '@' in the PATH (not userinfo) with a loopback host must not be misread as
# userinfo — it fails later on readiness (exit 4), not the userinfo gate (3).
run_sut 4 "at-in-path" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="http://127.0.0.1:1/foo@bar" -- "q"
# Lima host-gateway opt-in (ADR-096): the fixed pair is refused without the
# opt-in; with it, the URL gate passes and the run fails later at readiness
# (exit 4 whether host.lima.internal resolves or not — port 1 never answers);
# an arbitrary host is still refused even with the opt-in set.
run_sut 3 "lima-no-optin" EXPERTISE_SEARCH_URL="http://host.lima.internal:1" -- "q"
run_sut 4 "lima-optin" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_ALLOW_LIMA_GATEWAY=1 EXPERTISE_SEARCH_URL="http://host.lima.internal:1" -- "q"
run_sut 3 "lima-optin-other-host" EXPERTISE_ALLOW_LIMA_GATEWAY=1 EXPERTISE_SEARCH_URL="http://example.com:8080" -- "q"

info "8: config file permission refusal"
mkdir -p "$WORK/home/.config/expertise-search"
printf 'EXPERTISE_SEARCH_API_KEY=%s\n' "$TEST_TOKEN" > "$WORK/home/.config/expertise-search/config"
chmod 644 "$WORK/home/.config/expertise-search/config"
run_sut 2 "config-perms" -- "q"
grep -q "chmod 600" "$WORK/errout" || { err "config-perms" "refusal does not name chmod 600"; errors=$((errors + 1)); }
chmod 600 "$WORK/home/.config/expertise-search/config"

info "9: missing key"
rm -f "$WORK/home/.config/expertise-search/config"
run_sut 2 "no-key" -- "q"

info "10: API down (closed loopback port)"
run_sut 4 "api-down" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="http://127.0.0.1:1" -- "q"

info "11: xtrace never leaks the token"
rc=0
env HOME="$WORK/home" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" \
    EXPERTISE_SEARCH_URL="http://127.0.0.1:1" \
    "$BASH_BIN" -x "$SUT" "q" >"$WORK/out" 2>"$WORK/errout" || rc=$?
if grep -q "$TEST_TOKEN" "$WORK/out" "$WORK/errout"; then
  err "xtrace-leak" "token appeared in bash -x output"
  errors=$((errors + 1))
else
  ok "xtrace-leak" "token absent from bash -x trace (exit $rc)"
fi

# --- HTTP cases against a local stub (SKIP without python3) ------------------
if command -v python3 >/dev/null 2>&1; then
  cat > "$WORK/stub.py" <<'PYEOF'
import http.server, socketserver

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        if self.path == '/health/ready':
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok'); return
        if self.path.startswith('/expertise/search/semantic'):
            if 'q=auth-fail' in self.path:
                self.send_response(401); self.end_headers()
                self.wfile.write(b'{"error":"unauthorized"}'); return
            if 'q=rate-limit' in self.path:
                self.send_response(429); self.send_header('Retry-After', '42')
                self.end_headers(); self.wfile.write(b'{"error":"rate"}'); return
            if 'q=server-err' in self.path:
                self.send_response(500); self.end_headers()
                self.wfile.write(b'{"error":"boom"}'); return
            if self.headers.get('Authorization', '') != 'Bearer test-token-123':
                self.send_response(401); self.end_headers()
                self.wfile.write(b'{"error":"bad token"}'); return
            self.send_response(200); self.end_headers()
            self.wfile.write(b'{"results":[{"id":1,"title":"entry"}]}'); return
        self.send_response(404); self.end_headers()

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
    info "12-15: HTTP cases against stub on port $PORT"
    export TMPDIR="$WORK/tmp"; mkdir -p "$TMPDIR"

    run_sut 0 "success" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" -- "kafka partitions" "5"
    body='{"results":[{"id":1,"title":"entry"}]}'
    if [ "$(cat "$WORK/out")" = "$body" ]; then
      ok "success-body" "stdout is the exact verbatim body"
    else
      err "success-body" "stdout differs from the API body"
      errors=$((errors + 1))
    fi

    run_sut 5 "auth-fail" EXPERTISE_SEARCH_API_KEY="wrong" EXPERTISE_SEARCH_URL="$STUB_URL" -- "auth-fail"
    run_sut 6 "rate-limit" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" -- "rate-limit"
    grep -q "retry after 42s" "$WORK/errout" || { err "rate-limit" "Retry-After value not surfaced"; errors=$((errors + 1)); }
    run_sut 7 "server-err" EXPERTISE_SEARCH_API_KEY="$TEST_TOKEN" EXPERTISE_SEARCH_URL="$STUB_URL" -- "server-err"

    info "16: temp file cleanup"
    leftovers="$(find "$TMPDIR" -name 'expertise-search-*' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$leftovers" = "0" ]; then
      ok "tmp-cleanup" "no header/body temp files left behind"
    else
      err "tmp-cleanup" "$leftovers expertise-search-* file(s) left in TMPDIR"
      errors=$((errors + 1))
    fi
    unset TMPDIR
  fi
else
  skip "http-cases" "python3 not available — stub-server cases 12-16 skipped"
fi

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors errors, 0 warnings"
  exit 1
else
  echo "PASS — 0 errors, 0 warnings"
  exit 0
fi
