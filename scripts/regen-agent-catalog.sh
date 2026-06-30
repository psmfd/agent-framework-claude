#!/usr/bin/env bash
# Agent Framework — Agent Catalog Drift Gate / Regenerator
#
# AGENTS.md "Available Agents" is the canonical source for each agent's
# Tier / Domain / Use-when. This script keeps the downstream catalogs
# consistent with it (see ADR-062):
#
#   --check  (default)  Detect drift; write nothing; exit non-zero on drift.
#                       Wired into validate.sh as a blocking check.
#   --write             Regenerate the same-schema routing mirror
#                       (rules/agent-first-selection.md)
#                       from AGENTS.md, in place (order-preserving merge).
#   -h, --help          Print this help and exit.
#
# What --check verifies (keyed by agent name):
#   - every AGENTS.md agent has agents/<name>.md            (error if missing)
#   - every agents/<name>.md appears in AGENTS.md           (warn if missing)
#   - Domain + Use-when match across AGENTS.md and the routing mirror   (error)
#   - README "Current Agents" Tier matches AGENTS.md, and Model matches each
#     wrapper's `model:` frontmatter                        (error on drift)
#
# Out of scope (intentionally divergent): README Description column, and the
# web/instructions.md Agent Catalog (condensed; covered by the web-sync check).
#
# Exit codes:
#   0  no drift (--check) / regenerated cleanly (--write)
#   1  drift detected (--check) / write failed
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

