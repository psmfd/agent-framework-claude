#!/usr/bin/env bash
#
# bash-destructive-guard.sh — Global PreToolUse hook
#
# Denies rm and mv commands targeting paths outside a configurable safe list.
# Fires on every Bash/execute tool call across all agents and sessions.
#
# Detection (per command segment — the command is split on &&, ||, |, ;, and
# newline so a destructive op cannot hide on a later line/segment):
#   - A "canonical verb" is resolved past leading wrapper commands
#     (env/sudo/xargs/time/nice/nohup/command/builtin) and their flags, so
#     `env rm ...` / `sudo rm ...` / `xargs rm` are caught. `git rm`,
#     `grep rm`, etc. are NOT flagged because the canonical verb is git/grep.
#   - Shell-interpreter `-c` invocations (bash/sh/dash/zsh/ksh/busybox) are
#     denied.
#   - `find ... -delete` / `-exec rm` / `-execdir rm` are denied.
#   - For `rm`/`mv`: in a compound command any rm/mv segment is denied; a
#     single rm/mv is denied only when a path falls outside the safe list.
#
# Known accepted gaps (defense-in-depth, not a sandbox): non-shell interpreter
#   payloads (`perl -e 'unlink'`, `python -c '...os.remove...'`), content
#   destructors that are not path-removal (`truncate`, `dd of=`, `>` redirect,
#   `shred`), `rsync --remove-source-files`, a wrapper flag that takes a value
#   before the verb (`sudo -u root rm`), and quoted separators/paths
#   (`read -ra` does not honor shell quoting). The pattern set is best-effort.
#
# Platforms: Claude Code (Bash tool), VS Code Copilot (execute tool),
#   Copilot CLI (execute tool — only deny is processed)
# Contract: exit 0 = allow, exit 2 = deny. Stderr on deny is shown to user.
#
# Safe paths: /tmp (built-in) + lines in ~/.claude/bash-guard-safe-paths.conf
#
# Usage:
#   Exit codes:
#     0 — command allowed (not destructive, or targets safe paths)
#     2 — command denied (destructive command targeting unsafe path)

set -uo pipefail

INPUT="$(cat)"
[[ -z "$INPUT" ]] && exit 0

deny() {
  echo "bash-destructive-guard: denied — $1" >&2
  exit 2
}

# --- Dependency guard: jq is required to parse tool input (fail CLOSED) ---
# Without jq the parses below yield "" via the `// ""` fallbacks, the tool-name
# filter falls through to `exit 0`, and the guard silently self-disables on any
# jq-less host. A missing dependency is an indeterminate state and is denied,
# matching the sibling secrets/identity guards (ADR-057). The hook fires only on
# tool calls, so this never blocks normal shell use outside the agent.
command -v jq >/dev/null 2>&1 || deny "jq not on PATH; cannot parse tool input to verify path safety. Install jq (apt install jq / brew install jq)."

# --- Tool-name self-filter ---
# Claude Code uses "Bash" as tool_name; Copilot uses "execute" as toolName.
# VS Code ignores matchers — this hook fires on ALL tool calls.
# Allow any tool that is not Bash/execute immediately.
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // .toolName // ""')"
case "$TOOL_NAME" in
  Bash|execute) ;;
  *) exit 0 ;;
esac

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .toolInput.command // ""')"
[[ -z "$COMMAND" ]] && exit 0

WRAPPER_VERBS="env sudo nice nohup time command builtin xargs"
INTERPRETERS="bash sh dash zsh ksh busybox"

