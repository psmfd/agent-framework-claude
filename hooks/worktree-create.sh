#!/usr/bin/env bash
# worktree-create.sh — WorktreeCreate hook for Claude Code
#
# Redirects worktree creation from .claude/worktrees/ to .wt_tmp/ to avoid
# path permission conflicts. The .claude/ directory is a restricted write path,
# and worktrees placed inside it cause Edit/Write tool denials for subagents.
#
# Platforms: Claude Code only (WorktreeCreate is not available in Copilot)
# Targets: bash 3.2+ (macOS compatible), jq 1.5+, git 2.23+
# Contract:
#   - stdout must contain ONLY the absolute worktree path (nothing else)
#   - exit 0 on success, non-zero on failure
#   - any stdout contamination causes Claude Code to hang silently (bug #27467)
#
# Exit codes:
#   0 — worktree created, path returned on stdout
#   1+ — git worktree add or switch failed (set -e propagates the actual exit code)
#   2 — missing dependencies or invalid input (null fields, unsafe name)

set -euo pipefail

# --- Dependency check ---
for cmd in jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "worktree-create: missing required command: $cmd" >&2
    exit 2
  fi
done

# --- Read stdin ---
INPUT="$(cat)"

# --- Extract fields ---
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"
NAME="$(echo "$INPUT" | jq -r '.name // empty')"

if [ -z "$CWD" ] || [ -z "$NAME" ]; then
  echo "worktree-create: required fields cwd and name missing or null" >&2
  exit 2
fi
if [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "worktree-create: unsafe name: $NAME" >&2
  exit 2
fi
REF="$(echo "$INPUT" | jq -r '.ref // empty')"
BRANCH="$(echo "$INPUT" | jq -r '.branch // empty')"

# --- Compute custom worktree path ---
WORKTREE_PATH="${CWD}/.wt_tmp/${NAME}"

# --- Prune orphaned worktrees from prior crashed sessions ---
# WorktreeRemove does not fire on abnormal exit, so orphans accumulate.
git -C "$CWD" worktree prune 2>/dev/null || true
if [ -d "$WORKTREE_PATH" ]; then
  rm -rf "$WORKTREE_PATH" 2>/dev/null || true
fi

# --- Create worktree ---
# ALL git output must go to /dev/null — stdout contamination causes a silent hang.
mkdir -p "${CWD}/.wt_tmp" 2>/dev/null || true

if [ -n "$BRANCH" ]; then
  # Two-step add+switch: git worktree add -b fails if the branch already exists.
  # The fallback to switch handles re-creation after a crash where the branch persists.
  git -C "$CWD" worktree add "$WORKTREE_PATH" -- "${REF:-HEAD}" >/dev/null 2>&1
  if ! git -C "$WORKTREE_PATH" switch -c "$BRANCH" >/dev/null 2>&1; then
    if ! git -C "$WORKTREE_PATH" switch "$BRANCH" >/dev/null 2>&1; then
      echo "worktree-create: warning: could not switch to branch '$BRANCH'" >&2
    fi
  fi
elif [ -n "$REF" ]; then
  git -C "$CWD" worktree add "$WORKTREE_PATH" -- "$REF" >/dev/null 2>&1
else
  git -C "$CWD" worktree add "$WORKTREE_PATH" >/dev/null 2>&1
fi

# --- Handle .worktreeinclude ---
# When a WorktreeCreate hook is registered, Claude Code's automatic
# .worktreeinclude processing is disabled. The hook must copy files manually.
#
# Containment (ADR-070): entries that are symlinks, or whose parent directory
# physically resolves outside the repo root, are skipped with a stderr warning.
# cp -R copies any nested symlink as a link (never follows it), so at most an
# inert pointer — no external content — can land in the worktree. Accepted
# residuals: that inert pointer, and a narrow TOCTOU race between the checks
# and the copy (requires concurrent write access to the repo).
if [ -f "${CWD}/.worktreeinclude" ]; then
  REPO_PHYS="$(cd "$CWD" && pwd -P)"
  while IFS= read -r file; do
    file="${file%$'\r'}"
    [[ "$file" =~ ^# ]] && continue
    [ -z "$file" ] && continue
    file="${file#./}"
    file="${file%/}"
    [ -z "$file" ] && continue
    [ "$file" = "." ] && continue
    case "$file" in
      ..|../*|*/../*|*/..) continue ;;
    esac
    [[ "$file" = /* ]] && continue
    if [ -L "${CWD}/${file}" ]; then
      printf 'worktree-create: skipping symlink entry: %s\n' "$file" >&2
      continue
    fi
    [ -e "${CWD}/${file}" ] || continue
    # Resolve the parent dir physically — catches symlinked intermediate
    # components. The if-! form keeps a failed cd from aborting under set -e.
    if ! src_dir="$(cd "$(dirname "${CWD}/${file}")" 2>/dev/null && pwd -P)"; then
      printf 'worktree-create: skipping %s — could not resolve parent directory\n' "$file" >&2
      continue
    fi
    # Containment: src_dir must be REPO_PHYS or a child of it. Prefix-strip
    # with an explicit /-boundary test — a case glob would misbehave when the
    # repo path contains pattern metacharacters.
    rel="${src_dir#"$REPO_PHYS"}"
    if [ "$rel" = "$src_dir" ] || { [ -n "$rel" ] && [ "${rel#/}" = "$rel" ]; }; then
      printf 'worktree-create: skipping %s — resolves outside repo root\n' "$file" >&2
      continue
    fi
    mkdir -p "$(dirname "${WORKTREE_PATH}/${file}")" 2>/dev/null || true
    cp -R "${CWD}/${file}" "${WORKTREE_PATH}/${file}"
  done < "${CWD}/.worktreeinclude"
fi

# --- Return path ---
# This MUST be the only stdout output. Nothing else.
echo "$WORKTREE_PATH"
