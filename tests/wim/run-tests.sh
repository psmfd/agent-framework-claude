#!/usr/bin/env bash
#
# tests/wim/run-tests.sh — end-to-end test runner for scripts/wim/.
#
# Uses CLI shims under tests/wim/fixtures/bin to stand in for `az` and `gh`.
# Output follows rules/script-output-conventions.md (OK/SKIP/ERROR labels,
# exit 0 on PASS / 1 on FAIL).
#
# Usage:
#   tests/wim/run-tests.sh
#
# Exit codes:
#   0 — all tests pass
#   1 — one or more tests fail
#

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_DIR="$REPO_DIR/tests/wim"
WIM_DIR="$REPO_DIR/scripts/wim"
SHIM_DIR="$TESTS_DIR/fixtures/bin"

# Counters
ok_count=0
fail_count=0

ok()   { echo "OK    [$1] $2"; ok_count=$((ok_count + 1)); }
fail() { echo "ERROR [$1] $2" >&2; fail_count=$((fail_count + 1)); }
info() { echo "INFO  $*"; }

setup_state() {
  WIM_TEST_STATE_DIR=$(mktemp -d)
  export WIM_TEST_STATE_DIR
  export PATH="$SHIM_DIR:$PATH"
}

teardown_state() {
  rm -rf "$WIM_TEST_STATE_DIR"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$name" "got expected '$expected'"
  else
    fail "$name" "expected '$expected', got '$actual'"
  fi
}

assert_ne_empty() {
  local name="$1" actual="$2"
  if [[ -n "$actual" ]]; then
    ok "$name" "non-empty value '$actual'"
  else
    fail "$name" "expected non-empty"
  fi
}

assert_file_contains() {
  local name="$1" file="$2" pattern="$3"
  if grep -q -- "$pattern" "$file"; then
    ok "$name" "file matches pattern"
  else
    fail "$name" "file does not contain '$pattern'"
    [[ -f "$file" ]] && head -20 "$file" | sed 's/^/      /' >&2
  fi
}

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    ok "$name" "exit code $actual as expected"
  else
    fail "$name" "expected exit $expected, got $actual"
  fi
}

# -------------------------------------------------------------------
# Test cases
# -------------------------------------------------------------------

test_ado_epic_golden() {
  setup_state
  local id
  id=$(bash "$WIM_DIR/create-epic.sh" \
        --backend ado \
        --organization https://dev.azure.com/test \
        --project Test \
        --area "Test\\Area" \
        --iteration "Test\\Sprint" \
        --title "Auth overhaul" 2>/dev/null)
  assert_eq "ado-epic-id-format" "4000" "$id"
  assert_file_contains "ado-epic-create-call" "$WIM_TEST_STATE_DIR/az-calls.log" "work-item create"
  teardown_state
}

test_ado_epic_idempotent() {
  setup_state
  local first second
  first=$(bash "$WIM_DIR/create-epic.sh" \
            --backend ado --organization https://dev.azure.com/test --project Test \
            --area "Test\\Area" --iteration "Test\\Sprint" --title "Reuse me" 2>/dev/null)
  second=$(bash "$WIM_DIR/create-epic.sh" \
            --backend ado --organization https://dev.azure.com/test --project Test \
            --area "Test\\Area" --iteration "Test\\Sprint" --title "Reuse me" 2>/dev/null)
  assert_eq "ado-epic-idempotent-id-match" "$first" "$second"
  # Confirm only one create call was made (search returns before create on second run)
  local create_count
  create_count=$(grep -c "work-item create" "$WIM_TEST_STATE_DIR/az-calls.log" || true)
  assert_eq "ado-epic-idempotent-single-create" "1" "$create_count"
  teardown_state
}

