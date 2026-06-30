#!/usr/bin/env bash
#
# scripts/wim/create-feature.sh — frozen, parameterized Feature creation.
#
# Do not edit. SHA-pinned in scripts/wim/.frozen-shas.
# See agents/work-item-management-expert.md "Frozen Work-Item Scripts".
#
# Usage:
#   create-feature.sh --backend ado    [ado flags]    --parent-id <epic-id>    --title <t> ...
#   create-feature.sh --backend github [github flags] --parent-id <epic-num>   --title <t> ...
#
# Stdout: the created (or reused) item ID — single line.
# Stderr: OK/SKIP/ERROR labels per rules/script-output-conventions.md.
#

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$LIB_DIR/_lib.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: create-feature.sh --backend ado|github --parent-id <id> --title <t> [flags]

Common:
  --backend ado|github                 Required.
  --parent-id <id>                     Required. ADO: integer Epic ID. GitHub: integer Epic issue number.
  --title <t>                          Required.
  --description <text>                 Optional.

ADO (--backend ado):
  --organization <url>                 Required.
  --project <name>                     Required.
  --area <Project\Area>                Required.
  --iteration <Project\Iter>           Required.
  --tags <tag1; tag2>                  Optional.
  --priority <1-4>                     Optional (default: 2).
  --value-area Business|Architectural  Optional.

GitHub (--backend github):
  --repo <owner/repo>                  Required.
  --org <login>                        Optional. Required for Issue Type via GraphQL.
  --labels <a,b,c>                     Optional. Always appended with type/feature.
  --milestone <title>                  Optional.
  --gh-project <project-title>         Optional.
USAGE
  exit 2
}

main() {
  local backend="" title="" description="" parent_id=""
  local ado_org="" ado_project="" ado_area="" ado_iteration="" ado_tags=""
  local ado_priority="2" ado_value_area=""
  local gh_repo="" gh_org="" gh_labels="" gh_milestone="" gh_project=""

  while (( $# > 0 )); do
    case "$1" in
      --backend)         backend="$2"; shift 2 ;;
      --title)           title="$2"; shift 2 ;;
      --description)     description="$2"; shift 2 ;;
      --parent-id)       parent_id="$2"; shift 2 ;;
      --organization)    ado_org="$2"; shift 2 ;;
      --project)         ado_project="$2"; shift 2 ;;
      --area)            ado_area="$2"; shift 2 ;;
      --iteration)       ado_iteration="$2"; shift 2 ;;
      --tags)            ado_tags="$2"; shift 2 ;;
      --priority)        ado_priority="$2"; shift 2 ;;
      --value-area)      ado_value_area="$2"; shift 2 ;;
      --repo)            gh_repo="$2"; shift 2 ;;
      --org)             gh_org="$2"; shift 2 ;;
      --labels)          gh_labels="$2"; shift 2 ;;
      --milestone)       gh_milestone="$2"; shift 2 ;;
      --gh-project)      gh_project="$2"; shift 2 ;;
      -h|--help)         usage ;;
      *) die "args" "unknown flag: $1" 2 ;;
    esac
  done

  [[ -n "$backend" ]]   || die "args" "missing --backend" 2
  [[ -n "$title" ]]     || die "args" "missing --title" 2
  [[ -n "$parent_id" ]] || die "args" "missing --parent-id" 2

  case "$backend" in
    ado)    create_ado "$title" "$description" "$parent_id" \
                       "$ado_org" "$ado_project" "$ado_area" "$ado_iteration" \
                       "$ado_tags" "$ado_priority" "$ado_value_area" ;;
    github) create_gh  "$title" "$description" "$parent_id" \
                       "$gh_repo" "$gh_org" "$gh_labels" "$gh_milestone" "$gh_project" ;;
    *)      die "args" "unknown --backend '$backend' (expected ado|github)" 2 ;;
  esac
}

create_ado() {
  local title="$1" desc="$2" parent_id="$3"
  local org="$4" project="$5" area="$6" iter="$7"
  local tags="$8" priority="$9" value_area="${10}"

  [[ -n "$org" ]]     || die "args" "ado: missing --organization" 2
  [[ -n "$project" ]] || die "args" "ado: missing --project" 2
  [[ -n "$area" ]]    || die "args" "ado: missing --area" 2
  [[ -n "$iter" ]]    || die "args" "ado: missing --iteration" 2

  require_cmd az
  require_cmd jq

  az devops configure --defaults organization="$org" project="$project" >/dev/null

  local existing
  existing=$(ado_search_by_title "Feature" "$title" "$area")
  if [[ -n "$existing" ]]; then
    skip "feature" "already exists id=$existing — reusing (parent link not re-applied)" >&2
    echo "$existing"
    return 0
  fi

  local extra=( "Microsoft.VSTS.Common.Priority=$priority" )
  [[ -n "$value_area" ]] && extra+=( "Microsoft.VSTS.Common.ValueArea=$value_area" )

  local new_id
  new_id=$(ado_create_work_item "Feature" "$title" "${desc:-<p></p>}" "$area" "$iter" "$tags" "${extra[@]}")

  ado_link_parent "$new_id" "$parent_id"
  ok "feature" "created id=$new_id parent=$parent_id" >&2
  echo "$new_id"
}

create_gh() {
  local title="$1" desc="$2" parent_id="$3"
  local repo="$4" org="$5" labels="$6" milestone="$7" project="$8"

  [[ -n "$repo" ]] || die "args" "github: missing --repo" 2

  require_cmd gh
  require_cmd jq

  local existing
  existing=$(gh_search_by_title "$repo" "$title")
  if [[ -n "$existing" ]]; then
    skip "feature" "already exists number=$existing — reusing (parent link not re-applied)" >&2
    echo "$existing"
    return 0
  fi

  local effective_labels
  if [[ -n "$labels" ]]; then
    effective_labels="${labels},type/feature"
  else
    effective_labels="type/feature"
  fi

  local meta
  meta=$(gh_create_issue "$repo" "$title" "${desc:-No description provided.}" \
                         "$effective_labels" "$milestone" "$project")
  local number node_id
  number=$(printf '%s' "$meta" | cut -f1)
  node_id=$(printf '%s' "$meta" | cut -f2)

  if [[ -n "$org" ]]; then
    gh_set_issue_type "$node_id" "$org" "Feature" || true
  fi

  gh_link_subissue "$repo" "$parent_id" "$number" || true
  ok "feature" "created number=$number parent=$parent_id" >&2
  echo "$number"
}

main "$@"
