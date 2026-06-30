#!/usr/bin/env bash
#
# scripts/wim/apply-manifest.sh — frozen driver for the work-item suite.
#
# Reads a manifest JSON file conforming to scripts/wim/manifest.schema.json,
# walks Epic -> Features -> Stories top-down, and invokes the corresponding
# create-*.sh scripts. IDs returned on stdout by each create script are
# captured and threaded as parent links to children. Idempotent: each create
# script searches for an existing item by title before creating.
#
# Do not edit. SHA-pinned in scripts/wim/.frozen-shas.
# See agents/work-item-management-expert.md "Frozen Work-Item Scripts".
#
# Usage:
#   apply-manifest.sh <path-to-manifest.json>
#
# Exit codes:
#   0 — all items created or reused successfully
#   1 — one or more failures (see summary block)
#   2 — usage / missing dependency / invalid manifest
#

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$LIB_DIR/_lib.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: apply-manifest.sh <path-to-manifest.json>

Reads the manifest, then invokes:
  scripts/wim/create-epic.sh
  scripts/wim/create-feature.sh   (with --parent-id from epic)
  scripts/wim/create-user-story.sh (with --parent-id from feature)

Backend selector and per-backend globals come from the manifest. See
scripts/wim/manifest.schema.json and scripts/wim/manifest.example.json.
USAGE
  exit 2
}

main() {
  [[ $# -eq 1 ]] || usage
  local manifest="$1"
  [[ -f "$manifest" ]] || die "manifest" "file not found: $manifest" 2

  require_cmd jq

  jq -e . "$manifest" >/dev/null 2>&1 || die "manifest" "not valid JSON: $manifest" 2

  # Counter aggregation across child create-*.sh subprocesses.
  # warn()/err() in _lib.sh append "W"/"E" markers to this file when the env
  # var is set. Without this, child increments would be lost because WIM_*_COUNT
  # is bash-process-scoped.
  WIM_COUNTS_FILE=$(mktemp -t wim-counts.XXXXXX)
  export WIM_COUNTS_FILE
  trap 'rm -f "$WIM_COUNTS_FILE"' EXIT

  local backend
  backend=$(manifest_get "$manifest" '.backend')
  case "$backend" in
    ado|github) ;;
    "")         die "manifest" ".backend is required" 2 ;;
    *)          die "manifest" ".backend must be 'ado' or 'github' (got '$backend')" 2 ;;
  esac

  # Require at least one of: an epic tree, or a non-empty standalone issues list.
  local epic_present issues_count
  epic_present=$(manifest_get "$manifest" '.epic.title')
  issues_count=$(jq '(.issues // []) | length' "$manifest")
  if [[ -z "$epic_present" && "$issues_count" == "0" ]]; then
    die "manifest" "manifest must declare .epic or a non-empty .issues array" 2
  fi

  info "applying manifest: $manifest (backend=$backend)"

  case "$backend" in
    ado)    apply_ado "$manifest" ;;
    github) apply_gh  "$manifest" ;;
  esac

  apply_issues "$backend" "$manifest"

  # Aggregate child-process counters before printing summary.
  # `grep -c` exits 1 with output "0" when no matches; the || branch handles that
  # without doubling output. The assignment captures grep's count; `|| ...=0`
  # only runs on non-zero exit, ensuring a single clean integer in the variable.
  if [[ -f "$WIM_COUNTS_FILE" ]]; then
    WIM_WARN_COUNT=$(grep -c '^W$' "$WIM_COUNTS_FILE" 2>/dev/null) || WIM_WARN_COUNT=0
    WIM_ERROR_COUNT=$(grep -c '^E$' "$WIM_COUNTS_FILE" 2>/dev/null) || WIM_ERROR_COUNT=0
  fi

  wim_print_summary
}

# ---------------------------------------------------------------------------
# ADO branch
# ---------------------------------------------------------------------------

