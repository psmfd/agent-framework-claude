#!/usr/bin/env bash
#
# instructions-loaded-log.sh — Global InstructionsLoaded observability logger (ADR-092)
#
# Appends one compact JSON line per instruction-file load event to a local log,
# to turn the rule-loading cost model (#27: ~23–31k always-loaded tokens, ×N
# under fan-out) from bytes/4 estimates into measured data, and to empirically
# settle whether `paths:`-scoped rules re-trigger inside sub-agent file reads.
#
# Event: `InstructionsLoaded` fires per CLAUDE.md / rules file load (added Claude
# Code v2.1.69). It is OBSERVABILITY-ONLY — its exit code is ignored, it cannot
# block or modify loading, and its stdout is discarded from context (only
# UserPromptSubmit/UserPromptExpansion/SessionStart inject stdout). A local,
# metadata-only, stdout-discarded logger therefore cannot inject anything into
# the harness system context and is compatible with rules/no-mcp-servers.md
# (ADR-092). This is the framework's first observability hook and first hook
# that writes persistent local state.
#
# Logged (METADATA ONLY — never file or conversation content):
#   ts           ISO-8601 UTC timestamp
#   session_id   from the payload
#   load_reason  session_start | nested_traversal | path_glob_match | include | compact
#   memory_type  User | Project | Local | Managed (capitalized, per the wire schema)
#   bytes        size of the loaded file via `wc -c` (a count, not content); null if unreadable
#   file_path    absolute path of the loaded file
#
# Log location: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/instructions-loaded.jsonl
#   dir  chmod 700, file chmod 600 — the log records which local files loaded and
#   when; it is kept owner-only.
#
# Known upstream gaps (reported, unconfirmed/unfixed as of CLI 2.1.199 — treat as
# analysis caveats, not this hook's behavior):
#   - does NOT fire on /clear (anthropics/claude-code#31017) — use fresh sessions
#     for clean data.
#   - duplicates ~3× per file on /compact (anthropics/claude-code#52176) — dedupe
#     at analysis time by (session_id, file_path, load_reason).
#
# Fail posture: fail-OPEN and always exit 0 — an observability hook must never
# disrupt a session. Missing jq, empty stdin, an absent file_path, or any write
# error simply skips logging. A payload with no file_path writes nothing (and
# creates no log dir/file), so a `{}` smoke payload is a clean no-op.
#
# Override: SKIP_INSTRUCTIONS_LOG=1 (env) — silent (announcing on every file load
# would spam). Exit code: always 0. Targets bash 3.2+.

set -uo pipefail

[ "${SKIP_INSTRUCTIONS_LOG:-}" = "1" ] && exit 0

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0   # fail-open (observability — nothing to protect)

file_path="$(printf '%s' "$INPUT" | jq -r '.file_path // empty' 2>/dev/null || true)"
[ -z "$file_path" ] && exit 0             # nothing to log; no dir/file created

session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || true)"
load_reason="$(printf '%s' "$INPUT" | jq -r '.load_reason // "unknown"' 2>/dev/null || true)"
memory_type="$(printf '%s' "$INPUT" | jq -r '.memory_type // "unknown"' 2>/dev/null || true)"

# Byte size — a COUNT, never content. Only read if the file is readable.
bytes="null"
if [ -f "$file_path" ] && [ -r "$file_path" ]; then   # regular file only — a FIFO/device could block wc
  b="$(wc -c < "$file_path" 2>/dev/null | tr -d '[:space:]')"
  case "$b" in ''|*[!0-9]*) bytes="null" ;; *) bytes="$b" ;; esac
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')"

LOG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs"
LOG_FILE="$LOG_DIR/instructions-loaded.jsonl"

if [ ! -d "$LOG_DIR" ]; then
  # umask 077 so the dir is created 0700 with no group/world-traversable window
  # (the chmod is belt-and-suspenders); mirrors the log-file creation below.
  ( umask 077; mkdir -p "$LOG_DIR" ) 2>/dev/null || exit 0
  chmod 700 "$LOG_DIR" 2>/dev/null || true
fi
if [ ! -f "$LOG_FILE" ]; then
  ( umask 077; : > "$LOG_FILE" ) 2>/dev/null || exit 0
  chmod 600 "$LOG_FILE" 2>/dev/null || true
fi

# One compact JSON line — jq -n escapes every field; bytes is a number or null.
line="$(jq -nc \
  --arg ts "$ts" --arg sid "$session_id" --arg lr "$load_reason" \
  --arg mt "$memory_type" --argjson bytes "$bytes" --arg fp "$file_path" \
  '{ts:$ts, session_id:$sid, load_reason:$lr, memory_type:$mt, bytes:$bytes, file_path:$fp}' \
  2>/dev/null || true)"
[ -z "$line" ] && exit 0

printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || exit 0
exit 0
