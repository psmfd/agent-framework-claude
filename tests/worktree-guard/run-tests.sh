#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for hooks/worktree-create.sh .worktreeinclude
# containment (ADR-070, supersedes the .worktreeinclude clause of ADR-038)
#
# Proves the containment checks reject the symlink copy-out bypasses that the
# prior traversal-only filter missed:
#   1. positive control: a regular file entry is copied
#   2. an entry that is itself a symlink to an outside file is skipped
#   3. an entry under a symlinked directory (intermediate component) is skipped
#   4. a nested symlink inside a copied directory is copied as a link, not content
#   5. a `../` traversal entry is still skipped (pre-ADR-070 filter intact)
#   6. a file in a subdirectory is copied with its directory structure
#   7. a '.' (repo root) entry is skipped
#   8. a symlink to a prefix-sharing sibling dir is rejected at the /-boundary
#
# Each case builds a throwaway git repo plus a sibling "outside" directory
# holding a marker file that must never be materialized inside the worktree.
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (the hook's floor). Run: bash tests/worktree-guard/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing case
# to report all results; failures are tracked via the `errors` counter instead.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/worktree-create.sh"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }

errors=0
TMPDIRS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local d; for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

for cmd in git jq; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd is required but not on PATH"; exit 2; }
done
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }

# Build a case sandbox: $SANDBOX/repo (git repo with one commit) and
# $SANDBOX/outside/secret.txt (the marker that must never be copied).
SANDBOX="" REPO="" OUTSIDE=""
new_sandbox() {
  SANDBOX="$(mktemp -d)"
  TMPDIRS+=("$SANDBOX")
  REPO="$SANDBOX/repo"
  OUTSIDE="$SANDBOX/outside"
  mkdir -p "$REPO" "$OUTSIDE"
  printf 'MARKER-DO-NOT-COPY\n' > "$OUTSIDE/secret.txt"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config user.name "worktree-guard-test"
  printf 'seed\n' > "$REPO/seed.txt"
  git -C "$REPO" add seed.txt
  git -C "$REPO" commit -qm seed
}

# Run the hook for repo $REPO with worktree name $1. Sets the globals WT (the
# returned worktree path) and RC (the hook's exit code) — globals, not a
# command substitution, so they survive into the caller's shell.
WT="" RC=0
run_hook() {
  local name="$1"
  RC=0
  WT="$(printf '{"cwd":"%s","name":"%s"}' "$REPO" "$name" | bash "$HOOK" 2>/dev/null)" || RC=$?
}

# Case 1 — positive control: regular file entry is copied.
new_sandbox
printf 'hello\n' > "$REPO/keep.txt"
printf 'keep.txt\n' > "$REPO/.worktreeinclude"
run_hook t1
if [ "$RC" = "0" ] && [ -f "$WT/keep.txt" ]; then
  ok "plain-copy" "regular file entry copied into worktree"
else
  err "plain-copy" "expected keep.txt in worktree (rc=$RC)"; errors=$((errors+1))
fi

# Case 2 — entry that is a symlink to an outside file is skipped.
new_sandbox
ln -s "$OUTSIDE/secret.txt" "$REPO/leak"
printf 'leak\n' > "$REPO/.worktreeinclude"
run_hook t2
if [ "$RC" = "0" ] && [ ! -e "$WT/leak" ] && [ ! -L "$WT/leak" ]; then
  ok "symlink-entry" "symlink entry skipped (nothing copied)"
else
  err "symlink-entry" "symlink entry was copied (rc=$RC) — copy-out not closed"; errors=$((errors+1))
fi

# Case 3 — entry under a symlinked directory (intermediate component) is skipped.
new_sandbox
ln -s "$OUTSIDE" "$REPO/linkdir"
printf 'linkdir/secret.txt\n' > "$REPO/.worktreeinclude"
run_hook t3
if [ "$RC" = "0" ] && [ ! -e "$WT/linkdir/secret.txt" ]; then
  ok "symlink-parent" "entry under symlinked directory skipped"
