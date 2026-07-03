#!/usr/bin/env bash
# Agent Framework — Agent Catalog Drift Gate
#
# AGENTS.md "Available Agents" is the canonical (and only always-loaded)
# catalog for each agent's Tier / Domain / Use-when (ADR-062; the generated
# routing mirror in rules/agent-first-selection.md was retired by ADR-085 —
# that rule now carries a pointer instead of a table copy).
#
#   --check  (default)  Detect drift; write nothing; exit non-zero on drift.
#                       Wired into validate.sh as a blocking check.
#   -h, --help          Print this help and exit.
#
# What --check verifies (keyed by agent name):
#   - every AGENTS.md agent has agents/<name>.md            (error if missing)
#   - every agents/<name>.md appears in AGENTS.md           (warn if missing)
#   - rules/agent-first-selection.md carries NO catalog table (a reintroduced
#     mirror is drift) and still points at AGENTS.md         (error)
#   - README "Current Agents" Tier matches AGENTS.md, and Model matches each
#     wrapper's `model:` frontmatter                        (error on drift)
#
# Out of scope (intentionally divergent): README Description column, and the
# web/instructions.md Agent Catalog (condensed; covered by the web-sync check).
#
# Exit codes:
#   0  no drift
#   1  drift detected
#   2  environment / precondition failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=scripts/lib/git.sh
. "$SCRIPT_DIR/lib/git.sh"

usage() {
  awk '
    NR==1 && /^#!/   { next }
    /^#/             { sub(/^# ?/, ""); print; next }
    /^[[:space:]]*$/ { next }
    { exit }
  ' "$0"
}

case "${1:-}" in
  --check|"") : ;;
  --write)    printf -- '--write was retired with the routing mirror (ADR-085); AGENTS.md is edited by hand and gated by --check\n' >&2; exit 2 ;;
  -h|--help)  usage; exit 0 ;;
  *)          printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac

REPO_ROOT="$(git_repo_root)" || fatal "catalog" "not inside a git repository" 2
AGENTS_MD="$REPO_ROOT/AGENTS.md"
AGENTS_DIR="$REPO_ROOT/agents"
README_MD="$REPO_ROOT/README.md"
ROUTING_RULE="$REPO_ROOT/rules/agent-first-selection.md"

[ -f "$AGENTS_MD" ]   || fatal "catalog" "AGENTS.md not found at $AGENTS_MD" 2
[ -d "$AGENTS_DIR" ]  || fatal "catalog" "agents/ directory not found at $AGENTS_DIR" 2

TMPDIR_BASE="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "$TMPDIR_BASE/regen-catalog.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- Markdown table helpers -------------------------------------------------

# Emit the data rows of the table whose header line is the literal prefix $2.
# Row collection ends at the first line that is not a `|`-prefixed table row
# (#28) — terminating only on blank/`#` lines silently consumed trailing
# prose as spurious data rows when a table was not followed by a blank line.
extract_body() {
  awk -v h="$2" '
    index($0,h)==1         { st=1; next }
    st==1 && /^\|[[:space:]]*-/ { st=2; next }
    st==2 && $0 !~ /^\|/   { exit }
    st==2                  { print }
  ' "$1"
}

# Read raw table rows on stdin; emit tab-separated trimmed cells (backticks
# preserved). A leading/trailing pipe yields empty edge fields, dropped here.
# GFM-escaped pipes (\|) inside a cell are protected from the field split and
# restored as literal pipes in the emitted cell (#28).
cells_tsv() {
  awk '
    function trim(s){ sub(/^[ \t\r]+/,"",s); sub(/[ \t\r]+$/,"",s); return s }
    {
      line=$0
      gsub(/\\\|/, "\001", line)
      n=split(line, f, "|")
      out=""
      for (i=2; i<n; i++) {
        c=trim(f[i]); gsub(/\001/, "|", c)
        out = out (i>2 ? "\t" : "") c
      }
      print out
    }'
}

# --- Build canonical data from AGENTS.md ------------------------------------
# canon.tsv:  name <tab> tier <tab> domain <tab> usewhen
CANON="$WORK/canon.tsv"
extract_body "$AGENTS_MD" '| Agent | Tier | Domain | Use when |' | cells_tsv \
  | awk -F'\t' '{ n=$1; gsub(/`/,"",n); print n "\t" $2 "\t" $3 "\t" $4 }' > "$CANON"

if [ ! -s "$CANON" ]; then
  fatal "catalog" "no agent rows parsed from AGENTS.md — check the 'Available Agents' table header" 2
fi

# --- CHECK MODE -------------------------------------------------------------