test_ado_feature_links_parent() {
  setup_state
  local epic feat
  epic=$(bash "$WIM_DIR/create-epic.sh" --backend ado --organization https://dev.azure.com/test \
          --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title E 2>/dev/null)
  feat=$(bash "$WIM_DIR/create-feature.sh" --backend ado --organization https://dev.azure.com/test \
          --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title F \
          --parent-id "$epic" 2>/dev/null)
  assert_ne_empty "ado-feature-id" "$feat"
  assert_file_contains "ado-feature-parent-link" "$WIM_TEST_STATE_DIR/az-relations.log" "${feat}	${epic}	parent"
  teardown_state
}

test_ado_story_uses_process_effort_field() {
  setup_state
  local epic feat story
  epic=$(bash "$WIM_DIR/create-epic.sh" --backend ado --organization https://dev.azure.com/test \
          --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title E 2>/dev/null)
  feat=$(bash "$WIM_DIR/create-feature.sh" --backend ado --organization https://dev.azure.com/test \
          --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title F \
          --parent-id "$epic" 2>/dev/null)
  story=$(bash "$WIM_DIR/create-user-story.sh" --backend ado --organization https://dev.azure.com/test \
          --project Test --process scrum --area "Test\\Area" --iteration "Test\\Sprint" \
          --title S --parent-id "$feat" --story-points 5 2>/dev/null)
  assert_ne_empty "ado-story-id" "$story"
  assert_file_contains "ado-story-effort-field-scrum" "$WIM_TEST_STATE_DIR/az-calls.log" \
    "Microsoft.VSTS.Scheduling.Effort=5"
  teardown_state
}

test_ado_story_acceptance_criteria_html() {
  setup_state
  local epic feat
  epic=$(bash "$WIM_DIR/create-epic.sh" --backend ado --organization https://dev.azure.com/test \
          --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title E 2>/dev/null)
  feat=$(bash "$WIM_DIR/create-feature.sh" --backend ado --organization https://dev.azure.com/test \
          --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title F \
          --parent-id "$epic" 2>/dev/null)
  bash "$WIM_DIR/create-user-story.sh" --backend ado --organization https://dev.azure.com/test \
        --project Test --process agile --area "Test\\Area" --iteration "Test\\Sprint" \
        --title S --parent-id "$feat" \
        --acceptance-criteria $'- [ ] Item one\n- [ ] Item two' >/dev/null 2>&1
  assert_file_contains "ado-story-ac-html-li" "$WIM_TEST_STATE_DIR/az-calls.log" \
    "Microsoft.VSTS.Common.AcceptanceCriteria=<ul><li>Item one</li><li>Item two</li></ul>"
  teardown_state
}

test_gh_epic_golden() {
  setup_state
  local num
  num=$(bash "$WIM_DIR/create-epic.sh" --backend github --repo owner/repo --title "GH Epic" 2>/dev/null)
  assert_eq "gh-epic-number" "100" "$num"
  assert_file_contains "gh-epic-label-type-epic" "$WIM_TEST_STATE_DIR/gh-calls.log" "type/epic"
  teardown_state
}

test_gh_feature_links_subissue() {
  setup_state
  local epic feat
  epic=$(bash "$WIM_DIR/create-epic.sh" --backend github --repo owner/repo --title E 2>/dev/null)
  feat=$(bash "$WIM_DIR/create-feature.sh" --backend github --repo owner/repo --title F \
          --parent-id "$epic" 2>/dev/null)
  assert_ne_empty "gh-feature-number" "$feat"
  assert_file_contains "gh-feature-subissue-link" "$WIM_TEST_STATE_DIR/gh-subissues.log" "${epic}	${feat}"
  teardown_state
}