apply_ado() {
  local manifest="$1"

  local org project process global_area global_iter
  org=$(manifest_get "$manifest" '.ado.organization')
  project=$(manifest_get "$manifest" '.ado.project')
  process=$(manifest_get "$manifest" '.ado.process')
  global_area=$(manifest_get "$manifest" '.ado.area')
  global_iter=$(manifest_get "$manifest" '.ado.iteration')

  [[ -n "$org" ]]         || die "manifest" "ado: .ado.organization is required" 2
  [[ -n "$project" ]]     || die "manifest" "ado: .ado.project is required" 2
  [[ -n "$process" ]]     || die "manifest" "ado: .ado.process is required" 2
  [[ -n "$global_area" ]] || die "manifest" "ado: .ado.area is required" 2
  [[ -n "$global_iter" ]] || die "manifest" "ado: .ado.iteration is required" 2

  # --- Epic ---
  local epic_title epic_desc epic_tags epic_area epic_iter epic_priority epic_biz
  epic_title=$(manifest_get "$manifest" '.epic.title')
  epic_desc=$(manifest_get "$manifest" '.epic.description')
  epic_tags=$(manifest_get "$manifest" '.epic.tags')
  epic_area=$(manifest_get "$manifest" '.epic.ado.area')
  epic_iter=$(manifest_get "$manifest" '.epic.ado.iteration')
  epic_priority=$(manifest_get "$manifest" '.epic.ado.priority')
  epic_biz=$(manifest_get "$manifest" '.epic.ado.business_value')
  [[ -z "$epic_area" ]]     && epic_area="$global_area"
  [[ -z "$epic_iter" ]]     && epic_iter="$global_iter"
  [[ -z "$epic_priority" ]] && epic_priority="2"

  [[ -n "$epic_title" ]] || { detail "no .epic.title — skipping ADO epic tree"; return 0; }

  local epic_args=(
    --backend ado
    --organization "$org"
    --project "$project"
    --area "$epic_area"
    --iteration "$epic_iter"
    --title "$epic_title"
    --priority "$epic_priority"
  )
  [[ -n "$epic_desc" ]] && epic_args+=( --description "$epic_desc" )
  [[ -n "$epic_tags" ]] && epic_args+=( --tags "$epic_tags" )
  [[ -n "$epic_biz" ]]  && epic_args+=( --business-value "$epic_biz" )

  local epic_id
  epic_id=$(bash "$LIB_DIR/create-epic.sh" "${epic_args[@]}") || die "epic" "create-epic.sh failed for '$epic_title'"

  # --- Features ---
  local feature_idx=0
  local feat_count
  feat_count=$(jq '.epic.features | length // 0' "$manifest")

  while (( feature_idx < feat_count )); do
    local fpath=".epic.features[${feature_idx}]"

    local f_title f_desc f_tags f_area f_iter f_priority f_value_area
    f_title=$(manifest_get "$manifest" "${fpath}.title")
    f_desc=$(manifest_get "$manifest" "${fpath}.description")
    f_tags=$(manifest_get "$manifest" "${fpath}.tags")
    f_area=$(manifest_get "$manifest" "${fpath}.ado.area")
    f_iter=$(manifest_get "$manifest" "${fpath}.ado.iteration")
    f_priority=$(manifest_get "$manifest" "${fpath}.ado.priority")
    f_value_area=$(manifest_get "$manifest" "${fpath}.ado.value_area")
    [[ -z "$f_area" ]]     && f_area="$global_area"
    [[ -z "$f_iter" ]]     && f_iter="$global_iter"
    [[ -z "$f_priority" ]] && f_priority="2"

    [[ -n "$f_title" ]] || die "manifest" "feature[$feature_idx].title is required" 2

    local f_args=(
      --backend ado
      --organization "$org"
      --project "$project"
      --area "$f_area"
      --iteration "$f_iter"
      --title "$f_title"
      --parent-id "$epic_id"
      --priority "$f_priority"
    )
    [[ -n "$f_desc" ]]       && f_args+=( --description "$f_desc" )
    [[ -n "$f_tags" ]]       && f_args+=( --tags "$f_tags" )
    [[ -n "$f_value_area" ]] && f_args+=( --value-area "$f_value_area" )

    local feature_id
    feature_id=$(bash "$LIB_DIR/create-feature.sh" "${f_args[@]}") \
      || { err "feature" "create-feature.sh failed for '$f_title'"; feature_idx=$((feature_idx + 1)); continue; }

    # --- Stories under this feature ---
    local story_count
    story_count=$(jq "${fpath}.stories | length // 0" "$manifest")
    local story_idx=0
    while (( story_idx < story_count )); do
      local spath="${fpath}.stories[${story_idx}]"

      local s_title s_desc s_ac s_tags s_area s_iter s_priority s_points s_assigned
      s_title=$(manifest_get "$manifest" "${spath}.title")
      s_desc=$(manifest_get "$manifest" "${spath}.description")
      s_ac=$(manifest_get "$manifest" "${spath}.acceptance_criteria")
      s_tags=$(manifest_get "$manifest" "${spath}.tags")
      s_area=$(manifest_get "$manifest" "${spath}.ado.area")
      s_iter=$(manifest_get "$manifest" "${spath}.ado.iteration")
      s_priority=$(manifest_get "$manifest" "${spath}.ado.priority")
      s_points=$(manifest_get "$manifest" "${spath}.ado.story_points")
      s_assigned=$(manifest_get "$manifest" "${spath}.ado.assigned_to")
      [[ -z "$s_area" ]]     && s_area="$global_area"
      [[ -z "$s_iter" ]]     && s_iter="$global_iter"
      [[ -z "$s_priority" ]] && s_priority="2"

      [[ -n "$s_title" ]] || die "manifest" "feature[$feature_idx].stories[$story_idx].title is required" 2

      local s_args=(
        --backend ado
        --organization "$org"
        --project "$project"
        --process "$process"
        --area "$s_area"
        --iteration "$s_iter"
        --title "$s_title"
        --parent-id "$feature_id"
        --priority "$s_priority"
      )
      [[ -n "$s_desc" ]]     && s_args+=( --description "$s_desc" )
      [[ -n "$s_ac" ]]       && s_args+=( --acceptance-criteria "$s_ac" )
      [[ -n "$s_tags" ]]     && s_args+=( --tags "$s_tags" )
      [[ -n "$s_points" ]]   && s_args+=( --story-points "$s_points" )
      [[ -n "$s_assigned" ]] && s_args+=( --assigned-to "$s_assigned" )

      bash "$LIB_DIR/create-user-story.sh" "${s_args[@]}" >/dev/null \
        || err "story" "create-user-story.sh failed for '$s_title'"

      story_idx=$((story_idx + 1))
    done

    feature_idx=$((feature_idx + 1))
  done
}

