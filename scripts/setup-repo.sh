#!/usr/bin/env bash
#
# Agent Framework — Repo Setup Script
#
# Applies standard branch protection and merge settings to a GitHub repo.
# Uses the agent-framework repo as the reference configuration.
#
# Usage:
#   ./scripts/setup-repo.sh owner/repo [branch]
#
# Arguments:
#   owner/repo  — GitHub repository in owner/repo format (required)
#   branch      — Branch to protect (default: main)
#
# Requires:
#   gh CLI authenticated with admin access to the target repo
#
# Exit codes:
#   0 — all settings applied successfully
#   1 — one or more errors occurred
#

set -euo pipefail

# --- Output helpers (rules/script-output-conventions.md, ADR-061) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

# --- Argument validation ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 owner/repo [branch]"
  exit 1
fi

REPO="$1"
BRANCH="${2:-main}"

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  err "args" "Repo must be in owner/repo format, got: $REPO"
  exit 1
fi

# --- Preflight checks ---
echo "Repo Setup — $REPO ($BRANCH)"
echo "=================================="
echo ""

# gh CLI available
if ! command -v gh >/dev/null 2>&1; then
  err "preflight" "gh CLI not found — install from https://cli.github.com"
  exit 1
fi

# gh authenticated
if ! gh auth status >/dev/null 2>&1; then
  err "preflight" "gh CLI not authenticated — run 'gh auth login'"
  exit 1
fi
ok "preflight" "gh CLI authenticated"

# Repo exists and accessible
if ! gh api "repos/${REPO}" --silent 2>/dev/null; then
  err "preflight" "Repository ${REPO} not found or not accessible"
  exit 1
fi
ok "preflight" "Repository ${REPO} exists"

# Branch exists
if ! gh api "repos/${REPO}/branches/${BRANCH}" --silent 2>/dev/null; then
  err "preflight" "Branch '${BRANCH}' does not exist in ${REPO} — create it first"
  exit 1
fi
ok "preflight" "Branch ${BRANCH} exists"
echo ""

# --- Apply repo-level merge settings ---
echo "Merge settings:"
if gh api \
  --method PATCH \
  "repos/${REPO}" \
  --silent \
  --input - <<'EOF'
{
  "allow_squash_merge": true,
  "allow_merge_commit": true,
  "allow_rebase_merge": false,
  "delete_branch_on_merge": true,
  "squash_merge_commit_title": "COMMIT_OR_PR_TITLE",
  "squash_merge_commit_message": "COMMIT_MESSAGES"
}
EOF
then
  ok "merge" "Squash-only, delete-on-merge, commit title/message format"
else
  err "merge" "Failed to apply merge settings"
fi
echo ""

# --- Apply branch protection ---
echo "Branch protection (${BRANCH}):"
if gh api \
  --method PUT \
  "repos/${REPO}/branches/${BRANCH}/protection" \
  --silent \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
then
  ok "protection" "PR required, 0 approvals, dismiss stale, no force-push, no branch delete"
else
  err "protection" "Failed to apply branch protection"
fi
echo ""

# --- Verify settings ---
echo "Verification:"

merge_settings=$(gh api "repos/${REPO}" --jq '{
  squash: .allow_squash_merge,
  merge_commit: .allow_merge_commit,
  rebase: .allow_rebase_merge,
  delete_on_merge: .delete_branch_on_merge,
  squash_title: .squash_merge_commit_title,
  squash_message: .squash_merge_commit_message
}' 2>/dev/null || echo "FAILED")

if [[ "$merge_settings" != "FAILED" ]]; then
  ok "verify" "Merge settings: $merge_settings"
else
  err "verify" "Could not read merge settings"
fi

protection_settings=$(gh api "repos/${REPO}/branches/${BRANCH}/protection" --jq '{
  pr_reviews: (.required_pull_request_reviews != null),
  dismiss_stale: .required_pull_request_reviews.dismiss_stale_reviews,
  enforce_admins: .enforce_admins.enabled,
  force_push: .allow_force_pushes.enabled,
  deletions: .allow_deletions.enabled
}' 2>/dev/null || echo "FAILED")

if [[ "$protection_settings" != "FAILED" ]]; then
  ok "verify" "Branch protection: $protection_settings"
else
  err "verify" "Could not read branch protection"
fi
echo ""

# --- Summary ---
info "Settings applied to ${REPO} (${BRANCH})"
print_summary
exit $?