test_apply_manifest_ado_full_tree() {
  setup_state
  local manifest="$WIM_TEST_STATE_DIR/manifest.json"
  cat > "$manifest" <<'JSON'
{
  "backend": "ado",
  "ado": {
    "organization": "https://dev.azure.com/test",
    "project": "Test",
    "process": "agile",
    "area": "Test\\Area",
    "iteration": "Test\\Sprint"
  },
  "epic": {
    "title": "E1",
    "features": [
      {
        "title": "F1",
        "stories": [
          { "title": "S1", "ado": { "story_points": 3 } },
          { "title": "S2", "acceptance_criteria": "- [ ] AC1" }
        ]
      },
      {
        "title": "F2",
        "stories": [
          { "title": "S3" }
        ]
      }
    ]
  }
}
JSON
  local out rc
  set +e
  out=$(bash "$WIM_DIR/apply-manifest.sh" "$manifest" 2>&1)
  rc=$?
  set -e
  assert_exit "apply-ado-rc" 0 "$rc"
  # Six items total: 1 Epic + 2 Features + 3 Stories
  local create_count
  create_count=$(grep -c "work-item create" "$WIM_TEST_STATE_DIR/az-calls.log" || true)
  assert_eq "apply-ado-create-count" "6" "$create_count"
  # Two parent links Feature->Epic + three parent links Story->Feature = 5
  local link_count
  link_count=$(wc -l < "$WIM_TEST_STATE_DIR/az-relations.log" | tr -d '[:space:]')
  assert_eq "apply-ado-relation-count" "5" "$link_count"
  assert_file_contains "apply-ado-summary-pass" <(echo "$out") "PASS"
  teardown_state
}

test_apply_manifest_gh_full_tree() {
  setup_state
  local manifest="$WIM_TEST_STATE_DIR/manifest.json"
  cat > "$manifest" <<'JSON'
{
  "backend": "github",
  "github": { "repo": "owner/repo", "default_labels": ["enhancement"] },
  "epic": {
    "title": "GH-E",
    "features": [
      {
        "title": "GH-F",
        "stories": [
          { "title": "GH-S1", "acceptance_criteria": "- [ ] do thing" }
        ]
      }
    ]
  }
}
JSON
  local out rc
  set +e
  out=$(bash "$WIM_DIR/apply-manifest.sh" "$manifest" 2>&1)
  rc=$?
  set -e
  assert_exit "apply-gh-rc" 0 "$rc"
  local create_count
  create_count=$(grep -c "issue create" "$WIM_TEST_STATE_DIR/gh-calls.log" || true)
  assert_eq "apply-gh-create-count" "3" "$create_count"
  # Two sub-issue links: Feature->Epic, Story->Feature
  local link_count
  link_count=$(wc -l < "$WIM_TEST_STATE_DIR/gh-subissues.log" | tr -d '[:space:]')
  assert_eq "apply-gh-subissue-count" "2" "$link_count"
  teardown_state
}

test_apply_manifest_gh_identity_preflight() {
  setup_state
  local manifest="$WIM_TEST_STATE_DIR/manifest.json"
  cat > "$manifest" <<'JSON'
{
  "backend": "github",
  "github": { "repo": "owner/repo", "default_labels": ["enhancement"] },
  "epic": { "title": "GH-E", "features": [] }
}
JSON
  local out rc
  set +e
  out=$(GH_SHIM_DENY_REPO="owner/repo" GH_TOKEN="" GITHUB_TOKEN="" \
    bash "$WIM_DIR/apply-manifest.sh" "$manifest" 2>&1)
  rc=$?
  set -e
  # Fail fast with a non-zero exit when the active account cannot resolve the repo
  assert_exit "apply-gh-identity-rc" 1 "$rc"
  # No issue created before the identity error — the guard runs before any writes
  local create_count
  create_count=$(grep -c "issue create" "$WIM_TEST_STATE_DIR/gh-calls.log" || true)
  assert_eq "apply-gh-identity-no-writes" "0" "$create_count"
  # Error is labelled with the gh-identity guard
  if printf '%s' "$out" | grep -q "gh-identity"; then
    ok "apply-gh-identity-msg" "preflight error surfaced"
  else
    fail "apply-gh-identity-msg" "expected gh-identity error, got: $out"
  fi
  teardown_state
}

test_usage_missing_backend() {
  setup_state
  local rc
  set +e
  bash "$WIM_DIR/create-epic.sh" --title "no backend" >/dev/null 2>&1
  rc=$?
  set -e
  assert_exit "usage-missing-backend" 2 "$rc"
  teardown_state
}