else
  err "symlink-parent" "entry under symlinked dir was copied (rc=$RC)"; errors=$((errors+1))
fi

# Case 4 — nested symlink inside a copied directory: copied as a link, never
# materialized as regular-file content.
new_sandbox
mkdir -p "$REPO/cfg"
printf 'real\n' > "$REPO/cfg/real.txt"
ln -s "$OUTSIDE/secret.txt" "$REPO/cfg/nested-leak"
printf 'cfg\n' > "$REPO/.worktreeinclude"
run_hook t4
if [ "$RC" = "0" ] && [ -f "$WT/cfg/real.txt" ] && { [ -L "$WT/cfg/nested-leak" ] || [ ! -e "$WT/cfg/nested-leak" ]; }; then
  ok "nested-symlink" "nested symlink copied as link (no content materialized)"
else
  err "nested-symlink" "nested symlink materialized as content (rc=$RC)"; errors=$((errors+1))
fi

# Case 5 — `../` traversal entry is still skipped (pre-existing filter).
# The marker-grep over the whole worktree is the operative assertion: it fails
# wherever in the worktree the escaped content might land.
new_sandbox
printf '../outside/secret.txt\n' > "$REPO/.worktreeinclude"
run_hook t5
if [ "$RC" = "0" ] && ! grep -rq "MARKER-DO-NOT-COPY" "$WT" 2>/dev/null; then
  ok "traversal" "../ traversal entry skipped"
else
  err "traversal" "traversal entry escaped containment (rc=$RC)"; errors=$((errors+1))
fi

# Case 6 — subdirectory file copied with structure intact.
new_sandbox
mkdir -p "$REPO/a/b"
printf 'deep\n' > "$REPO/a/b/deep.txt"
printf 'a/b/deep.txt\n' > "$REPO/.worktreeinclude"
run_hook t6
if [ "$RC" = "0" ] && [ -f "$WT/a/b/deep.txt" ]; then
  ok "subdir-copy" "subdirectory entry copied with structure"
else
  err "subdir-copy" "expected a/b/deep.txt in worktree (rc=$RC)"; errors=$((errors+1))
fi

# Case 7 — entry '.' (the repo root itself) is skipped, never copied wholesale.
new_sandbox
printf '.\n' > "$REPO/.worktreeinclude"
run_hook t7
if [ "$RC" = "0" ] && [ ! -e "$WT/repo" ] && [ ! -e "$WT/.wt_tmp" ]; then
  ok "dot-entry" "'.' entry skipped"
else
  err "dot-entry" "'.' entry was processed (rc=$RC)"; errors=$((errors+1))
fi

# Case 8 — symlink to a sibling directory whose path shares the repo prefix
# (e.g. repo at .../repo, target .../repo-evil): the /-boundary test must
# reject it even though the resolved path string starts with REPO_PHYS.
new_sandbox
EVIL="${REPO}-evil"
mkdir -p "$EVIL"
TMPDIRS+=("$EVIL")
printf 'MARKER-DO-NOT-COPY\n' > "$EVIL/secret.txt"
ln -s "$EVIL" "$REPO/sib"
printf 'sib/secret.txt\n' > "$REPO/.worktreeinclude"
run_hook t8
if [ "$RC" = "0" ] && ! grep -rq "MARKER-DO-NOT-COPY" "$WT" 2>/dev/null; then
  ok "prefix-sibling" "prefix-sharing sibling directory rejected at /-boundary"
else
  err "prefix-sibling" "prefix-sharing sibling escaped containment (rc=$RC)"; errors=$((errors+1))
fi

echo "=================================="
if [ "$errors" -eq 0 ]; then
  echo "PASS — 0 errors, 0 warnings"
  exit 0
else
  echo "FAIL — $errors errors, 0 warnings"
  exit 1
fi
