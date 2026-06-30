#!/usr/bin/env bash
#
# scripts/wim/create-epic.sh — frozen, parameterized Epic creation.
#
# Do not edit. SHA-pinned in scripts/wim/.frozen-shas.
# See agents/work-item-management-expert.md "Frozen Work-Item Scripts".
#
# Usage:
#   create-epic.sh --backend ado    [ado flags]    --title <t> [--description <d>] ...
#   create-epic.sh --backend github [github flags] --title <t> [--description <d>] ...
#
# Stdout: the created (or reused) item ID — single line.
# Stderr: OK/SKIP/ERROR labels per rules/script-output-conventions.md.
#
# Exit codes:
#   0 — created or reused
#   1 — backend failure
#   2 — usage / missing dependency
#

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$LIB_DIR/_lib.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: create-epic.sh --backend ado|github [flags] --title <t>

Common:
  --backend ado|github                 Required.
  --title <t>                          Required.
  --description <text>                 Optional. HTML for ADO; Markdown body for GitHub.

ADO (--backend ado):
  --organization <url>                 Required.
  --project <name>                     Required.
  --area <Project\Area>                Required.
  --iteration <Project\Iter>           Required.
  --tags <tag1; tag2>                  Optional.
  --priority <1-4>                     Optional (default: 2).
  --business-value <int>               Optional.

GitHub (--backend github):
  --repo <owner/repo>                  Required.
  --org <login>                        Optional. Required to set Issue Type via GraphQL.
  --labels <a,b,c>                     Optional. Always appended with type/epic.
  --milestone <title>                  Optional.
  --gh-project <project-title>         Optional.
USAGE
  exit 2
}

main() {
  local backend="" title="" description=""
  local ado_org="" ado_project="" ado_area="" ado_iteration="" ado_tags=""
  local ado_priority="2" ado_business_value=""
  local gh_repo="" gh_org="" gh_labels="" gh_milestone="" gh_project=""

  while (( $# > 0 )); do
    case "$1" in
      --backend)         backend="$2"; shift 2 ;;
      --title)           title="$2"; shift 2 ;;
      --description)     description="$2"; shift 2 ;;
      --organization)    ado_org="$2"; shift 2 ;;
      --project)         ado_project="$2"; shift 2 ;;
      --area)            ado_area="$2"; shift 2 ;;
      --iteration)       ado_iteration="$2"; shift 2 ;;
      --tags)            ado_tags="$2"; shift 2 ;;
      --priority)        ado_priority="$2"; shift 2 ;;
      --business-value)  ado_business_value="$2"; shift 2 ;;
      --repo)            gh_repo="$2"; shift 2 ;;
      --org)             gh_org="$2"; shift 2 ;;
      --labels)          gh_labels="$2"; shift 2 ;;
      --milestone)       gh_milestone="$2"; shift 2 ;;
      --gh-project)      gh_project="$2"; shift 2 ;;
      -h|--help)         usage ;;
      *) die "args" "unknown flag: $1" 2 ;;
    esac
  done

  [[ -n "$backend" ]] || die "args" "missing --backend" 2
  [[ -n "$title" ]]   || die "args" "missing --title" 2

  case "$backend" in
    ado)     create_ado "$title" "$description" "$ado_org" "$ado_project" \
                        "$ado_area" "$ado_iteration" "$ado_tags" \
                        "$ado_priority" "$ado_business_value" ;;
    github)  create_gh  "$title" "$description" "$gh_repo" "$gh_org" \
                        "$gh_labels" "$gh_milestone" "$gh_project" ;;
    *)       die "args" "unknown --backend '$backend' (expected ado|github)" 2 ;;
  esac
}

create_ado() {
  local title="$1" desc="$2" org="$3" project="$4" area="$5" iter="$6"
  local tags="$7" priority="$8" biz_value="$9"

  [[ -n "$org" ]]     || die "args" "ado: missing --organization" 2
  [[ -n "$project" ]] || die "args" "ado: missing --project" 2
  [[ -n "$area" ]]    || die "args" "ado: missing --area" 2
  [[ -n "$iter" ]]    || die "args" "ado: missing --iteration" 2

  require_cmd az
  require_cmd jq

  az devops configure --defaults organization="$org" project="$project" >/dev/null

  local existing
  existing=$(ado_search_by_title "Epic" "$title" "$area")
  if [[ -n "$existing" ]]; then
    skip "epic" "already exists id=$existing — reusing" >&2
    echo "$existing"
    return 0
  fi

  local extra=( "Microsoft.VSTS.Common.Priority=$priority" )
  [[ -n "$biz_value" ]] && extra+=( "Microsoft.VSTS.Common.BusinessValue=$biz_value" )

  local new_id
  new_id=$(ado_create_work_item "Epic" "$title" "${desc:-<p></p>}" "$area" "$iter" "$tags" "${extra[@]}")
  ok "epic" "created id=$new_id" >&2
  echo "$new_id"
}

create_gh() {
  local title="$1" desc="$2" repo="$3" org="$4" labels="$5" milestone="$6" project="$7"

  [[ -n "$repo" ]] || die "args" "github: missing --repo" 2

  require_cmd gh
  require_cmd jq

  local existing
  existing=$(gh_search_by_title "$repo" "$title")
  if [[ -n "$existing" ]]; then
    skip "epic" "already exists number=$existing — reusing" >&2
    echo "$existing"
    return 0
  fi

  local effective_labels
  if [[ -n "$labels" ]]; then
    effective_labels="${labels},type/epic"
  else
    effective_labels="type/epic"
  fi

  local meta
  meta=$(gh_create_issue "$repo" "$title" "${desc:-No description provided.}" \
                         "$effective_labels" "$milestone" "$project")
  local number node_id
  number=$(printf '%s' "$meta" | cut -f1)
  node_id=$(printf '%s' "$meta" | cut -f2)

  if [[ -n "$org" ]]; then
    gh_set_issue_type "$node_id" "$org" "Epic" || true
  fi

  ok "epic" "created number=$number" >&2
  echo "$number"
}

main "$@"
