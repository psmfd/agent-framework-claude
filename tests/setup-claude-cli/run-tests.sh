#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for setup.sh's setup_claude_cli() section
# (Claude Code CLI install, issue #48 / ADR-093)
#
# Approach: source setup.sh (guarded so main() does not run) in a subshell with
# a controlled HOME/PATH and shimmed `claude`/`curl`/`uname`, then call
# setup_claude_cli directly. This isolates the CLI step from the rest of setup
# (no symlinks, no gh-pin prompt). The real ~/.claude and the network are never
# touched — `curl` is always a shim, and installs land under a throwaway HOME.
#
# Coverage:
#   1. claude present                       -> OK already installed, curl NOT called
#   2. absent, --dry-run                     -> "would: download", curl NOT called
#   3. absent, non-interactive, no opt-in    -> SKIP (set CLAUDE_CLI_INSTALL=1), curl NOT called
#   4. absent, non-interactive + opt-in      -> curl called once, OK installed
#   5. absent, interactive, prompt accepted  -> curl called, OK installed
#   6. absent, interactive, prompt declined  -> SKIP declined, curl NOT called
#   7. absent, unsupported platform (uname)  -> WARN unsupported, curl NOT called
#   8. absent, installer runs but no binary  -> ERROR not found (fail-safe, no abort)
#
# Output per rules/script-output-conventions.md. Exit: 0 all pass, 1 fail, 2 precond.
# Targets bash 3.2+. Run: bash tests/setup-claude-cli/run-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_DIR/setup.sh"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
TMPFILES=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap
cleanup() { local f; for f in ${TMPFILES[@]+"${TMPFILES[@]}"}; do [ -n "$f" ] && rm -rf "$f"; done; }
trap cleanup EXIT

for cmd in bash mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd required but not on PATH"; exit 2; }
done
[ -f "$SETUP" ] || { err "env" "setup.sh not found at $SETUP"; exit 2; }

# --- Per-case scaffolding ----------------------------------------------------
H="" SHIMS="" CURL_LOG=""
new_case() {
  H="$(mktemp -d)";      TMPFILES+=("$H")
  SHIMS="$(mktemp -d)";  TMPFILES+=("$SHIMS")
  CURL_LOG="$H/curl-calls.log"
}

# A fake `claude` on PATH (the "already installed" case).
shim_claude_present() {
  cat > "$SHIMS/claude" <<'SH'
#!/bin/sh
echo "2.1.199 (Claude Code)"
SH
  chmod +x "$SHIMS/claude"
}

# A fake `curl` that logs its call and copies a pre-written installer to the -o
# target (kept as a separate file to avoid nested heredocs, which bash 3.2 does
# not parse). mode=install -> the installer creates a working
# $HOME/.local/bin/claude; mode=noop -> it creates nothing (broken install).
shim_curl() {
  local mode="$1"
  if [ "$mode" = install ]; then
    cat > "$SHIMS/.installer" <<'INST'
#!/usr/bin/env bash
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho "2.1.199 (Claude Code)"\n' > "$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
INST
  else
    cat > "$SHIMS/.installer" <<'INST'
#!/usr/bin/env bash
exit 0
INST
  fi
  cat > "$SHIMS/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "$HOME/curl-calls.log"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && cp "$(dirname "$0")/.installer" "$out"
exit 0
SH
  chmod +x "$SHIMS/curl"
}

# A fake `uname` reporting an unsupported OS.
shim_uname_unsupported() {
  cat > "$SHIMS/uname" <<'SH'
#!/bin/sh
echo "SunOS"
SH
  chmod +x "$SHIMS/uname"
}

