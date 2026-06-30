#!/usr/bin/env bash
# worktree-remove.sh — WorktreeRemove hook for Claude Code
#
# Cleans up custom worktree directories under .wt_tmp/. Claude Code handles
# the actual git worktree removal — this hook handles residual directory
# cleanup and orphan pruning.
#
# Platforms: Claude Code only (WorktreeRemove is not available in Copilot)
# Targets: bash 3.2+ (macOS compatible), jq 1.5+, git 2.23+
# Contract:
#   - Fire-and-forget: exit code is ignored by Claude Code
#   - No stdout output required
#   - Only fires on clean session exit (not on crash/kill)
#
# Exit codes:
#   0 — always (failures must not block session termination)

# The ERR trap (below) exits 0 on any command failure.
# -e is omitted for clarity — the trap is the sole error handler.
set -uo pipefail

# Trap any unexpected errors — always exit 0
trap 'exit 0' ERR

# --- Dependency check ---
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- Read stdin ---
INPUT="$(cat)"

# --- Extract fields ---
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')" || true
NAME="$(echo "$INPUT" | jq -r '.name // empty')" || true
if [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  exit 0
fi

# --- Remove residual worktree directory ---
if [ -n "$CWD" ]; then
  WORKTREE_DIR="${CWD}/.wt_tmp/${NAME}"
  if [ -d "$WORKTREE_DIR" ]; then
    rm -rf "$WORKTREE_DIR" 2>/dev/null || true
  fi

  # Remove .wt_tmp/ itself if empty
  if [ -d "${CWD}/.wt_tmp" ]; then
    rmdir "${CWD}/.wt_tmp" 2>/dev/null || true
  fi
fi

# --- Prune stale worktree references ---
if [ -n "$CWD" ]; then
  git -C "$CWD" worktree prune 2>/dev/null || true
fi

exit 0