# --- Load safe-path list ---
SAFE_PATHS=("/tmp")
CONFIG="$HOME/.claude/bash-guard-safe-paths.conf"
if [[ -f "$CONFIG" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    line="${line#"${line%%[! ]*}"}"
    line="${line%"${line##*[! ]}"}"
    SAFE_PATHS+=("$line")
  done < "$CONFIG"
fi

# --- Path-safety check for a single rm/mv invocation ---
# Args: the canonical verb followed by its arguments. Denies (exit 2) if any
# path token is outside the safe list, contains shell metacharacters, or has a
# `..` traversal. Allows relative paths within the project.
check_path_safety() {
  local verb="$1"; shift
  local paths=() past_dashdash=0 tok
  for tok in "$@"; do
    if [[ "$tok" == "--" ]]; then
      past_dashdash=1
    elif (( past_dashdash )) || [[ "$tok" != -* ]]; then
      paths+=("$tok")
    fi
  done
  (( ${#paths[@]} == 0 )) && return 0
  local p s match
  for p in "${paths[@]}"; do
    if [[ "$p" =~ [\$\`\|\;\&\(\)\{\}] ]]; then
      deny "'$verb' — path '$p' contains shell metacharacters"
    fi
    if [[ "$p" == *".."* ]]; then
      deny "'$verb' — path '$p' contains '..' traversal"
    fi
    match=0
    for s in "${SAFE_PATHS[@]}"; do
      if [[ "$p" == "$s" || "$p" == "$s/"* ]]; then match=1; break; fi
    done
    # Relative paths within the project are allowed (.. already denied above).
    if (( match == 0 )) && [[ "$p" != /* ]]; then match=1; fi
    if (( match == 0 )); then
      echo "bash-destructive-guard: denied '$verb $p' — path is outside safe list" >&2
      echo "bash-destructive-guard: safe paths: ${SAFE_PATHS[*]}" >&2
      exit 2
    fi
  done
}

# --- Split COMMAND into segments on && || | ; and newline ---
# Order matters: collapse two-char operators before the single pipe.
segs="$COMMAND"
segs="${segs//&&/$'\n'}"
segs="${segs//||/$'\n'}"
segs="${segs//|/$'\n'}"
segs="${segs//;/$'\n'}"

# Count non-blank segments (a compound command has more than one).
seg_count=0
while IFS= read -r seg; do
  [[ -z "${seg//[[:space:]]/}" ]] && continue
  seg_count=$((seg_count + 1))
done <<< "$segs"

# --- Evaluate each segment ---
while IFS= read -r seg; do
  [[ -z "${seg//[[:space:]]/}" ]] && continue
  read -ra toks <<< "$seg"
  (( ${#toks[@]} == 0 )) && continue

  # Resolve canonical verb: skip leading wrapper verbs and their flags /
  # (for env) VAR=val assignments. Depth-capped against adversarial stacking.
  idx=0; guard=0
  while (( guard < 8 )); do
    guard=$((guard + 1))
    cur="${toks[$idx]:-}"
    is_wrap=0
    for w in $WRAPPER_VERBS; do
      [[ "$cur" == "$w" ]] && { is_wrap=1; break; }
    done
    (( is_wrap == 0 )) && break
    idx=$((idx + 1))
    while [[ "${toks[$idx]:-}" == -* || "${toks[$idx]:-}" == *=* ]]; do
      idx=$((idx + 1))
    done
  done
  cverb="${toks[$idx]:-}"

  # Shell interpreter with -c
  for it in $INTERPRETERS; do
    if [[ "$cverb" == "$it" ]]; then
      for ((j = idx + 1; j < ${#toks[@]}; j++)); do
        if [[ "${toks[$j]}" == "-c" || "${toks[$j]}" == -[^-]*c* ]]; then
          deny "shell interpreter with -c is not permitted"
        fi
      done
    fi
  done

  # find with a destructive action
  if [[ "$cverb" == "find" ]]; then
    fe=0
    for ((j = idx; j < ${#toks[@]}; j++)); do
      case "${toks[$j]}" in
        -delete) deny "find -delete is not permitted" ;;
        -exec|-execdir) fe=1 ;;
        rm|mv) (( fe )) && deny "find -exec ${toks[$j]} is not permitted" ;;
      esac
    done
  fi

  # rm / mv
  if [[ "$cverb" == "rm" || "$cverb" == "mv" ]]; then
    if (( seg_count > 1 )); then
      deny "compound command contains '$cverb'"
    else
      check_path_safety "${toks[@]:idx}"
    fi
  fi
done <<< "$segs"

exit 0
