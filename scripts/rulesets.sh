#!/usr/bin/env bash
#
# scripts/rulesets.sh — ruleset-as-code for GitHub branch-protection rulesets.
#
# rulesets/<name>.json is the committed desired state (ADR-086). Files are
# normalized (jq -S, explicit key allowlist, sorted rules/contexts) so the
# committed shape IS the PUT body — one format for diffing and applying.
#
#   --check              Diff live GitHub ruleset state against rulesets/*.json.
#                        SKIPs (exit 0) when gh/network/auth are unavailable —
#                        the offline gate is validate.sh check_ruleset_job_drift.
#   --apply <name>       PUT (or POST if absent live) rulesets/<name>.json.
#                        Requires repo Administration:write (a maintainer's own
#                        gh session — GITHUB_TOKEN cannot hold it). Confirm
#                        prompt (default deny); honors --dry-run / --yes.
#   --pull <name>        Fetch live state, normalize, write rulesets/<name>.json
#                        (seed or resync after an intentional UI change).
#   -h, --help           Print this help and exit.
#
# Options: --dry-run  --yes  --repo <owner/repo>
#
# Exit codes: 0 ok/skipped · 1 drift or apply failure · 2 precondition failure
#
# Targets bash 3.2 (macOS system bash) — no 4.0-only features.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=scripts/lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"

usage() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/,""); print; next} /^[[:space:]]*$/ {next} {exit}' "$0"
}

# Normalization filter: explicit allowlist (fail-closed on unknown fields),
# rules sorted by type, required-check contexts sorted alphabetically.
# Applied to BOTH the live GET response and (idempotently) the committed file.
NORMALIZE='{
  name: .name, target: .target, enforcement: .enforcement,
  conditions: .conditions,
  bypass_actors: (.bypass_actors // [] | sort_by(.actor_id, .actor_type)),
  rules: (.rules | sort_by(.type)
    | map(if .type == "required_status_checks"
          then .parameters.required_status_checks |= sort_by(.context)
          else . end))
}'

MODE="" NAME="" DRY_RUN=0 ASSUME_YES=0 REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check)   MODE="check" ;;
    --apply)   MODE="apply"; NAME="${2:-}"; shift ;;
    --pull)    MODE="pull";  NAME="${2:-}"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    --yes|--force) ASSUME_YES=1 ;;
    --repo)    REPO="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -z "$MODE" ] && { usage >&2; exit 2; }
if [ "$MODE" != "check" ] && [ -z "$NAME" ]; then
  fatal "rulesets" "--$MODE requires a ruleset name (rulesets/<name>.json)" 2
fi

command -v jq >/dev/null 2>&1 || fatal "env" "jq is required" 2

REPO_ROOT="$(git_repo_root)" || fatal "rulesets" "not inside a git repository" 2
RULESETS_DIR="$REPO_ROOT/rulesets"

# gh + auth + repo resolution. For --check these are SKIP conditions (the
# check is a convenience, never a gate); for --apply/--pull they are hard
# preconditions of an explicitly requested operation.
probe_fail() {
  if [ "$MODE" = "check" ]; then
    skip "rulesets" "live drift check skipped — $1"
    exit 0
  fi
  fatal "rulesets" "$1" 2
}
command -v gh >/dev/null 2>&1 || probe_fail "gh not on PATH"
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
    || probe_fail "cannot resolve repository (gh unauthenticated or network unavailable)"
fi

# List live rulesets once: "id<TAB>name" lines.
LIVE_INDEX="$(gh api "repos/$REPO/rulesets" --jq '.[] | "\(.id)\t\(.name)"' 2>/dev/null)" \
  || probe_fail "cannot list rulesets for $REPO (network/auth)"

live_id_for() {
  printf '%s\n' "$LIVE_INDEX" | awk -F'\t' -v n="$1" '$2==n {print $1; exit}'
}

fetch_normalized() {  # $1 = live id
  gh api "repos/$REPO/rulesets/$1" 2>/dev/null | jq -S "$NORMALIZE"
}

