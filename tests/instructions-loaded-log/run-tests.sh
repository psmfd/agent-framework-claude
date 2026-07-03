#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for hooks/instructions-loaded-log.sh (the
# InstructionsLoaded observability logger, ADR-092)
#
# Contract under test: stdin=JSON InstructionsLoaded payload. ALWAYS exit 0.
# When the payload has a file_path, append one compact JSON metadata line to
# ${CLAUDE_CONFIG_DIR}/logs/instructions-loaded.jsonl (dir 700, file 600);
# otherwise write nothing. Metadata only — never file content. Fail-open on
# missing jq / empty stdin / absent file_path.
#
# Coverage:
#   1. session_start load        -> logged with correct fields
#   2. path_glob_match load      -> logged (extra globs field ignored)
#   3. missing file_path         -> exit 0, NO log file created
#   4. empty stdin               -> exit 0, no write
#   5. jq absent                 -> exit 0, no crash (fail-open)
#   6. dir 700 / file 600 perms
#   7. metadata-only             -> file CONTENT never appears in the log line
#   8. bytes == actual file size
#   9. SKIP_INSTRUCTIONS_LOG=1    -> exit 0, no write
#  10. file_path set but unreadable/absent -> logged with bytes null
#
# Output per rules/script-output-conventions.md. Exit: 0 all pass, 1 fail, 2 precond.
# Targets bash 3.2+. Run: bash tests/instructions-loaded-log/run-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/instructions-loaded-log.sh"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
TMPFILES=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap
cleanup() { local f; for f in ${TMPFILES[@]+"${TMPFILES[@]}"}; do [ -n "$f" ] && rm -rf "$f"; done; }
trap cleanup EXIT

for cmd in jq bash wc; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd required but not on PATH"; exit 2; }
done
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }
BASH_BIN="$(command -v bash)"

# Feed the hook via file redirection (not a pipe): the SKIP path exits before
# reading stdin, and `printf | hook` under `set -o pipefail` would then race the
# hook's pipe close and return EPIPE (non-deterministic across bash versions;
# bash 3.2 loses it). A redirected file has no such race.
INFILE="$(mktemp)"; TMPFILES+=("$INFILE")

build_path_without_jq() {
  local dir c src
  dir="$(mktemp -d)"; TMPFILES+=("$dir")
  for c in cat sed awk printf tr wc date mkdir chmod; do
    src="$(command -v "$c" 2>/dev/null)" || continue
    case "$src" in /*) ln -s "$src" "$dir/$c" ;; esac
  done
  printf '%s' "$dir"
}

# mk_input FILE_PATH LOAD_REASON MEMORY_TYPE [SESSION_ID]
mk_input() {
  jq -nc --arg fp "$1" --arg lr "$2" --arg mt "$3" --arg sid "${4:-sess-1}" \
    '{hook_event_name:"InstructionsLoaded", session_id:$sid, file_path:$fp, load_reason:$lr, memory_type:$mt}'
}

# Each case gets a fresh CLAUDE_CONFIG_DIR so the real ~/.claude is never touched.
CFG=""
new_cfg() { CFG="$(mktemp -d)"; TMPFILES+=("$CFG"); }
LOGFILE() { printf '%s/logs/instructions-loaded.jsonl' "$CFG"; }

RC=0
run_hook() {
  local payload="$1" use_path="${2:-$PATH}"
  printf '%s' "$payload" > "$INFILE"
  RC=0
  CLAUDE_CONFIG_DIR="$CFG" PATH="$use_path" "$BASH_BIN" "$HOOK" < "$INFILE" >/dev/null 2>&1 || RC=$?
}

# --- Case 1: session_start load -> logged with correct fields ------------------
case_session_start() {
  new_cfg
  local f; f="$(mktemp)"; TMPFILES+=("$f"); printf 'abcde' > "$f"   # 5 bytes
  run_hook "$(mk_input "$f" session_start Project)"
  if [ "$RC" != 0 ]; then err "session-start" "expected exit 0, got $RC"; errors=$((errors+1)); return; fi
  local lf; lf="$(LOGFILE)"
  if [ ! -f "$lf" ]; then err "session-start" "no log file written"; errors=$((errors+1)); return; fi
  if jq -e '.load_reason=="session_start" and .memory_type=="Project" and .bytes==5 and (.file_path|length>0) and (.ts|length>0)' "$lf" >/dev/null 2>&1; then
    ok "session-start" "logged with correct fields (bytes=5)"
  else
    err "session-start" "log line fields wrong: $(cat "$lf")"; errors=$((errors+1))
  fi
}

# --- Case 2: path_glob_match load -> logged -----------------------------------
case_path_glob() {
  new_cfg
  local f; f="$(mktemp)"; TMPFILES+=("$f"); printf 'x' > "$f"
  # include an extra globs field the logger should ignore
  run_hook "$(jq -nc --arg fp "$f" '{hook_event_name:"InstructionsLoaded",session_id:"s",file_path:$fp,load_reason:"path_glob_match",memory_type:"Project",globs:["**/*.sh"]}')"
  local lf; lf="$(LOGFILE)"
  if [ -f "$lf" ] && jq -e '.load_reason=="path_glob_match"' "$lf" >/dev/null 2>&1; then
    ok "path-glob" "logged (extra globs field ignored)"
  else
    err "path-glob" "not logged correctly"; errors=$((errors+1))
  fi
}

