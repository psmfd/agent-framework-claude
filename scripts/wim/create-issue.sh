#!/usr/bin/env bash
#
# scripts/wim/create-issue.sh — frozen, parameterized standalone-issue creation.
#
# Creates a single issue OUTSIDE the Epic -> Feature -> Story hierarchy. Unlike
# create-epic.sh / create-feature.sh / create-user-story.sh, it injects no
# type/* label (GitHub) and takes an explicit --type (ADO), so a standalone
# issue can carry any type (e.g. a bug). No parent link is created.
#
# Do not edit. SHA-pinned in scripts/wim/.frozen-shas.
# See agents/work-item-management-expert.md "Frozen Work-Item Scripts".
#
# Usage:
#   create-issue.sh --backend ado    [ado flags]    --title <t> [--description <d>] ...
#   create-issue.sh --backend github [github flags] --title <t> [--description <d>] ...
#
# Stdout: the created (or reused) item ID/number — single line.
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
Usage: create-issue.sh --backend ado|github [flags] --title <t>

Creates a standalone issue (no parent, no auto type/* label).

Common:
  --backend ado|github                 Required.
  --title <t>                          Required.
  --description <text>                 Optional. HTML for ADO; Markdown body for GitHub.
  --acceptance-criteria <md>           Optional. Markdown; ADO AcceptanceCriteria field / GitHub body section.

ADO (--backend ado):
  --organization <url>                 Required.
  --project <name>                     Required.
  --area <Project\Area>                Required.
  --iteration <Project\Iter>           Required.
  --type <display-name>                Optional (default: Issue). e.g. Bug, Task, Issue.
  --tags <tag1; tag2>                  Optional.
  --priority <1-4>                     Optional.
  --severity <"2 - High">              Optional. Microsoft.VSTS.Common.Severity (Bug type).
  --assigned-to <user>                 Optional.

GitHub (--backend github):
  --repo <owner/repo>                  Required.
  --org <login>                        Optional. Required to set Issue Type via GraphQL.
  --issue-type <name>                  Optional. GraphQL Issue Type name (org-configured).
  --labels <a,b,c>                     Optional. Applied verbatim — no type/* auto-label.
  --milestone <title>                  Optional.
  --gh-project <project-title>         Optional.
  --assignees <a,b>                    Optional.
USAGE
  exit 2
}

main() {
  local backend="" title="" description="" acceptance=""
  local ado_org="" ado_project="" ado_area="" ado_iteration="" ado_type="Issue"
  local ado_tags="" ado_priority="" ado_severity="" ado_assigned=""
  local gh_repo="" gh_org="" gh_issue_type="" gh_labels="" gh_milestone="" gh_project="" gh_assignees=""

  while (( $# > 0 )); do
    case "$1" in
      --backend)             backend="$2"; shift 2 ;;
      --title)               title="$2"; shift 2 ;;
      --description)         description="$2"; shift 2 ;;
      --acceptance-criteria) acceptance="$2"; shift 2 ;;
      --organization)        ado_org="$2"; shift 2 ;;
      --project)             ado_project="$2"; shift 2 ;;
      --area)                ado_area="$2"; shift 2 ;;
      --iteration)           ado_iteration="$2"; shift 2 ;;
      --type)                ado_type="$2"; shift 2 ;;
      --tags)                ado_tags="$2"; shift 2 ;;
      --priority)            ado_priority="$2"; shift 2 ;;
      --severity)            ado_severity="$2"; shift 2 ;;
      --assigned-to)         ado_assigned="$2"; shift 2 ;;
      --repo)                gh_repo="$2"; shift 2 ;;
      --org)                 gh_org="$2"; shift 2 ;;
      --issue-type)          gh_issue_type="$2"; shift 2 ;;
      --labels)              gh_labels="$2"; shift 2 ;;
      --milestone)           gh_milestone="$2"; shift 2 ;;
      --gh-project)          gh_project="$2"; shift 2 ;;
      --assignees)           gh_assignees="$2"; shift 2 ;;
      -h|--help)             usage ;;
      *) die "args" "unknown flag: $1" 2 ;;
    esac
  done

  [[ -n "$backend" ]] || die "args" "missing --backend" 2
  [[ -n "$title" ]]   || die "args" "missing --title" 2

  case "$backend" in
    ado)     create_ado ;;
    github)  create_gh ;;
    *)       die "args" "unknown --backend '$backend' (expected ado|github)" 2 ;;
  esac
}

create_ado() {
  [[ -n "$ado_org" ]]      || die "args" "ado: missing --organization" 2
  [[ -n "$ado_project" ]]  || die "args" "ado: missing --project" 2
  [[ -n "$ado_area" ]]     || die "args" "ado: missing --area" 2
  [[ -n "$ado_iteration" ]] || die "args" "ado: missing --iteration" 2

  require_cmd az
  require_cmd jq

  az devops configure --defaults organization="$ado_org" project="$ado_project" >/dev/null

  local existing
  existing=$(ado_search_by_title "$ado_type" "$title" "$ado_area")
  if [[ -n "$existing" ]]; then
    skip "issue" "already exists id=$existing — reusing" >&2
    echo "$existing"
    return 0
  fi

  local desc_html="${description:-<p></p>}"
  local extra=()
  [[ -n "$ado_priority" ]] && extra+=( "Microsoft.VSTS.Common.Priority=$ado_priority" )
  [[ -n "$ado_severity" ]] && extra+=( "Microsoft.VSTS.Common.Severity=$ado_severity" )
  [[ -n "$ado_assigned" ]] && extra+=( "System.AssignedTo=$ado_assigned" )
  if [[ -n "$acceptance" ]]; then
    local ac_html
    ac_html=$(printf '%s' "$acceptance" | md_to_ado_html)
    extra+=( "Microsoft.VSTS.Common.AcceptanceCriteria=$ac_html" )
  fi

  local new_id
  new_id=$(ado_create_work_item "$ado_type" "$title" "$desc_html" "$ado_area" "$ado_iteration" "$ado_tags" "${extra[@]}")
  ok "issue" "created id=$new_id type='$ado_type'" >&2
  echo "$new_id"
}

create_gh() {
  [[ -n "$gh_repo" ]] || die "args" "github: missing --repo" 2

  require_cmd gh
  require_cmd jq

  local existing
  existing=$(gh_search_by_title "$gh_repo" "$title")
  if [[ -n "$existing" ]]; then
    skip "issue" "already exists number=$existing — reusing" >&2
    echo "$existing"
    return 0
  fi

  # Build the body: description plus an optional Acceptance Criteria section.
  local body="${description:-No description provided.}"
  if [[ -n "$acceptance" ]]; then
    body="${body}"$'\n\n'"## Acceptance Criteria"$'\n\n'"${acceptance}"
  fi

  # Labels are applied verbatim — no type/* auto-label (the whole point of a
  # standalone issue vs an Epic/Feature/Story).
  local meta
  meta=$(gh_create_issue "$gh_repo" "$title" "$body" "$gh_labels" "$gh_milestone" "$gh_project")
  local number node_id
  number=$(printf '%s' "$meta" | cut -f1)
  node_id=$(printf '%s' "$meta" | cut -f2)

  if [[ -n "$gh_assignees" ]]; then
    gh issue edit "$number" --repo "$gh_repo" --add-assignee "$gh_assignees" >/dev/null 2>&1 \
      || warn "issue" "failed to add assignees '$gh_assignees' to #$number"
  fi

  if [[ -n "$gh_org" && -n "$gh_issue_type" ]]; then
    gh_set_issue_type "$node_id" "$gh_org" "$gh_issue_type" || true
  fi

  ok "issue" "created number=$number" >&2
  echo "$number"
}

main "$@"