# ---------------------------------------------------------------------------
# GitHub branch
# ---------------------------------------------------------------------------

apply_gh() {
  local manifest="$1"

  local repo org project milestone
  repo=$(manifest_get "$manifest" '.github.repo')
  org=$(manifest_get "$manifest" '.github.org')
  project=$(manifest_get "$manifest" '.github.project')
  milestone=$(manifest_get "$manifest" '.github.milestone')

  [[ -n "$repo" ]] || die "manifest" "github: .github.repo is required" 2

  # Fail fast if the active gh account cannot resolve the repo (multi-account
  # hosts: wrong active account => "Could not resolve to a Repository"). See ADR-052.
  gh_preflight_identity "$repo"

  local default_labels
  default_labels=$(jq -r '.github.default_labels // [] | join(",")' "$manifest")

  # --- Epic ---
  local e_title e_desc e_extra_labels e_milestone e_project
  e_title=$(manifest_get "$manifest" '.epic.title')
  e_desc=$(manifest_get "$manifest" '.epic.description')
  e_extra_labels=$(jq -r '.epic.labels // [] | join(",")' "$manifest")
  e_milestone=$(manifest_get "$manifest" '.epic.github.milestone')
  e_project=$(manifest_get "$manifest" '.epic.github.project')
  [[ -z "$e_milestone" ]] && e_milestone="$milestone"
  [[ -z "$e_project" ]]   && e_project="$project"

  [[ -n "$e_title" ]] || { detail "no .epic.title — skipping GitHub epic tree"; return 0; }

  local e_labels
  e_labels=$(combine_labels "$default_labels" "$e_extra_labels")

  local epic_args=(
    --backend github
    --repo "$repo"
    --title "$e_title"
  )
  [[ -n "$e_desc" ]]      && epic_args+=( --description "$e_desc" )
  [[ -n "$org" ]]         && epic_args+=( --org "$org" )
  [[ -n "$e_labels" ]]    && epic_args+=( --labels "$e_labels" )
  [[ -n "$e_milestone" ]] && epic_args+=( --milestone "$e_milestone" )
  [[ -n "$e_project" ]]   && epic_args+=( --gh-project "$e_project" )

  local epic_number
  epic_number=$(bash "$LIB_DIR/create-epic.sh" "${epic_args[@]}") || die "epic" "create-epic.sh failed for '$e_title'"

  # --- Features ---
  local feat_count
  feat_count=$(jq '.epic.features | length // 0' "$manifest")
  local feature_idx=0

  while (( feature_idx < feat_count )); do
    local fpath=".epic.features[${feature_idx}]"

    local f_title f_desc f_extra_labels f_milestone f_project
    f_title=$(manifest_get "$manifest" "${fpath}.title")
    f_desc=$(manifest_get "$manifest" "${fpath}.description")
    f_extra_labels=$(jq -r "${fpath}.labels // [] | join(\",\")" "$manifest")
    f_milestone=$(manifest_get "$manifest" "${fpath}.github.milestone")
    f_project=$(manifest_get "$manifest" "${fpath}.github.project")
    [[ -z "$f_milestone" ]] && f_milestone="$milestone"
    [[ -z "$f_project" ]]   && f_project="$project"

    [[ -n "$f_title" ]] || die "manifest" "feature[$feature_idx].title is required" 2

    local f_labels
    f_labels=$(combine_labels "$default_labels" "$f_extra_labels")

    local f_args=(
      --backend github
      --repo "$repo"
      --title "$f_title"
      --parent-id "$epic_number"
    )
    [[ -n "$f_desc" ]]      && f_args+=( --description "$f_desc" )
    [[ -n "$org" ]]         && f_args+=( --org "$org" )
    [[ -n "$f_labels" ]]    && f_args+=( --labels "$f_labels" )
    [[ -n "$f_milestone" ]] && f_args+=( --milestone "$f_milestone" )
    [[ -n "$f_project" ]]   && f_args+=( --gh-project "$f_project" )

    local feature_number
    feature_number=$(bash "$LIB_DIR/create-feature.sh" "${f_args[@]}") \
      || { err "feature" "create-feature.sh failed for '$f_title'"; feature_idx=$((feature_idx + 1)); continue; }

    # --- Stories under this feature ---
    local story_count
    story_count=$(jq "${fpath}.stories | length // 0" "$manifest")
    local story_idx=0
    while (( story_idx < story_count )); do
      local spath="${fpath}.stories[${story_idx}]"

      local s_title s_desc s_ac s_extra_labels s_milestone s_project s_assignees
      s_title=$(manifest_get "$manifest" "${spath}.title")
      s_desc=$(manifest_get "$manifest" "${spath}.description")
      s_ac=$(manifest_get "$manifest" "${spath}.acceptance_criteria")
      s_extra_labels=$(jq -r "${spath}.labels // [] | join(\",\")" "$manifest")
      s_milestone=$(manifest_get "$manifest" "${spath}.github.milestone")
      s_project=$(manifest_get "$manifest" "${spath}.github.project")
      s_assignees=$(jq -r "${spath}.github.assignees // [] | join(\",\")" "$manifest")
      [[ -z "$s_milestone" ]] && s_milestone="$milestone"
      [[ -z "$s_project" ]]   && s_project="$project"

      [[ -n "$s_title" ]] || die "manifest" "feature[$feature_idx].stories[$story_idx].title is required" 2

      local s_labels
      s_labels=$(combine_labels "$default_labels" "$s_extra_labels")

      local s_args=(
        --backend github
        --repo "$repo"
        --title "$s_title"
        --parent-id "$feature_number"
      )
      [[ -n "$s_desc" ]]       && s_args+=( --description "$s_desc" )
      [[ -n "$s_ac" ]]         && s_args+=( --acceptance-criteria "$s_ac" )
      [[ -n "$org" ]]          && s_args+=( --org "$org" )
      [[ -n "$s_labels" ]]     && s_args+=( --labels "$s_labels" )
      [[ -n "$s_milestone" ]]  && s_args+=( --milestone "$s_milestone" )
      [[ -n "$s_project" ]]    && s_args+=( --gh-project "$s_project" )
      [[ -n "$s_assignees" ]]  && s_args+=( --assignees "$s_assignees" )

      bash "$LIB_DIR/create-user-story.sh" "${s_args[@]}" >/dev/null \
        || err "story" "create-user-story.sh failed for '$s_title'"

      story_idx=$((story_idx + 1))
    done

    feature_idx=$((feature_idx + 1))
  done
}