# --- Case 3: missing file_path -> no log file ---------------------------------
case_missing_file_path() {
  new_cfg
  run_hook '{"hook_event_name":"InstructionsLoaded","session_id":"s","load_reason":"session_start","memory_type":"User"}'
  if [ "$RC" = 0 ] && [ ! -e "$CFG/logs" ]; then
    ok "missing-file-path" "exit 0, no log dir/file created"
  else
    err "missing-file-path" "expected no log dir; rc=$RC logs-exists=$([ -e "$CFG/logs" ] && echo yes || echo no)"; errors=$((errors+1))
  fi
}

# --- Case 4: empty stdin -> no write ------------------------------------------
case_empty_stdin() {
  new_cfg
  run_hook ""
  if [ "$RC" = 0 ] && [ ! -e "$CFG/logs" ]; then ok "empty-stdin" "exit 0, no write"; else err "empty-stdin" "rc=$RC"; errors=$((errors+1)); fi
}

# --- Case 5: jq absent -> fail-open -------------------------------------------
case_jq_missing() {
  new_cfg
  local f; f="$(mktemp)"; TMPFILES+=("$f"); printf 'x' > "$f"
  run_hook "$(mk_input "$f" session_start Project)" "$(build_path_without_jq)"
  if [ "$RC" = 0 ] && [ ! -e "$CFG/logs" ]; then ok "jq-missing" "exit 0, no write (fail-open)"; else err "jq-missing" "rc=$RC"; errors=$((errors+1)); fi
}

# --- Case 6: dir 700 / file 600 perms -----------------------------------------
case_perms() {
  new_cfg
  local f; f="$(mktemp)"; TMPFILES+=("$f"); printf 'x' > "$f"
  run_hook "$(mk_input "$f" session_start Project)"
  local dperm fperm
  # shellcheck disable=SC2012  # ls is the portable way to read the mode string
  # (stat flags differ macOS vs Linux); the path is a controlled mktemp dir.
  dperm="$(ls -ld "$CFG/logs" 2>/dev/null | cut -c1-10)"
  # shellcheck disable=SC2012
  fperm="$(ls -l "$(LOGFILE)" 2>/dev/null | cut -c1-10)"
  if [ "$dperm" = "drwx------" ] && [ "$fperm" = "-rw-------" ]; then
    ok "perms" "dir 700, file 600"
  else
    err "perms" "dir='$dperm' file='$fperm' (want drwx------ / -rw-------)"; errors=$((errors+1))
  fi
}

# --- Case 7: metadata-only -> file content never in the log -------------------
case_metadata_only() {
  new_cfg
  local f; f="$(mktemp)"; TMPFILES+=("$f"); printf 'TOPSECRET_CONTENT_XYZ' > "$f"
  run_hook "$(mk_input "$f" session_start Local)"
  local lf; lf="$(LOGFILE)"
  if [ -f "$lf" ] && ! grep -q 'TOPSECRET_CONTENT_XYZ' "$lf"; then
    ok "metadata-only" "file content not present in log (only its byte count)"
  else
    err "metadata-only" "file content leaked into log or not written"; errors=$((errors+1))
  fi
}

# --- Case 8: bytes == actual size ---------------------------------------------
case_bytes_size() {
  new_cfg
  local f; f="$(mktemp)"; TMPFILES+=("$f")
  # exactly 12 bytes
  printf '123456789012' > "$f"
  run_hook "$(mk_input "$f" session_start Project)"
  if jq -e '.bytes==12' "$(LOGFILE)" >/dev/null 2>&1; then ok "bytes-size" "bytes==12"; else err "bytes-size" "wrong: $(cat "$(LOGFILE)" 2>/dev/null)"; errors=$((errors+1)); fi
}

# --- Case 9: SKIP_INSTRUCTIONS_LOG=1 -> no write ------------------------------
case_skip() {
  new_cfg
  local f; f="$(mktemp)"; TMPFILES+=("$f"); printf 'x' > "$f"
  printf '%s' "$(mk_input "$f" session_start Project)" > "$INFILE"
  RC=0
  SKIP_INSTRUCTIONS_LOG=1 CLAUDE_CONFIG_DIR="$CFG" "$BASH_BIN" "$HOOK" < "$INFILE" >/dev/null 2>&1 || RC=$?
  if [ "$RC" = 0 ] && [ ! -e "$CFG/logs" ]; then ok "skip" "exit 0, no write"; else err "skip" "rc=$RC"; errors=$((errors+1)); fi
}

# --- Case 10: file_path set but file absent -> logged with bytes null ----------
case_absent_file() {
  new_cfg
  run_hook "$(mk_input "/no/such/file/here-$$" compact Managed)"
  local lf; lf="$(LOGFILE)"
  if [ -f "$lf" ] && jq -e '.bytes==null and .load_reason=="compact" and .memory_type=="Managed"' "$lf" >/dev/null 2>&1; then
    ok "absent-file" "logged with bytes null"
  else
    err "absent-file" "wrong: $(cat "$lf" 2>/dev/null)"; errors=$((errors+1))
  fi
}

info "instructions-loaded-log.sh (InstructionsLoaded hook) acceptance tests"
case_session_start
case_path_glob
case_missing_file_path
case_empty_stdin
case_jq_missing
case_perms
case_metadata_only
case_bytes_size
case_skip
case_absent_file

echo "=================================="
if [ "$errors" -gt 0 ]; then echo "FAIL — $errors error(s)"; exit 1; fi
echo "PASS — 0 errors"
exit 0