test_manifest_missing_backend() {
  setup_state
  local manifest="$WIM_TEST_STATE_DIR/bad.json"
  echo '{ "epic": { "title": "no backend" } }' > "$manifest"
  local rc
  set +e
  bash "$WIM_DIR/apply-manifest.sh" "$manifest" >/dev/null 2>&1
  rc=$?
  set -e
  assert_exit "manifest-missing-backend" 2 "$rc"
  teardown_state
}

# --- #177: adversarial-title sanitization (idempotency must survive) ---

test_gh_search_adversarial_title() {
  setup_state
  local t='Auth overhaul OR label:security'
  local first second
  first=$(bash "$WIM_DIR/create-epic.sh" --backend github --repo owner/repo --title "$t" 2>/dev/null)
  second=$(bash "$WIM_DIR/create-epic.sh" --backend github --repo owner/repo --title "$t" 2>/dev/null)
  assert_ne_empty "gh-adversarial-created" "$first"
  assert_eq "gh-adversarial-idempotent" "$first" "$second"
  local create_count
  create_count=$(grep -c "issue create" "$WIM_TEST_STATE_DIR/gh-calls.log" || true)
  assert_eq "gh-adversarial-single-create" "1" "$create_count"
  teardown_state
}

test_ado_search_single_quote_title() {
  setup_state
  local t="It's a feature"
  local first second
  first=$(bash "$WIM_DIR/create-epic.sh" --backend ado --organization https://dev.azure.com/test \
            --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title "$t" 2>/dev/null)
  second=$(bash "$WIM_DIR/create-epic.sh" --backend ado --organization https://dev.azure.com/test \
            --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title "$t" 2>/dev/null)
  assert_ne_empty "ado-squote-created" "$first"
  assert_eq "ado-squote-idempotent" "$first" "$second"
  local create_count
  create_count=$(grep -c "work-item create" "$WIM_TEST_STATE_DIR/az-calls.log" || true)
  assert_eq "ado-squote-single-create" "1" "$create_count"
  teardown_state
}

test_ado_search_structural_chars_title() {
  setup_state
  local t="Feature [v2] AND OR NOT done"
  local first second
  first=$(bash "$WIM_DIR/create-epic.sh" --backend ado --organization https://dev.azure.com/test \
            --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title "$t" 2>/dev/null)
  second=$(bash "$WIM_DIR/create-epic.sh" --backend ado --organization https://dev.azure.com/test \
            --project Test --area "Test\\Area" --iteration "Test\\Sprint" --title "$t" 2>/dev/null)
  assert_eq "ado-structural-idempotent" "$first" "$second"
  teardown_state
}

# --- #178: standalone (non-epic) issues ---

test_gh_standalone_issue_no_type_injection() {
  setup_state
  local num
  num=$(bash "$WIM_DIR/create-issue.sh" --backend github --repo owner/repo \
          --title "Login fails on Safari" --labels "bug,p:now" 2>/dev/null)
  assert_ne_empty "gh-standalone-number" "$num"
  assert_file_contains "gh-standalone-label-bug" "$WIM_TEST_STATE_DIR/gh-calls.log" "bug"
  if grep -qE "type/(epic|feature|story)" "$WIM_TEST_STATE_DIR/gh-calls.log"; then
    fail "gh-standalone-no-type-label" "unexpected type/* label injected"
  else
    ok "gh-standalone-no-type-label" "no type/* label injected"
  fi
  teardown_state
}

test_ado_standalone_issue_type() {
  setup_state
  local id
  id=$(bash "$WIM_DIR/create-issue.sh" --backend ado --organization https://dev.azure.com/test \
        --project Test --area "Test\\Area" --iteration "Test\\Sprint" \
        --title "DB timeout" --type "Bug" --severity "2 - High" 2>/dev/null)
  assert_ne_empty "ado-standalone-id" "$id"
  assert_file_contains "ado-standalone-type-bug" "$WIM_TEST_STATE_DIR/az-calls.log" "work-item create --type Bug"
  assert_file_contains "ado-standalone-severity" "$WIM_TEST_STATE_DIR/az-calls.log" "Microsoft.VSTS.Common.Severity=2 - High"
  if [[ -s "$WIM_TEST_STATE_DIR/az-relations.log" ]]; then
    fail "ado-standalone-no-parent" "unexpected parent relation for standalone issue"
  else
    ok "ado-standalone-no-parent" "no parent relation created"
  fi
  teardown_state
}