# Presence: AGENTS.md names vs agents/*.md wrapper files.
canon_names="$WORK/canon.names"; cut -f1 "$CANON" | sort > "$canon_names"
wrapper_names="$WORK/wrapper.names"
: > "$WORK/wrapper.models"   # name <tab> model
for f in "$AGENTS_DIR"/*.md; do
  [ -f "$f" ] || continue
  nm="$(basename "$f" .md)"
  printf '%s\n' "$nm"
  md="$(awk '
    NR==1 && /^---[[:space:]]*$/ { fm=1; next }
    fm==1 && /^---[[:space:]]*$/ { exit }
    fm==1 && /^model:/ { sub(/^model:[ \t]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); gsub(/\r/,""); print; exit }
  ' "$f")"
  printf '%s\t%s\n' "$nm" "$md" >> "$WORK/wrapper.models"
done | sort > "$wrapper_names"

while IFS= read -r nm; do
  [ -z "$nm" ] && continue
  grep -qxF "$nm" "$wrapper_names" || err "catalog" "AGENTS.md lists '$nm' but agents/${nm}.md not found"
done < "$canon_names"

while IFS= read -r nm; do
  [ -z "$nm" ] && continue
  grep -qxF "$nm" "$canon_names" || warn "catalog" "agents/${nm}.md exists but is not listed in AGENTS.md"
done < "$wrapper_names"

# Routing rule: must carry the pointer to AGENTS.md, not a table copy.
# A reintroduced '| Agent | Domain | Use when |' table is the drift this
# guards against (ADR-085 retired the generated mirror).
check_routing_pointer() {
  local file="$1" label="$2"
  [ -f "$file" ] || { err "$label" "routing rule not found: $file"; return; }
  if grep -q '^| Agent | Domain | Use when |' "$file"; then
    err "$label" "catalog table reintroduced in ${file##*/} — the mirror was retired (ADR-085); AGENTS.md is the only catalog copy"
    return
  fi
  if ! grep -q 'Available Agents' "$file"; then
    err "$label" "${file##*/} no longer points at AGENTS.md's Available Agents table — restore the pointer (ADR-085)"
    return
  fi
  ok "$label" "pointer to AGENTS.md present; no table copy"
}
check_routing_pointer "$ROUTING_RULE" "routing-rule"

# README "Current Agents": Tier vs canonical, Model vs wrapper frontmatter.
if [ -f "$README_MD" ]; then
  readme_tsv="$WORK/readme.tsv"   # name <tab> model <tab> tier
  extract_body "$README_MD" '| Agent | Model | Tier | Description |' | cells_tsv \
    | awk -F'\t' '{ n=$1; gsub(/`/,"",n); print n "\t" $2 "\t" $3 }' > "$readme_tsv"
  # Loud empty-extraction guard (#28): a drifted/reformatted README header
  # yields zero rows here, and the drift awk below would then report zero
  # findings — indistinguishable from "checked, no drift". Same failure class
  # the CANON guard above already covers for AGENTS.md.
  if [ ! -s "$readme_tsv" ]; then
    err "catalog" "no rows parsed from README 'Current Agents' table — check the '| Agent | Model | Tier | Description |' header (README Tier/Model drift check skipped)"
  else
  awk -F'\t' -v canon="$CANON" -v models="$WORK/wrapper.models" '
    BEGIN{
      while ((getline l < canon)>0){ split(l,a,"\t"); ctier[a[1]]=a[2]; cseen[a[1]]=1 } close(canon)
      while ((getline m < models)>0){ split(m,b,"\t"); wmodel[b[1]]=b[2] } close(models)
    }
    { rmodel[$1]=$2; rtier[$1]=$3; rseen[$1]=1 }
    END{
      for (n in cseen){
        if(!(n in rseen)) continue   # README presence handled by check_readme_catalog (warn)
        if(rtier[n]!=ctier[n]) print "README Tier drift for " n ": AGENTS.md=[" ctier[n] "] README=[" rtier[n] "]"
        if((n in wmodel) && wmodel[n]!="" && rmodel[n]!=wmodel[n]) print "README Model drift for " n ": frontmatter=[" wmodel[n] "] README=[" rmodel[n] "]"
      }
    }' "$readme_tsv" > "$WORK/readme.drift"
  LC_ALL=C sort "$WORK/readme.drift" > "$WORK/readme.drift.sorted"
  while IFS= read -r msg; do
    [ -n "$msg" ] && err "catalog" "$msg"
  done < "$WORK/readme.drift.sorted"
  fi
else
  warn "catalog" "README.md not found — skipping README Tier/Model checks"
fi

if [ "${LOG_ERROR_COUNT:-0}" -eq 0 ]; then
  ok "catalog" "agent catalog consistent ($(wc -l < "$CANON" | tr -d ' ') agents; AGENTS.md canonical)"
fi
print_summary
exit $?
