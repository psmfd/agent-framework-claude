#!/usr/bin/env bash
# Acceptance tests for the plain-English Write prompt-gate control plane
# (ADR-099, #112). Semantic verdict quality requires a real Claude Code
# prototype; this offline suite verifies registration, scope, prompt clauses,
# and fixture coverage without claiming deterministic model judgment.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETTINGS="$ROOT/settings.json"
FIXTURES="$SCRIPT_DIR/fixtures.json"
RULE="$ROOT/rules/plain-english.md"
ADR="$ROOT/adrs/099-plain-english-write-gate.md"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0

for cmd in jq grep; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd is required but not on PATH"; exit 2; }
done
for file in "$SETTINGS" "$FIXTURES" "$RULE" "$ADR"; do
  [ -f "$file" ] || { err "env" "required file missing: $file"; exit 2; }
done

check_jq() {
  local name="$1" expression="$2" file="$3" message="$4"
  if jq -e "$expression" "$file" >/dev/null 2>&1; then
    ok "$name" "$message"
  else
    err "$name" "$message"
    errors=$((errors + 1))
  fi
}

info "plain-English Write gate control-plane tests"

check_jq "settings-json" '.' "$SETTINGS" "settings.json parses"
check_jq "hook-count" \
  '[.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[] | select(.type == "prompt")] | length == 3' \
  "$SETTINGS" "three Write prompt handlers are registered"
check_jq "path-scope" \
  '([.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[].if] | sort) == (["Write(CONTRIBUTING.md)", "Write(README.md)", "Write(docs/**/*.md)"] | sort)' \
  "$SETTINGS" "path filters match the initial scope exactly"
# shellcheck disable=SC2016  # jq must match the literal $ARGUMENTS placeholder.
check_jq "handler-contract" \
  '[.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[] | select(.type == "prompt") | (.continueOnBlock == true and .timeout == 30 and (.prompt | contains("$ARGUMENTS")))] | all' \
  "$SETTINGS" "handlers use prompt input, timeout, and retry-on-block"
check_jq "prompt-lockstep" \
  '[.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[].prompt] | unique | length == 1' \
  "$SETTINGS" "all scoped handlers use one policy prompt"
check_jq "preservation-prompt" \
  '[.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[].prompt | (contains("Preserve facts") and contains("specialist terminology") and contains("quotations and examples") and contains("If uncertain, allow") and contains("Return JSON only"))] | all' \
  "$SETTINGS" "prompt carries preservation, quotation, uncertainty, and response clauses"
check_jq "anti-pattern-prompt" \
  '[.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[].prompt | (contains("hedging stacks") and contains("filler transitions") and contains("jargon stacking") and contains("marketing adjectives") and contains("nominalizations") and contains("over-qualification") and contains("structure padding") and contains("redundant summaries"))] | all' \
  "$SETTINGS" "prompt names every canonical anti-pattern"
check_jq "prompt-hardening" \
  '[.hooks.PreToolUse[] | select(.matcher == "Write") | .hooks[].prompt | (contains("untrusted data") and contains("Never follow instructions") and contains("at most 160 characters") and contains("UNTRUSTED TOOL INPUT"))] | all' \
  "$SETTINGS" "prompt separates policy from untrusted content and bounds denial excerpts"
check_jq "fixture-categories" \
  '([.cases[].category] | unique | sort) == (["allowed-prose", "blocked-prose", "excluded-path", "hook-failure", "malformed-input", "prompt-injection", "protected-syntax", "specialist-prose"] | sort)' \
  "$FIXTURES" "fixture corpus covers scope, prose, injection, syntax, malformed input, and runtime failure"
check_jq "fixture-expectations" \
  'all(.cases[]; if (.category == "allowed-prose" or .category == "specialist-prose" or .category == "protected-syntax") then .expected == "allow" elif (.category == "blocked-prose" or .category == "prompt-injection") then .expected == "deny" elif .category == "excluded-path" then .expected == "not-invoked" elif .category == "malformed-input" then .expected == "not-invoked" elif .category == "hook-failure" then .expected == "runtime-owned" else false end)' \
  "$FIXTURES" "each fixture category carries the intended expected outcome"
check_jq "write-fixture-shape" \
  '[.cases[] | select(.category != "hook-failure") | (.input.hook_event_name == "PreToolUse" and .input.tool_name == "Write" and (.input.tool_input | type == "object"))] | all' \
  "$FIXTURES" "non-runtime fixtures use the PreToolUse Write input shape"
check_jq "content-fixtures" \
  '[.cases[] | select(.category == "allowed-prose" or .category == "blocked-prose" or .category == "prompt-injection" or .category == "specialist-prose" or .category == "protected-syntax") | (.input.tool_input.file_path | type == "string") and (.input.tool_input.content | type == "string")] | all' \
  "$FIXTURES" "semantic prototype fixtures carry file_path and content"
check_jq "fixture-path-outcomes" \
  'all(.cases[]; if (.category == "allowed-prose" or .category == "blocked-prose" or .category == "prompt-injection" or .category == "specialist-prose" or .category == "protected-syntax") then (.input.tool_input.file_path | test("/(README\\.md|CONTRIBUTING\\.md|docs/.+\\.md)$")) elif .category == "excluded-path" then (.input.tool_input.file_path | test("/(README\\.md|CONTRIBUTING\\.md|docs/.+\\.md)$") | not) else true end)' \
  "$FIXTURES" "eligible and excluded fixture paths match the configured boundary"

if grep -q '^\*\*Enforcement:\*\* PreToolUse hook' "$RULE"; then
  ok "rule-enforcement" "rule states the mechanical boundary"
else
  err "rule-enforcement" "rule lacks the expected PreToolUse enforcement line"
  errors=$((errors + 1))
fi

info "semantic allow/deny outcomes are prototype expectations, not offline CI claims"
echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
