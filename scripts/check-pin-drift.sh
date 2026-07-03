#!/usr/bin/env bash
#
# scripts/check-pin-drift.sh — detect stale workflow-embedded container digests.
#
# Dependabot's docker ecosystem does not scan image references embedded in
# workflow YAML (dependabot-core #5541), so a `docker run <image>@sha256:...`
# pin silently goes stale. This script finds every such pin across
# .github/workflows/*.yml, resolves the CURRENT digest of the tag named in the
# adjacent convention comment (`# <image>:<tag> ...`), and compares.
#
# Convention (extractor fails loudly if a pin has no comment, per the ADR-083
# lockstep-extractor philosophy):
#     # <registry>/<repo>:<tag> (SHA-pinned, ADR-NNN)
#     ... <registry>/<repo>@sha256:<64 hex> ...
# The comment may appear up to 5 lines above the pin.
#
# Run by .github/workflows/pin-drift-check.yml (weekly). On genuine drift the
# WORKFLOW files/updates an idempotent issue; this script only reports:
#
# Exit codes:
#   0 — all pins current
#   1 — one or more pins drifted (details on stdout as DRIFT lines)
#   2 — precondition/inspection failure (missing tool, unreadable registry,
#       pin without a convention comment) — indeterminate, NOT drift
#
# Output (machine-readable, one per pin, on stdout):
#   CURRENT <file> <image>:<tag> <digest>
#   DRIFT   <file> <image>:<tag> <pinned-digest> <current-digest>
#
# Targets bash 3.2. Requires skopeo (preinstalled on ubuntu-24.04 runners)
# and jq.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

command -v skopeo >/dev/null 2>&1 || fatal "env" "skopeo is required (preinstalled on ubuntu-24.04 runners)" 2
command -v jq     >/dev/null 2>&1 || fatal "env" "jq is required" 2

WF_DIR="$REPO_DIR/.github/workflows"
[ -d "$WF_DIR" ] || fatal "env" ".github/workflows not found" 2

drift=0 indeterminate=0 found=0

for wf in "$WF_DIR"/*.yml; do
  [ -f "$wf" ] || continue
  # "lineno<TAB>image<TAB>digest" for every image@sha256 pin in the file.
  pins="$(awk '
    match($0, /[A-Za-z0-9.\/_-]+@sha256:[0-9a-f]{64}/) {
      ref = substr($0, RSTART, RLENGTH)
      split(ref, parts, "@")
      print NR "\t" parts[1] "\t" parts[2]
    }' "$wf")"
  [ -n "$pins" ] || continue

  while IFS="$(printf '\t')" read -r lineno image pinned; do
    [ -n "$image" ] || continue
    found=1
    # Find the convention comment within the 5 lines above the pin.
    start=$(( lineno - 5 )); [ "$start" -lt 1 ] && start=1
    tag="$(sed -n "${start},${lineno}p" "$wf" \
      | grep -oE "# *${image}:[A-Za-z0-9._-]+" \
      | tail -1 | sed -E "s|.*${image}:||")"
    if [ -z "$tag" ]; then
      err "pin-drift" "${wf##*/}:${lineno}: pin for ${image} has no adjacent '# ${image}:<tag>' comment — extractor cannot resolve the intended tag"
      indeterminate=1
      continue
    fi
    current="$(skopeo inspect --no-tags "docker://${image}:${tag}" 2>/dev/null | jq -r .Digest)" || current=""
    if [ -z "$current" ] || [ "$current" = "null" ]; then
      err "pin-drift" "${wf##*/}: could not resolve current digest for ${image}:${tag} (registry/network) — indeterminate, not drift"
      indeterminate=1
      continue
    fi
    if [ "$current" = "$pinned" ]; then
      ok "pin-drift" "${wf##*/}: ${image}:${tag} pin is current"
      printf 'CURRENT %s %s:%s %s\n' "${wf##*/}" "$image" "$tag" "$pinned"
    else
      warn "pin-drift" "${wf##*/}: ${image}:${tag} pin is stale — pinned ${pinned}, tag now ${current}"
      printf 'DRIFT %s %s:%s %s %s\n' "${wf##*/}" "$image" "$tag" "$pinned" "$current"
      drift=1
    fi
  done <<EOF
$pins
EOF
done

[ "$found" = "1" ] || info "no workflow-embedded digest pins found"
print_summary >/dev/null 2>&1 || true

[ "$indeterminate" = "1" ] && exit 2
[ "$drift" = "1" ] && exit 1
exit 0
