#!/usr/bin/env bash
#
# scripts/wim/create-user-story.sh — frozen, parameterized User Story creation.
#
# Do not edit. SHA-pinned in scripts/wim/.frozen-shas.
# See agents/work-item-management-expert.md "Frozen Work-Item Scripts".
#
# Usage:
#   create-user-story.sh --backend ado    [ado flags]    --parent-id <feat-id>  --title <t> ...
#   create-user-story.sh --backend github [github flags] --parent-id <feat-num> --title <t> ...
#
# AcceptanceCriteria:
#   ADO:    Markdown checklist/paragraphs are converted to HTML and stored in
#           Microsoft.VSTS.Common.AcceptanceCriteria.
#   GitHub: rendered as a "## Acceptance Criteria" section appended to the body.
#
# Stdout: the created (or reused) item ID — single line.
#

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$LIB_DIR/_lib.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: create-user-story.sh --backend ado|github --parent-id <id> --title <t> [flags]

Common:
  --backend ado|github                 Required.
  --parent-id <id>                     Required. ADO: integer Feature ID. GitHub: integer Feature issue number.
  --title <t>                          Required.
  --description <text>                 Optional.
  --acceptance-criteria <md>           Optional. Markdown — checklist or paragraphs.

ADO (--backend ado):
  --organization <url>                 Required.
  --project <name>                     Required.
  --process agile|scrum|cmmi           Required. Selects effort field reference name.
  --area <Project\Area>                Required.
  --iteration <Project\Iter>           Required.
  --tags <tag1; tag2>                  Optional.
  --priority <1-4>                     Optional (default: 2).
  --story-points <n>                   Optional. Mapped to StoryPoints (agile) / Effort (scrum) / Size (cmmi).
  --assigned-to <upn>                  Optional.

GitHub (--backend github):
  --repo <owner/repo>                  Required.
  --org <login>                        Optional. Required for Issue Type via GraphQL.
  --labels <a,b,c>                     Optional. Always appended with type/story.
  --milestone <title>                  Optional.
  --gh-project <project-title>         Optional.
  --assignees <a,b,c>                  Optional.
USAGE
  exit 2
}

main() {
  local backend="" title="" description="" acceptance="" parent_id=""
  local ado_org="" ado_project="" ado_process="" ado_area="" ado_iteration=""
  local ado_tags="" ado_priority="2" ado_story_points="" ado_assigned_to=""
  local gh_repo="" gh_org="" gh_labels="" gh_milestone="" gh_project="" gh_assignees=""

  while (( $# > 0 )); do
    case "$1" in
      --backend)              backend="$2"; shift 2 ;;
      --title)                title="$2"; shift 2 ;;
      --description)          description="$2"; shift 2 ;;
      --acceptance-criteria)  acceptance="$2"; shift 2 ;;
      --parent-id)            parent_id="$2"; shift 2 ;;
      --organization)         ado_org="$2"; shift 2 ;;
      --project)              ado_project="$2"; shift 2 ;;
      --process)              ado_process="$2"; shift 2 ;;
      --area)                 ado_area="$2"; shift 2 ;;
      --iteration)            ado_iteration="$2"; shift 2 ;;
      --tags)                 ado_tags="$2"; shift 2 ;;
      --priority)             ado_priority="$2"; shift 2 ;;
      --story-points)         ado_story_points="$2"; shift 2 ;;
      --assigned-to)          ado_assigned_to="$2"; shift 2 ;;
      --repo)                 gh_repo="$2"; shift 2 ;;
      --org)                  gh_org="$2"; shift 2 ;;
      --labels)               gh_labels="$2"; shift 2 ;;
      --milestone)            gh_milestone="$2"; shift 2 ;;
      --gh-project)           gh_project="$2"; shift 2 ;;
      --assignees)            gh_assignees="$2"; shift 2 ;;
      -h|--help)              usage ;;
      *) die "args" "unknown flag: $1" 2 ;;
    esac
  done

  [[ -n "$backend" ]]   || die "args" "missing --backend" 2
  [[ -n "$title" ]]     || die "args" "missing --title" 2
  [[ -n "$parent_id" ]] || die "args" "missing --parent-id" 2

  case "$backend" in
    ado)    create_ado "$title" "$description" "$acceptance" "$parent_id" \
                       "$ado_org" "$ado_project" "$ado_process" "$ado_area" "$ado_iteration" \
                       "$ado_tags" "$ado_priority" "$ado_story_points" "$ado_assigned_to" ;;
    github) create_gh  "$title" "$description" "$acceptance" "$parent_id" \
                       "$gh_repo" "$gh_org" "$gh_labels" "$gh_milestone" "$gh_project" "$gh_assignees" ;;
    *)      die "args" "unknown --backend '$backend' (expected ado|github)" 2 ;;
  esac
}