test_apply_manifest_gh_with_standalone_issues() {
  setup_state
  local manifest="$WIM_TEST_STATE_DIR/manifest.json"
  cat > "$manifest" <<'JSON'
{
  "backend": "github",
  "github": { "repo": "owner/repo", "default_labels": ["enhancement"] },
  "epic": { "title": "EP", "features": [ { "title": "FT", "stories": [ { "title": "ST" } ] } ] },
  "issues": [ { "title": "Standalone bug", "labels": ["bug"] } ]
}
JSON
  local out rc
  set +e
  out=$(bash "$WIM_DIR/apply-manifest.sh" "$manifest" 2>&1)
  rc=$?
  set -e
  assert_exit "apply-gh-standalone-rc" 0 "$rc"
  # 1 epic + 1 feature + 1 story + 1 standalone issue
  local create_count
  create_count=$(grep -c "issue create" "$WIM_TEST_STATE_DIR/gh-calls.log" || true)
  assert_eq "apply-gh-standalone-create-count" "4" "$create_count"
  teardown_state
}

test_apply_manifest_standalone_only() {
  setup_state
  local manifest="$WIM_TEST_STATE_DIR/manifest.json"
  cat > "$manifest" <<'JSON'
{
  "backend": "github",
  "github": { "repo": "owner/repo" },
  "issues": [ { "title": "Bug one", "labels": ["bug"] }, { "title": "Task two" } ]
}
JSON
  local out rc
  set +e
  out=$(bash "$WIM_DIR/apply-manifest.sh" "$manifest" 2>&1)
  rc=$?
  set -e
  assert_exit "apply-standalone-only-rc" 0 "$rc"
  local create_count
  create_count=$(grep -c "issue create" "$WIM_TEST_STATE_DIR/gh-calls.log" || true)
  assert_eq "apply-standalone-only-create-count" "2" "$create_count"
  assert_file_contains "apply-standalone-only-pass" <(echo "$out") "PASS"
  teardown_state
}

test_manifest_requires_epic_or_issues() {
  setup_state
  local manifest="$WIM_TEST_STATE_DIR/empty.json"
  echo '{ "backend": "github", "github": { "repo": "owner/repo" } }' > "$manifest"
  local rc
  set +e
  bash "$WIM_DIR/apply-manifest.sh" "$manifest" >/dev/null 2>&1
  rc=$?
  set -e
  assert_exit "manifest-requires-epic-or-issues" 2 "$rc"
  teardown_state
}

# -------------------------------------------------------------------
# Run
# -------------------------------------------------------------------

info "tests/wim run starting (shims at $SHIM_DIR)"

test_ado_epic_golden
test_ado_epic_idempotent
test_ado_feature_links_parent
test_ado_story_uses_process_effort_field
test_ado_story_acceptance_criteria_html
test_gh_epic_golden
test_gh_feature_links_subissue
test_apply_manifest_ado_full_tree
test_apply_manifest_gh_full_tree
test_apply_manifest_gh_identity_preflight
test_usage_missing_backend
test_manifest_missing_backend
test_gh_search_adversarial_title
test_ado_search_single_quote_title
test_ado_search_structural_chars_title
test_gh_standalone_issue_no_type_injection
test_ado_standalone_issue_type
test_apply_manifest_gh_with_standalone_issues
test_apply_manifest_standalone_only
test_manifest_requires_epic_or_issues

echo "=================================="
if (( fail_count > 0 )); then
  echo "FAIL — $fail_count failure(s), $ok_count ok"
  exit 1
fi
echo "PASS — $ok_count assertion(s)"
exit 0