confirm() {  # $1 = action description; honors --yes; default deny
  [ "$ASSUME_YES" = "1" ] && return 0
  if [ ! -t 0 ]; then
    err "rulesets" "non-interactive and no --yes — refusing to $1"
    return 1
  fi
  printf 'Proceed to %s? [y/N] ' "$1"
  read -r ans || ans=""
  case "$ans" in y|Y|yes|YES) return 0 ;; *) info "aborted"; return 1 ;; esac
}

case "$MODE" in

check)
  found_any=0
  for f in "$RULESETS_DIR"/*.json; do
    [ -f "$f" ] || continue
    found_any=1
    name="$(basename "$f" .json)"
    id="$(live_id_for "$name")"
    if [ -z "$id" ]; then
      err "rulesets" "'$name' has no matching live ruleset — run --apply $name to create it"
      continue
    fi
    live="$(fetch_normalized "$id")" || { err "rulesets" "failed to fetch live '$name'"; continue; }
    committed="$(jq -S "$NORMALIZE" "$f")" || { err "rulesets" "$f is not valid ruleset JSON"; continue; }
    if [ "$live" = "$committed" ]; then
      ok "rulesets" "$name matches live state"
    else
      err "rulesets" "$name drifted from live state — VERBOSE=1 for the diff; --pull $name to adopt live, --apply $name to push committed"
      if [ "${VERBOSE:-0}" = "1" ]; then
        diff <(printf '%s\n' "$committed") <(printf '%s\n' "$live") | while IFS= read -r l; do detail "$l"; done
      fi
    fi
  done
  [ "$found_any" = "1" ] || skip "rulesets" "no rulesets/*.json committed — nothing to check"
  print_summary
  exit $?
  ;;

apply)
  f="$RULESETS_DIR/$NAME.json"
  [ -f "$f" ] || fatal "rulesets" "$f not found" 2
  jq empty "$f" 2>/dev/null || fatal "rulesets" "$f is not valid JSON" 2
  id="$(live_id_for "$NAME")"
  if [ -n "$id" ]; then
    verb="PUT" ; url="repos/$REPO/rulesets/$id"
    live="$(fetch_normalized "$id")" || fatal "rulesets" "failed to fetch live '$NAME'" 1
    committed="$(jq -S "$NORMALIZE" "$f")"
    if [ "$live" = "$committed" ]; then
      ok "rulesets" "$NAME already matches live state — nothing to apply"
      print_summary; exit $?
    fi
    info "changes to apply to '$NAME':"
    diff <(printf '%s\n' "$live") <(printf '%s\n' "$committed") | sed 's/^/      /' || true
  else
    verb="POST"; url="repos/$REPO/rulesets"
    info "'$NAME' does not exist live — will create it"
  fi
  if [ "$DRY_RUN" = "1" ]; then
    info "would: $verb $url --input $f"
    print_summary; exit $?
  fi
  confirm "$verb $NAME to $REPO" || { print_summary; exit 1; }
  if gh api --method "$verb" "$url" --input "$f" >/dev/null; then
    ok "rulesets" "$NAME applied ($verb)"
  else
    err "rulesets" "$NAME apply failed"
  fi
  print_summary
  exit $?
  ;;

pull)
  id="$(live_id_for "$NAME")"
  [ -n "$id" ] || fatal "rulesets" "no live ruleset named '$NAME' in $REPO" 1
  live="$(fetch_normalized "$id")" || fatal "rulesets" "failed to fetch live '$NAME'" 1
  f="$RULESETS_DIR/$NAME.json"
  if [ -f "$f" ] && [ "$(jq -S "$NORMALIZE" "$f")" = "$live" ]; then
    ok "rulesets" "$NAME already in sync — no write needed"
    print_summary; exit $?
  fi
  if [ "$DRY_RUN" = "1" ]; then
    info "would: write normalized live state of '$NAME' to $f"
    print_summary; exit $?
  fi
  if [ -f "$f" ]; then
    confirm "overwrite $f with live state" || { print_summary; exit 1; }
  fi
  mkdir -p "$RULESETS_DIR"
  printf '%s\n' "$live" > "$f"
  ok "rulesets" "wrote $f from live state"
  print_summary
  exit $?
  ;;
esac