create_ado() {
  local title="$1" desc="$2" acceptance_md="$3" parent_id="$4"
  local org="$5" project="$6" process="$7" area="$8" iter="$9"
  local tags="${10}" priority="${11}" story_points="${12}" assigned_to="${13}"

  [[ -n "$org" ]]     || die "args" "ado: missing --organization" 2
  [[ -n "$project" ]] || die "args" "ado: missing --project" 2
  [[ -n "$process" ]] || die "args" "ado: missing --process" 2
  [[ -n "$area" ]]    || die "args" "ado: missing --area" 2
  [[ -n "$iter" ]]    || die "args" "ado: missing --iteration" 2

  local effort_field
  effort_field=$(ado_effort_field "$process") || die "args" "ado: --process must be one of: agile, scrum, cmmi" 2

  require_cmd az
  require_cmd jq
  require_cmd python3

  az devops configure --defaults organization="$org" project="$project" >/dev/null

  local existing
  existing=$(ado_search_by_title "User Story" "$title" "$area")
  if [[ -n "$existing" ]]; then
    skip "story" "already exists id=$existing — reusing (parent link not re-applied)" >&2
    echo "$existing"
    return 0
  fi

  local extra=( "Microsoft.VSTS.Common.Priority=$priority" )
  if [[ -n "$story_points" ]]; then
    extra+=( "${effort_field}=${story_points}" )
  fi
  if [[ -n "$assigned_to" ]]; then
    extra+=( "System.AssignedTo=${assigned_to}" )
  fi
  if [[ -n "$acceptance_md" ]]; then
    local ac_html
    ac_html=$(printf '%s' "$acceptance_md" | md_to_ado_html)
    extra+=( "Microsoft.VSTS.Common.AcceptanceCriteria=${ac_html}" )
  fi

  local new_id
  new_id=$(ado_create_work_item "User Story" "$title" "${desc:-<p></p>}" "$area" "$iter" "$tags" "${extra[@]}")
  ado_link_parent "$new_id" "$parent_id"
  ok "story" "created id=$new_id parent=$parent_id" >&2
  echo "$new_id"
}

create_gh() {
  local title="$1" desc="$2" acceptance_md="$3" parent_id="$4"
  local repo="$5" org="$6" labels="$7" milestone="$8" project="$9" assignees="${10}"

  [[ -n "$repo" ]] || die "args" "github: missing --repo" 2

  require_cmd gh
  require_cmd jq

  local existing
  existing=$(gh_search_by_title "$repo" "$title")
  if [[ -n "$existing" ]]; then
    skip "story" "already exists number=$existing — reusing (parent link not re-applied)" >&2
    echo "$existing"
    return 0
  fi

  local body="${desc:-No description provided.}"
  if [[ -n "$acceptance_md" ]]; then
    body="${body}"$'\n\n## Acceptance Criteria\n\n'"${acceptance_md}"
  fi

  local effective_labels
  if [[ -n "$labels" ]]; then
    effective_labels="${labels},type/story"
  else
    effective_labels="type/story"
  fi

  local cmd=( gh issue create --repo "$repo" --title "$title" --body "$body"
              --label "$effective_labels" )
  [[ -n "$milestone" ]] && cmd+=( --milestone "$milestone" )
  [[ -n "$project" ]]   && cmd+=( --project "$project" )
  if [[ -n "$assignees" ]]; then
    local a
    IFS=',' read -ra a <<< "$assignees"
    for u in "${a[@]}"; do cmd+=( --assignee "$u" ); done
  fi

  local url
  url=$("${cmd[@]}" 2>&1) || die "gh-create" "gh issue create '$title' failed: $url"
  url="${url##*$'\n'}"

  local meta number node_id
  meta=$(gh issue view "$url" --json number,id 2>&1) || die "gh-view" "gh issue view '$url' failed: $meta"
  number=$(echo "$meta" | jq -r '.number')
  node_id=$(echo "$meta" | jq -r '.id')

  if [[ -n "$org" ]]; then
    gh_set_issue_type "$node_id" "$org" "User Story" || true
  fi

  gh_link_subissue "$repo" "$parent_id" "$number" || true
  ok "story" "created number=$number parent=$parent_id" >&2
  echo "$number"
}

main "$@"
