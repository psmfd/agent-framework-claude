#!/usr/bin/env bash
# Agent Framework — Setup Script
#
# Creates symlinks from ~/.claude/ to this repo so that rules, agents, and
# settings are version-controlled and consistent across machines. Installs git
# hooks and the destructive-command guard config. Safe to re-run — correct
# symlinks are skipped, existing files are backed up before linking.
#
# Usage:
#   ./setup.sh [OPTIONS]
#
# Options:
#   --dry-run          Print every action without making any change.
#   --non-interactive  Skip all prompts; apply safe defaults (skip optional steps).
#   -h, --help         Print this help text and exit.
#
# Environment opt-out matrix (set to 1 to skip a section):
#   SETUP_SKIP_SYMLINKS   Skip the ~/.claude symlink step.
#   SETUP_SKIP_GIT_HOOKS  Skip installing the pre-push / pre-commit git hooks.
#   DOTFILES_DIR          Override the detected repo root (advanced/non-standard layouts).
#
# Exit codes:
#   0  All steps completed without errors.
#   1  One or more errors encountered.
#   2  Environment precondition failure (e.g. shared lib missing).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$SCRIPT_DIR}"
CLAUDE_DIR="$HOME/.claude"

# Runtime flags (set by arg parsing).
DRY_RUN=0
NON_INTERACTIVE=0
PROMPT_YN=n

# Opt-out matrix — default off (run everything) unless set in the environment.
SETUP_SKIP_SYMLINKS="${SETUP_SKIP_SYMLINKS:-0}"
SETUP_SKIP_GIT_HOOKS="${SETUP_SKIP_GIT_HOOKS:-0}"

# Items to symlink into ~/.claude/  (src-in-repo:name-in-target)
CLAUDE_LINKS=(
  "rules:rules"
  "agents:agents"
  "settings.json:settings.json"
  "hooks:hooks"
  "commands:commands"
)

# --- Help (extracted from the header comment block; works before log.sh) ---
usage() {
  awk '
    NR==1 && /^#!/      { next }                       # skip shebang
    /^#/                { sub(/^# ?/, ""); print; next }
    /^[[:space:]]*$/    { next }                        # skip blank lines in header
    { exit }                                           # stop at first code line
  ' "$0"
}

# --- Dry-run-aware command runner: logs one message, executes unless --dry-run ---
# Usage: run "human message" command [args...]
run() {
  local msg="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    info "would: $msg"
    return 0
  fi
  info "$msg"
  "$@"
}

# --- Dry-run-aware file writer for heredoc content ---
# Usage: write_file "human message" DEST_PATH <<'EOF' ... EOF
write_file() {
  local msg="$1" dest="$2"
  if [ "$DRY_RUN" = "1" ]; then
    info "would: $msg"
    cat > /dev/null   # drain the caller's heredoc so it doesn't hit the terminal
    return 0
  fi
  info "$msg"
  cat > "$dest"
}

# --- Non-interactive-aware yes/no prompt; result in $PROMPT_YN (y|n) ---
# Usage: prompt_yn "Question?" DEFAULT   (DEFAULT is y or n)
prompt_yn() {
  local q="$1" def="$2" ans="" hint="[y/N]"
  [ "$def" = "y" ] && hint="[Y/n]"
  if [ "$NON_INTERACTIVE" = "1" ]; then
    PROMPT_YN="$def"
    return 0
  fi
  printf '%s %s ' "$q" "$hint"
  read -r ans || true   # guard against EOF under set -e
  ans="${ans:-$def}"
  case "$ans" in
    [Yy]*) PROMPT_YN=y ;;
    *)     PROMPT_YN=n ;;
  esac
}

# --- Argument parsing (bash-3.2 safe; before log.sh so --help needs nothing) ---
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)         DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    --)                shift; break ;;
    -*)                printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)                 printf 'Unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- Shared output helpers (rules/script-output-conventions.md, ADR-061) ---
if [ ! -f "$DOTFILES_DIR/scripts/lib/log.sh" ]; then
  printf 'ERROR [setup] shared lib not found: %s\n' "$DOTFILES_DIR/scripts/lib/log.sh" >&2
  printf 'INFO  run setup.sh from inside the agent-framework repo, or set DOTFILES_DIR\n' >&2
  exit 2
fi
# shellcheck source=scripts/lib/log.sh
. "$DOTFILES_DIR/scripts/lib/log.sh"