# Run setup_claude_cli in a subshell with the shims + controlled flags.
# Args (as env-style globals set by the caller): NI DR CCI FEED
OUT=""
run_cli() {
  local ni="$1" dr="$2" cci="$3" feed="$4"
  printf '%s' "$feed" > "$H/.feed"
  # NOTE: comments inside the $( ) below must avoid quotes/backticks — the
  # bash 3.2 command-substitution scanner does not honor comments, so an
  # apostrophe inside one reads as an unbalanced quote and breaks the parse.
  OUT="$(
    (
      set --
      # Hermetic PATH: shims first, then standard system dirs only. This
      # deliberately EXCLUDES ~/.local/bin so a real claude install cannot
      # leak in and defeat the absent cases; the CLI step needs only
      # coreutils + bash + the shims.
      export DOTFILES_DIR="$REPO_DIR" HOME="$H" PATH="$SHIMS:/usr/bin:/bin"
      # shellcheck source=/dev/null
      . "$SETUP"
      # Consumed by the sourced setup_claude_cli; exported so the values also
      # reach the installer/curl shims and shellcheck sees them as used.
      export DRY_RUN="$dr" NON_INTERACTIVE="$ni" CLAUDE_CLI_INSTALL="$cci"
      setup_claude_cli < "$H/.feed"
    ) 2>&1
  )" || true
}

curl_called()     { [ -s "$CURL_LOG" ]; }
assert() {  # name  want_substr  want_curl(yes|no)
  local name="$1" substr="$2" want_curl="$3" bad=0
  case "$OUT" in *"$substr"*) : ;; *) err "$name" "missing '$substr' — got: $(printf '%s' "$OUT" | tr '\n' '|')"; bad=1 ;; esac
  if [ "$want_curl" = yes ] && ! curl_called; then err "$name" "expected curl to be called, it was not"; bad=1; fi
  if [ "$want_curl" = no ] && curl_called; then err "$name" "curl was called but should NOT have been: $(cat "$CURL_LOG")"; bad=1; fi
  if [ "$bad" = 0 ]; then ok "$name" "as expected"; else errors=$((errors + 1)); fi
}

# --- Case 1: already installed ------------------------------------------------
case_present() {
  new_case; shim_claude_present; shim_curl install
  run_cli 1 0 1 ""
  assert "present" "already installed" no
}

# --- Case 2: --dry-run --------------------------------------------------------
case_dry_run() {
  new_case; shim_curl install
  run_cli 1 1 1 ""
  assert "dry-run" "would: download" no
}

# --- Case 3: non-interactive, no opt-in -> SKIP -------------------------------
case_ni_no_optin() {
  new_case; shim_curl install
  run_cli 1 0 0 ""
  assert "ni-no-optin" "set CLAUDE_CLI_INSTALL=1" no
}

# --- Case 4: non-interactive + opt-in -> install ------------------------------
case_ni_optin_install() {
  new_case; shim_curl install
  run_cli 1 0 1 ""
  assert "ni-install" "installed" yes
  if [ -x "$H/.local/bin/claude" ]; then ok "ni-install-binary" "claude landed in ~/.local/bin"; else err "ni-install-binary" "no binary at ~/.local/bin/claude"; errors=$((errors+1)); fi
}

# --- Case 5: interactive, accepted -> install ---------------------------------
case_interactive_accept() {
  new_case; shim_curl install
  run_cli 0 0 0 "y
"
  assert "interactive-accept" "installed" yes
}

# --- Case 6: interactive, declined -> SKIP ------------------------------------
case_interactive_decline() {
  new_case; shim_curl install
  run_cli 0 0 0 "n
"
  assert "interactive-decline" "declined" no
}

# --- Case 7: unsupported platform -> WARN, no install -------------------------
case_unsupported() {
  new_case; shim_curl install; shim_uname_unsupported
  run_cli 1 0 1 ""
  assert "unsupported" "unsupported platform" no
}

# --- Case 8: installer runs but leaves no binary -> ERROR (no abort) ----------
case_install_no_binary() {
  new_case; shim_curl noop
  run_cli 1 0 1 ""
  assert "install-no-binary" "not found" yes
}

info "setup.sh setup_claude_cli() acceptance tests"
case_present
case_dry_run
case_ni_no_optin
case_ni_optin_install
case_interactive_accept
case_interactive_decline
case_unsupported
case_install_no_binary

echo "=================================="
if [ "$errors" -gt 0 ]; then echo "FAIL — $errors error(s)"; exit 1; fi
echo "PASS — 0 errors"
exit 0