# Combine two comma-separated label strings, dropping empty parts.
combine_labels() {
  local a="$1" b="$2"
  if [[ -z "$a" ]]; then echo "$b"; return; fi
  if [[ -z "$b" ]]; then echo "$a"; return; fi
  echo "${a},${b}"
}

# ---------------------------------------------------------------------------
# Standalone issues (flat list, no parent, no auto type/* label)
# ---------------------------------------------------------------------------

apply_issues() {
  local backend="$1" manifest="$2"

  local issue_count
  issue_count=$(jq '(.issues // []) | length' "$manifest")
  (( issue_count > 0 )) || return 0

  local repo org project milestone default_labels
  local org_ado project_ado global_area global_iter
  if [[ "$backend" == "github" ]]; then
    repo=$(manifest_get "$manifest" '.github.repo')
    org=$(manifest_get "$manifest" '.github.org')
    project=$(manifest_get "$manifest" '.github.project')
    milestone=$(manifest_get "$manifest" '.github.milestone')
    default_labels=$(jq -r '.github.default_labels // [] | join(",")' "$manifest")
  else
    org_ado=$(manifest_get "$manifest" '.ado.organization')
    project_ado=$(manifest_get "$manifest" '.ado.project')
    global_area=$(manifest_get "$manifest" '.ado.area')
    global_iter=$(manifest_get "$manifest" '.ado.iteration')
  fi

  local idx=0
  while (( idx < issue_count )); do
    local ipath=".issues[${idx}]"
    local i_title i_desc i_ac i_tags
    i_title=$(manifest_get "$manifest" "${ipath}.title")
    i_desc=$(manifest_get "$manifest" "${ipath}.description")
    i_ac=$(manifest_get "$manifest" "${ipath}.acceptance_criteria")
    i_tags=$(manifest_get "$manifest" "${ipath}.tags")

    [[ -n "$i_title" ]] || die "manifest" "issues[$idx].title is required" 2

    if [[ "$backend" == "github" ]]; then
      local i_extra_labels i_labels i_milestone i_project i_assignees
      i_extra_labels=$(jq -r "${ipath}.labels // [] | join(\",\")" "$manifest")
      i_labels=$(combine_labels "$default_labels" "$i_extra_labels")
      i_milestone=$(manifest_get "$manifest" "${ipath}.github.milestone")
      i_project=$(manifest_get "$manifest" "${ipath}.github.project")
      i_assignees=$(jq -r "${ipath}.github.assignees // [] | join(\",\")" "$manifest")
      [[ -z "$i_milestone" ]] && i_milestone="$milestone"
      [[ -z "$i_project" ]]   && i_project="$project"

      local g_args=( --backend github --repo "$repo" --title "$i_title" )
      [[ -n "$i_desc" ]]      && g_args+=( --description "$i_desc" )
      [[ -n "$i_ac" ]]        && g_args+=( --acceptance-criteria "$i_ac" )
      [[ -n "$org" ]]         && g_args+=( --org "$org" )
      [[ -n "$i_labels" ]]    && g_args+=( --labels "$i_labels" )
      [[ -n "$i_milestone" ]] && g_args+=( --milestone "$i_milestone" )
      [[ -n "$i_project" ]]   && g_args+=( --gh-project "$i_project" )
      [[ -n "$i_assignees" ]] && g_args+=( --assignees "$i_assignees" )

      bash "$LIB_DIR/create-issue.sh" "${g_args[@]}" >/dev/null \
        || err "issue" "create-issue.sh failed for '$i_title'"
    else
      local i_type i_area i_iter i_priority i_severity i_assigned
      i_type=$(manifest_get "$manifest" "${ipath}.ado.type")
      i_area=$(manifest_get "$manifest" "${ipath}.ado.area")
      i_iter=$(manifest_get "$manifest" "${ipath}.ado.iteration")
      i_priority=$(manifest_get "$manifest" "${ipath}.ado.priority")
      i_severity=$(manifest_get "$manifest" "${ipath}.ado.severity")
      i_assigned=$(manifest_get "$manifest" "${ipath}.ado.assigned_to")
      [[ -z "$i_area" ]] && i_area="$global_area"
      [[ -z "$i_iter" ]] && i_iter="$global_iter"
      [[ -z "$i_type" ]] && i_type="Issue"

      local a_args=( --backend ado --organization "$org_ado" --project "$project_ado"
                     --area "$i_area" --iteration "$i_iter" --title "$i_title" --type "$i_type" )
      [[ -n "$i_desc" ]]     && a_args+=( --description "$i_desc" )
      [[ -n "$i_ac" ]]       && a_args+=( --acceptance-criteria "$i_ac" )
      [[ -n "$i_tags" ]]     && a_args+=( --tags "$i_tags" )
      [[ -n "$i_priority" ]] && a_args+=( --priority "$i_priority" )
      [[ -n "$i_severity" ]] && a_args+=( --severity "$i_severity" )
      [[ -n "$i_assigned" ]] && a_args+=( --assigned-to "$i_assigned" )

      bash "$LIB_DIR/create-issue.sh" "${a_args[@]}" >/dev/null \
        || err "issue" "create-issue.sh failed for '$i_title'"
    fi

    idx=$((idx + 1))
  done
}

main "$@"