# --- Section: ~/.claude symlinks ---
link_items() {
  local target_dir="$1"; shift
  local entries=("$@")
  local entry src_name tgt_name src tgt backup

  if [ ! -d "$target_dir" ]; then
    run "[mkdir] $target_dir" mkdir -p "$target_dir"
  fi

  for entry in "${entries[@]}"; do
    src_name="${entry%%:*}"
    tgt_name="${entry##*:}"
    src="$DOTFILES_DIR/$src_name"
    tgt="$target_dir/$tgt_name"

    if [ ! -e "$src" ]; then
      skip "$tgt_name" "source not found in repo ($src)"
      continue
    fi
    if [ -L "$tgt" ] && [ "$(readlink "$tgt")" = "$src" ]; then
      ok "$tgt_name" "symlink already correct"
      continue
    fi
    if [ -e "$tgt" ] || [ -L "$tgt" ]; then
      backup="$tgt.bak.$(date +%Y%m%d%H%M%S)"
      run "[backup] $tgt_name -> $(basename "$backup")" mv "$tgt" "$backup"
    fi
    run "[symlink] $tgt_name -> $src" ln -s "$src" "$tgt"
  done
}

setup_symlinks() {
  if [ "$SETUP_SKIP_SYMLINKS" = "1" ]; then
    skip "symlinks" "SETUP_SKIP_SYMLINKS=1"
    return 0
  fi
  info "Claude Code ($CLAUDE_DIR):"
  link_items "$CLAUDE_DIR" "${CLAUDE_LINKS[@]}"
}