MODE="check"
case "${1:-}" in
  --check|"") MODE="check" ;;
  --write)    MODE="write" ;;
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
extract_body() {
  awk -v h="$2" '
    index($0,h)==1         { st=1; next }
    st==1 && /^\|[[:space:]]*-/ { st=2; next }
    st==2 && (/^[[:space:]]*$/ || /^#/) { exit }
    st==2                  { print }
  ' "$1"
}

# Read raw table rows on stdin; emit tab-separated trimmed cells (backticks
# preserved). A leading/trailing pipe yields empty edge fields, dropped here.
cells_tsv() {
  awk -F'|' '
    function trim(s){ sub(/^[ \t\r]+/,"",s); sub(/[ \t\r]+$/,"",s); return s }
    {
      out=""
      for (i=2; i<NF; i++) out = out (i>2 ? "\t" : "") trim($i)
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

# --- WRITE MODE -------------------------------------------------------------
# Order-preserving merge: refresh each routing row's Domain+Use-when from the
# canonical map, keyed by name; append canonical agents missing from the file;
# drop (with a warning) rows whose agent is absent from AGENTS.md.
write_routing() {
  local file="$1" label="$2"
  [ -f "$file" ] || { warn "$label" "not found: $file"; return; }
  local out="$file.regen.$$"
  awk -F'\t' -v canon="$CANON" '
    function trim(s){ sub(/^[ \t\r]+/,"",s); sub(/[ \t\r]+$/,"",s); return s }
    BEGIN{
      while ((getline line < canon) > 0) {
        nf=split(line, a, "\t"); cdom[a[1]]=a[3]; cuw[a[1]]=a[4]; seenc[a[1]]=1
        order[++n]=a[1]
      }
      close(canon)
    }
    # passthrough until table header
    st==0 && /^\| Agent \| Domain \| Use when \|/ { print; st=1; next }
    st==1 && /^\|[[:space:]]*-/ { print; st=2; next }
    st==2 && (/^[[:space:]]*$/ || /^#/) {
      # flush canonical agents not already emitted, in canonical order
      for (i=1;i<=n;i++){ nm=order[i]; if(!(nm in emitted)) printf "| `%s` | %s | %s |\n", nm, cdom[nm], cuw[nm] }
      print; st=3; next
    }
    st==2 {
      line=$0; nfields=split(line, c, "|"); nm=trim(c[2]); gsub(/`/,"",nm)
      if (nm in seenc) { printf "| `%s` | %s | %s |\n", nm, cdom[nm], cuw[nm]; emitted[nm]=1 }
      else { print "DROP\t" nm > "/dev/stderr" }   # stray row: drop + signal
      next
    }
    { print }
    END {
      if (st==2) { for (i=1;i<=n;i++){ nm=order[i]; if(!(nm in emitted)) printf "| `%s` | %s | %s |\n", nm, cdom[nm], cuw[nm] } }
    }
  ' "$file" > "$out" 2> "$WORK/dropped.$$" || { rm -f "$out"; err "$label" "awk regen failed"; return; }

  while IFS=$'\t' read -r tag nm; do
    [ "$tag" = "DROP" ] && warn "$label" "dropped stray row '$nm' (not in AGENTS.md)"
  done < "$WORK/dropped.$$"

  if cmp -s "$file" "$out"; then
    ok "$label" "already in sync with AGENTS.md"
    rm -f "$out"
  else
    mv "$out" "$file"
    info "[$label] regenerated from AGENTS.md (canonical)"
  fi
}

if [ "$MODE" = "write" ]; then
  write_routing "$ROUTING_RULE"    "routing-rule"
  info "README and web/instructions.md are intentionally divergent — not regenerated (run --check to verify Tier/Model)"
  print_summary
  exit $?
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

# Routing mirrors: name-presence + Domain/Use-when content parity.
check_routing() {
  local file="$1" label="$2"
  [ -f "$file" ] || { err "$label" "routing catalog not found: $file"; return; }
  local subj="$WORK/${label}.tsv"
  extract_body "$file" '| Agent | Domain | Use when |' | cells_tsv \
    | awk -F'\t' '{ n=$1; gsub(/`/,"",n); print n "\t" $2 "\t" $3 }' > "$subj"
  awk -F'\t' -v canon="$CANON" -v label="$label" '
    BEGIN{ while ((getline l < canon)>0){ split(l,a,"\t"); cdom[a[1]]=a[3]; cuw[a[1]]=a[4]; cseen[a[1]]=1 } close(canon) }
    { rdom[$1]=$2; ruw[$1]=$3; rseen[$1]=1 }
    END{
      for (n in cseen){
        if(!(n in rseen)){ print "ERR\t" label "\t" n " missing from routing catalog"; continue }
        if(cdom[n]!=rdom[n]) print "ERR\t" label "\t" n " Domain drift: AGENTS.md=[" cdom[n] "] catalog=[" rdom[n] "]"
        if(cuw[n]!=ruw[n])   print "ERR\t" label "\t" n " Use-when drift vs AGENTS.md"
      }
      for (n in rseen) if(!(n in cseen)) print "ERR\t" label "\t" n " listed in routing catalog but not in AGENTS.md"
    }' "$subj" > "$WORK/${label}.drift"
  # Read in the current shell (not a pipe subshell) so err() counters propagate.
  LC_ALL=C sort "$WORK/${label}.drift" > "$WORK/${label}.drift.sorted"
  while IFS=$'\t' read -r tag lbl msg; do
    [ -n "$tag" ] && err "$lbl" "$msg"
  done < "$WORK/${label}.drift.sorted"
}
check_routing "$ROUTING_RULE"    "routing-rule"

# README "Current Agents": Tier vs canonical, Model vs wrapper frontmatter.
if [ -f "$README_MD" ]; then
  readme_tsv="$WORK/readme.tsv"   # name <tab> model <tab> tier
  extract_body "$README_MD" '| Agent | Model | Tier | Description |' | cells_tsv \
    | awk -F'\t' '{ n=$1; gsub(/`/,"",n); print n "\t" $2 "\t" $3 }' > "$readme_tsv"
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
else
  warn "catalog" "README.md not found — skipping README Tier/Model checks"
fi

if [ "${LOG_ERROR_COUNT:-0}" -eq 0 ]; then
  ok "catalog" "agent catalog consistent ($(wc -l < "$CANON" | tr -d ' ') agents; AGENTS.md canonical)"
fi
print_summary
exit $?
