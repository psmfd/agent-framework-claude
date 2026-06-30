#!/usr/bin/env bash
# stop-preflight-check.sh — Stop hook for Claude Code
#
# Guards against empty assistant messages and stop_hook_active recursion,
# then outputs a reminder for the assistant to self-check its work before
# the session terminates.
#
# Platforms: Claude Code only (Stop hooks are not available in Copilot)
# Targets: bash 3.2+ (macOS compatible), jq 1.5+
# Contract: ALWAYS exits 0. Failures must not block session termination.

set -uo pipefail

# Trap any unexpected errors — always exit 0 with empty JSON
trap 'echo "{}"; exit 0' ERR

# --- Read stdin ---
INPUT="$(cat)"

# --- Extract fields (resilient to missing fields) ---
if command -v jq >/dev/null 2>&1; then
  STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // .stopHookActive // "false"')"
  LAST_MESSAGE="$(echo "$INPUT" | jq -r '.last_assistant_message // .lastAssistantMessage // ""')"
else
  # Fallback: extract fields with python3 (handles both snake_case and camelCase)
  STOP_HOOK_ACTIVE="$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(str(data.get('stop_hook_active', data.get('stopHookActive', False))).lower())
except Exception:
    print('false')
" 2>/dev/null)" || STOP_HOOK_ACTIVE="false"

  LAST_MESSAGE="$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('last_assistant_message', data.get('lastAssistantMessage', '')))
except Exception:
    print('')
" 2>/dev/null)" || LAST_MESSAGE=""
fi

# --- Guard: prevent recursion from stop hook's own response ---
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  echo '{}'
  exit 0
fi

# --- Guard: skip when no assistant message exists ---
if [ -z "$LAST_MESSAGE" ]; then
  echo '{}'
  exit 0
fi

# --- Output reminder ---
REMINDER="If you modified files during this session, confirm the post-implementation review pass was completed: linter clean on changed files, tests passing where applicable, and any documentation sync pairs updated. If a step was skipped, note it before stopping."

if command -v jq >/dev/null 2>&1; then
  jq -n -c --arg msg "$REMINDER" '{"description": $msg}'
else
  python3 -c "
import json, sys
print(json.dumps({'description': sys.argv[1]}))
" "$REMINDER"
fi

exit 0