# --- Section: migrate off the predecessor cross-platform framework (ADR-077) ---
# This framework replaces the predecessor as the consumed install. link_items()
# already backs up and repoints the links this framework manages (rules, agents,
# settings.json, hooks, commands). This step removes the ORPHANED symlinks the
# predecessor created that the Claude-only framework does NOT manage: ~/.claude/skills
# and the ~/.copilot tree. Only symlinks are removed — a real directory is left
# untouched with a warning. Re-runnable; the predecessor repo on disk is never touched.
PREDECESSOR_ORPHANS=(
  "$CLAUDE_DIR/skills"
  "$HOME/.copilot/agents"
  "$HOME/.copilot/instructions"
)
setup_migrate_predecessor() {
  if [ "$SETUP_SKIP_SYMLINKS" = "1" ]; then
    skip "migrate" "SETUP_SKIP_SYMLINKS=1"
    return 0
  fi

  local orphans_present=() orphan
  for orphan in "${PREDECESSOR_ORPHANS[@]}"; do
    if [ -L "$orphan" ]; then
      orphans_present+=("$orphan")
    elif [ -e "$orphan" ]; then
      warn "migrate" "$orphan exists but is not a symlink — leaving untouched (remove by hand if intended)"
    fi
  done

  if [ ${#orphans_present[@]} -eq 0 ]; then
    ok "migrate" "no predecessor framework symlinks found — nothing to migrate"
    return 0
  fi

  info "Predecessor framework detected. Managed links (~/.claude rules/agents/etc.)"
  info "will be repointed to this repo; these orphaned links will be removed:"
  for orphan in "${orphans_present[@]}"; do
    info "  $orphan -> $(readlink "$orphan" 2>/dev/null || true)"
  done
  prompt_yn "Remove these orphaned predecessor symlinks?" y
  if [ "$PROMPT_YN" != "y" ]; then
    skip "migrate" "left predecessor symlinks in place (declined)"
    return 0
  fi

  for orphan in "${orphans_present[@]}"; do
    run "[unlink] $orphan" rm -f "$orphan"
  done
  # Remove the ~/.copilot directory if the predecessor left it empty.
  if [ -d "$HOME/.copilot" ] && [ -z "$(ls -A "$HOME/.copilot" 2>/dev/null)" ]; then
    run "[rmdir] empty ~/.copilot" rmdir "$HOME/.copilot"
  fi
  ok "migrate" "predecessor orphaned symlinks removed — managed links repointed next"
}

# --- Section: make framework hook scripts executable ---
setup_hook_chmod() {
  local h
  for h in "$DOTFILES_DIR"/hooks/*.sh; do
    [ -f "$h" ] || continue
    if [ -x "$h" ]; then
      ok "hooks" "$(basename "$h") already executable"
    else
      run "[hooks] chmod +x $(basename "$h")" chmod +x "$h"
    fi
  done
}

# --- Section: install git hooks (pre-push, pre-commit) ---
setup_git_hooks() {
  if [ "$SETUP_SKIP_GIT_HOOKS" = "1" ]; then
    skip "git-hooks" "SETUP_SKIP_GIT_HOOKS=1"
    return 0
  fi
  local hook_dir="$DOTFILES_DIR/.git/hooks"
  local marker="# managed by setup.sh"
  local hook_file backup

  if [ ! -d "$hook_dir" ]; then
    skip "git-hooks" "not a git repository ($hook_dir missing)"
    return 0
  fi

  # pre-push: gh-identity-guard.sh then validate.sh
  hook_file="$hook_dir/pre-push"
  if [ -f "$hook_file" ] && grep -q "$marker" "$hook_file" 2>/dev/null; then
    ok "pre-push" "hook already installed"
  else
    if [ -f "$hook_file" ]; then
      backup="$hook_file.bak.$(date +%Y%m%d%H%M%S)"
      run "[backup] pre-push -> $(basename "$backup")" mv "$hook_file" "$backup"
    fi
    write_file "[git-hook] install pre-push (gh-identity-guard + validate.sh)" "$hook_file" <<'HOOK'
#!/usr/bin/env bash
# managed by setup.sh — runs gh-identity-guard.sh, then validate.sh before push
set -euo pipefail
DOTFILES_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# Block a wrong-account push first (fail-fast, one clear message) — see ADR-054.
"$DOTFILES_DIR/hooks/gh-identity-guard.sh" "$@"
echo "Running validate.sh before push..."
"$DOTFILES_DIR/validate.sh"
HOOK
    run "[git-hook] chmod +x pre-push" chmod +x "$hook_file"
  fi

  # pre-commit: secrets-guard.sh
  hook_file="$hook_dir/pre-commit"
  if [ -f "$hook_file" ] && grep -q "$marker" "$hook_file" 2>/dev/null; then
    ok "pre-commit" "hook already installed"
  else
    if [ -f "$hook_file" ]; then
      backup="$hook_file.bak.$(date +%Y%m%d%H%M%S)"
      run "[backup] pre-commit -> $(basename "$backup")" mv "$hook_file" "$backup"
    fi
    write_file "[git-hook] install pre-commit (secrets-guard)" "$hook_file" <<'HOOK'
#!/usr/bin/env bash
# managed by setup.sh — runs secrets-guard.sh before commit
set -euo pipefail
DOTFILES_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
"$DOTFILES_DIR/hooks/secrets-guard.sh"
HOOK
    run "[git-hook] chmod +x pre-commit" chmod +x "$hook_file"
  fi
}

# --- Section: optional local-only GitHub identity pin (ADR-060) ---
setup_gh_pin() {
  local gh_id_file="$DOTFILES_DIR/.gh-expected-identity"
  local login=""
  if [ -f "$gh_id_file" ]; then
    ok "gh-pin" ".gh-expected-identity present (gitignored, local-only)"
    return 0
  fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    skip "gh-pin" "non-interactive — gh-identity guard will use the accessibility fallback"
    return 0
  fi
  printf 'Pin a GitHub login for the identity guard? Enter your login (blank to skip): '
  read -r login || true
  if [ -n "${login:-}" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "would: write .gh-expected-identity pinned to '$login'"
    else
      printf '%s\n' "$login" > "$gh_id_file"
      info "[gh-pin] .gh-expected-identity created for '$login' (gitignored, local-only)"
    fi
  else
    skip "gh-pin" "the gh-identity guard will use the accessibility fallback"
  fi
}

# --- Section: destructive-command guard safe-paths config ---
setup_bashguard() {
  local cfg="$CLAUDE_DIR/bash-guard-safe-paths.conf"
  local marker="# managed by setup.sh"
  local backup
  if [ -f "$cfg" ] && grep -q "$marker" "$cfg" 2>/dev/null; then
    ok "bash-guard" "safe-paths.conf already configured"
    return 0
  fi
  if [ ! -d "$CLAUDE_DIR" ]; then
    run "[mkdir] $CLAUDE_DIR" mkdir -p "$CLAUDE_DIR"
  fi
  if [ -f "$cfg" ]; then
    backup="$cfg.bak.$(date +%Y%m%d%H%M%S)"
    run "[backup] bash-guard-safe-paths.conf -> $(basename "$backup")" mv "$cfg" "$backup"
  fi
  write_file "[bash-guard] create safe-paths.conf with defaults" "$cfg" <<'CONF'
# managed by setup.sh — safe paths for bash-destructive-guard.sh
# One absolute path prefix per line. rm/mv targets must be under one of these.
# /tmp is always allowed (built-in default).
# Relative paths within the current project directory are always allowed.
# Add user-specific paths here as needed; this file ships empty.
CONF
}

main() {
  info "Agent Framework setup — source: $DOTFILES_DIR"
  [ "$DRY_RUN" = "1" ] && info "dry-run mode — no changes will be made"

  setup_migrate_predecessor
  setup_symlinks
  setup_hook_chmod
  setup_git_hooks
  setup_gh_pin
  setup_bashguard

  print_summary
}

main "$@"
