#!/usr/bin/env bash
#
# scripts/wim/_lib.sh — frozen helper library for the work-item suite.
#
# Sourced by create-epic.sh, create-feature.sh, create-user-story.sh, and
# apply-manifest.sh. Do not edit. SHA-pinned in scripts/wim/.frozen-shas.
# See agents/work-item-management-expert.md "Frozen Work-Item Scripts".
#
# Exit codes (when sourced helpers call exit via die):
#   1 — fatal error (caller error or backend failure)
#   2 — missing dependency or bad usage
#

# This file is sourced; the caller controls set -e/-u/-o pipefail. Do not enable
# them here or sourcing scripts will inherit unexpected behavior changes.

# --- Counters (caller may inspect or use wim_print_summary) ---
WIM_ERROR_COUNT=${WIM_ERROR_COUNT:-0}
WIM_WARN_COUNT=${WIM_WARN_COUNT:-0}

# --- Output helpers (rules/script-output-conventions.md) ---
ok()    { echo "OK    [$1] $2"; }
skip()  { echo "SKIP  [$1] $2"; }
warn()  { echo "WARN  [$1] $2" >&2
          WIM_WARN_COUNT=$((WIM_WARN_COUNT + 1))
          [[ -n "${WIM_COUNTS_FILE:-}" ]] && echo "W" >> "$WIM_COUNTS_FILE"
          return 0; }
info()  { echo "INFO  $*"; }
err()   { echo "ERROR [$1] $2" >&2
          WIM_ERROR_COUNT=$((WIM_ERROR_COUNT + 1))
          [[ -n "${WIM_COUNTS_FILE:-}" ]] && echo "E" >> "$WIM_COUNTS_FILE"
          return 0; }
detail(){ if [[ "${WIM_VERBOSE:-0}" == "1" ]]; then echo "      $*"; fi; }
die()   { err "${1:-fatal}" "${2:-aborting}"; exit "${3:-1}"; }

# --- Required commands ---
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "preflight" "required command not found: $1" 2
}

# --- Process-template effort field reference name (ADO) ---
ado_effort_field() {
  case "${1:-}" in
    agile) echo "Microsoft.VSTS.Scheduling.StoryPoints" ;;
    scrum) echo "Microsoft.VSTS.Scheduling.Effort" ;;
    cmmi)  echo "Microsoft.VSTS.Scheduling.Size" ;;
    *)     return 1 ;;
  esac
}

# --- WIQL single-quote escape (double-up per WIQL syntax) ---
# Inside a single-quoted WIQL string literal, only the single-quote character is
# structural (it terminates the literal). Characters such as [ ] AND OR NOT
# CONTAINS < > = are literal text within the literal, so doubling single-quotes
# ('' per WIQL syntax) is the correct and sufficient escape against query
# injection. Ref: learn.microsoft.com/azure/devops/boards/queries/wiql-syntax
wiql_escape() {
  local s="$1"
  printf '%s' "${s//\'/\'\'}"
}

# --- Markdown checklist + paragraphs to ADO HTML field value ---
# Minimal converter sufficient for AcceptanceCriteria use. Not a full MD renderer.
# Uses `python3 -c` (not a `<<HEREDOC`) so the markdown payload on stdin is
# delivered to Python rather than being clobbered by the heredoc.
md_to_ado_html() {
  python3 -c '
import sys, html
data = sys.stdin.read()
lines = data.splitlines()
out, in_ul = [], False
for raw in lines:
    line = raw.rstrip()
    stripped = line.lstrip()
    if stripped.startswith(("- [ ] ", "- [x] ", "- [X] ")):
        if not in_ul:
            out.append("<ul>"); in_ul = True
        out.append("<li>" + html.escape(stripped[6:]) + "</li>")
    elif stripped.startswith("- "):
        if not in_ul:
            out.append("<ul>"); in_ul = True
        out.append("<li>" + html.escape(stripped[2:]) + "</li>")
    elif not line.strip():
        if in_ul:
            out.append("</ul>"); in_ul = False
    else:
        if in_ul:
            out.append("</ul>"); in_ul = False
        out.append("<p>" + html.escape(line) + "</p>")
if in_ul:
    out.append("</ul>")
sys.stdout.write("".join(out))
'
}

# --- ADO: search by title within an area path subtree ---
# Echoes the first matching ID, or empty string if none.
# Args: $1 = work item type (Epic|Feature|"User Story"), $2 = title, $3 = area path
ado_search_by_title() {
  local type="$1" title="$2" area="$3"
  local escaped_title escaped_area
  escaped_title=$(wiql_escape "$title")
  escaped_area=$(wiql_escape "$area")
  # Defensive: after escaping, every single-quote must be doubled. Remove all
  # doubled quotes; any single-quote that remains is lone, which would let the
  # title break out of its WIQL string literal. Abort rather than emit it.
  local residual
  residual=$(printf '%s' "$escaped_title" | sed "s/''//g")
  case "$residual" in
    *\'*) err "ado-search" "title contains an unescapable single-quote after wiql_escape — aborting"; return 1 ;;
  esac
  local wiql="SELECT [System.Id] FROM workitems WHERE [System.Title] = '${escaped_title}' AND [System.AreaPath] UNDER '${escaped_area}' AND [System.WorkItemType] = '${type}' AND [System.State] <> 'Removed'"
  local out
  out=$(az boards query --wiql "$wiql" --output json 2>&1) || {
    err "ado-search" "az boards query failed for type='$type' title='$title': $out"
    return 1
  }
  echo "$out" | jq -r '.[0].id // empty'
}

# --- ADO: create a work item with patch-fields, capture ID ---
# Args: $1 = type, $2 = title, $3 = description (HTML), $4 = area, $5 = iteration,
#       $6 = tags string (semicolon-separated, may be empty),
#       remaining args = additional "Microsoft.VSTS.*=value" pairs.
ado_create_work_item() {
  local type="$1" title="$2" desc="$3" area="$4" iter="$5" tags="$6"
  shift 6
  local cmd=(
    az boards work-item create
      --type "$type"
      --title "$title"
      --area "$area"
      --iteration "$iter"
      --description "$desc"
      --output json
  )
  local fields=()
  [[ -n "$tags" ]] && fields+=( "System.Tags=$tags" )
  local f
  for f in "$@"; do
    [[ -n "$f" ]] && fields+=( "$f" )
  done
  if (( ${#fields[@]} > 0 )); then
    cmd+=( --fields "${fields[@]}" )
  fi
  local out
  out=$("${cmd[@]}" 2>&1) || {
    err "ado-create" "az boards work-item create '$type / $title' failed: $out"
    return 1
  }
  echo "$out" | jq -r '.id'
}

# --- ADO: link parent ---
# Args: $1 = child id, $2 = parent id.
ado_link_parent() {
  local child="$1" parent="$2"
  local out
  out=$(az boards work-item relation add \
          --id "$child" \
          --relation-type parent \
          --target-id "$parent" \
          --output json 2>&1) || {
    err "ado-link" "relation add child=$child parent=$parent failed: $out"
    return 1
  }
}

# --- GitHub: search issue by exact title (open + closed) ---
# Echoes the first matching number, or empty.
#
# The manifest-supplied title is sanitized into `safe_title` BEFORE it is
# embedded in the --search string. GitHub search treats double-quotes and colons
# as syntax and the bare words OR/AND/NOT as boolean operators, so an
# unsanitized title (e.g. `foo OR label:security`) could broaden or narrow the
# server-side result set and corrupt the idempotency decision. The jq filter
# below — `select(.title == $t)` against the ORIGINAL, unmodified title — is the
# authoritative exact match; --search is only a coarse server-side pre-filter.
gh_search_by_title() {
  local repo="$1" title="$2"
  # Derive a query-safe title (bash 3.2-safe literal substitutions).
  local safe_title="$title"
  safe_title="${safe_title//\"/ }"   # double-quote delimits exact-match phrases
  safe_title="${safe_title//:/ }"    # colon separates qualifiers (in:, label:)
  # Strip bare boolean operators as whole words; pad so edge operators are caught.
  safe_title=$(printf '%s' " ${safe_title} " | sed 's/ OR / /g; s/ AND / /g; s/ NOT / /g')
  # Collapse whitespace runs and trim.
  safe_title=$(printf '%s' "$safe_title" | tr -s ' ' | sed 's/^ //; s/ $//')

  local json_fields="number,title"
  local search_args=( --repo "$repo" --state all --json "$json_fields" --limit 100 )
  # If sanitizing emptied the title (a pathological all-operator title), drop the
  # --search qualifier and let the jq exact-match below be the sole authority.
  [[ -n "$safe_title" ]] && search_args+=( --search "\"${safe_title}\" in:title" )

  local out
  out=$(gh issue list "${search_args[@]}" 2>&1) || {
    err "gh-search" "gh issue list failed: $out"
    return 1
  }
  echo "$out" | jq -r --arg t "$title" '.[] | select(.title == $t) | .number' | head -n1
}

# --- GitHub: create an issue, capture URL, then resolve number + node ID. ---
# Echoes "<number>\t<node-id>".
gh_create_issue() {
  local repo="$1" title="$2" body="$3" labels="$4" milestone="$5" project="$6"
  local cmd=( gh issue create --repo "$repo" --title "$title" --body "$body" )
  [[ -n "$labels" ]]    && cmd+=( --label "$labels" )
  [[ -n "$milestone" ]] && cmd+=( --milestone "$milestone" )
  [[ -n "$project" ]]   && cmd+=( --project "$project" )
  local url
  url=$("${cmd[@]}" 2>&1) || {
    err "gh-create" "gh issue create '$title' failed: $url"
    return 1
  }
  url="${url##*$'\n'}"
  local meta
  meta=$(gh issue view "$url" --json number,id 2>&1) || {
    err "gh-view" "gh issue view '$url' failed: $meta"
    return 1
  }
  local n nid
  n=$(echo "$meta" | jq -r '.number')
  nid=$(echo "$meta" | jq -r '.id')
  printf '%s\t%s\n' "$n" "$nid"
}

# --- GitHub: set Issue Type via GraphQL. ---
# Returns 0 on success; 2 if Issue Types are unavailable for the org or the
# requested type name is not configured (caller should fall back to label-only typing).
gh_set_issue_type() {
  local node_id="$1" org="$2" type_name="$3"
  local types_json
  types_json=$(gh api graphql -f query='
    query($org: String!) {
      organization(login: $org) {
        issueTypes(first: 50) { nodes { id name } }
      }
    }' -F org="$org" 2>&1) || {
    warn "gh-issuetype" "GraphQL issueTypes lookup failed for org=$org — falling back to label-only typing"
    return 2
  }
  if echo "$types_json" | jq -e '.errors' >/dev/null 2>&1; then
    warn "gh-issuetype" "Issue Types unavailable on org=$org — falling back to label-only typing"
    return 2
  fi
  local type_id
  type_id=$(echo "$types_json" | jq -r --arg n "$type_name" \
              '.data.organization.issueTypes.nodes[] | select(.name==$n) | .id' | head -n1)
  if [[ -z "$type_id" ]]; then
    warn "gh-issuetype" "Issue Type '$type_name' not configured on org=$org — falling back to label-only typing"
    return 2
  fi
  local out
  out=$(gh api graphql -f query='
    mutation($id: ID!, $typeId: ID!) {
      updateIssue(input: { id: $id, issueTypeId: $typeId }) {
        issue { number issueType { name } }
      }
    }' -F id="$node_id" -F typeId="$type_id" 2>&1) || {
    warn "gh-issuetype" "updateIssue mutation failed for node=$node_id type=$type_name: $out"
    return 2
  }
  if echo "$out" | jq -e '.errors' >/dev/null 2>&1; then
    warn "gh-issuetype" "updateIssue returned errors: $(echo "$out" | jq -c '.errors')"
    return 2
  fi
  return 0
}

# --- GitHub: link sub-issue (parent <- child by issue number). ---
# The sub-issues REST API requires the REST integer database ID of the child,
# not the issue number (which is repo-scoped, not globally unique). We look up
# the child's database ID first via the REST issues endpoint, then POST.
# Returns 0 on success; non-zero (warn) on failure.
gh_link_subissue() {
  local repo="$1" parent="$2" child="$3"
  local owner="${repo%%/*}"
  local reponame="${repo##*/}"
  local child_db_id
  child_db_id=$(gh api "repos/${owner}/${reponame}/issues/${child}" --jq '.id' 2>&1) || {
    warn "gh-subissue" "lookup of child=$child REST database ID failed: $child_db_id"
    return 2
  }
  local out
  out=$(gh api --method POST \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "repos/${owner}/${reponame}/issues/${parent}/sub_issues" \
          -F sub_issue_id="$child_db_id" 2>&1) || {
    warn "gh-subissue" "sub-issue link parent=$parent child=$child (db_id=$child_db_id) failed: $out"
    return 2
  }
  if echo "$out" | jq -e '.errors? // empty' >/dev/null 2>&1; then
    warn "gh-subissue" "sub-issue link returned errors: $out"
    return 2
  fi
  return 0
}

# --- GitHub: preflight active-account accessibility check ---
# Verifies the active gh account can resolve "owner/repo" before any writes.
# On a host with multiple GitHub accounts, gh authenticates as the globally
# active account (hosts.yml) and never auto-selects by repo owner — so the
# wrong active account yields "Could not resolve to a Repository" on every
# subsequent call. This guard fails fast (die, exit 1) with the corrective
# `gh auth switch` command rather than letting a partial run scatter cryptic
# per-call errors. Accessibility is the signal, not a login-vs-owner string
# match — repos are frequently org-owned, so the active user login rarely
# equals the owner even when access is correct. Honors GH_TOKEN/GITHUB_TOKEN
# overrides; github.com scope only. See ADR-052.
# Arg: $1 = "owner/repo"
gh_preflight_identity() {
  local repo="$1"
  [[ -n "$repo" ]] || return 0
  command -v gh >/dev/null 2>&1 || return 0

  # A token in the environment overrides keyring accounts; switching accounts
  # cannot help, so verify access under the token and report against it.
  if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
    gh api "repos/${repo}" --silent >/dev/null 2>&1 && return 0
    die "gh-identity" "GH_TOKEN/GITHUB_TOKEN is set but cannot resolve '${repo}' — verify that token grants access to the repo" 1
  fi

  # Active account can already resolve the repo: proceed.
  gh api "repos/${repo}" --silent >/dev/null 2>&1 && return 0

  # Unreachable under the active account. Probe the other authenticated
  # accounts (without switching) to name the one that works, for an actionable
  # message. Best-effort: if parsing yields nothing, fall back to a generic hint.
  local active suggestion="" acct tok
  active=$(gh api user --jq '.login' 2>/dev/null || true)
  for acct in $(gh auth status 2>/dev/null | sed -n 's/.*account \([^ ]*\).*/\1/p'); do
    [[ "$acct" == "$active" ]] && continue
    tok=$(gh auth token --user "$acct" 2>/dev/null || true)
    [[ -n "$tok" ]] || continue
    if GH_TOKEN="$tok" gh api "repos/${repo}" --silent >/dev/null 2>&1; then
      suggestion="$acct"
      break
    fi
  done

  if [[ -n "$suggestion" ]]; then
    die "gh-identity" "active gh account '${active:-unknown}' cannot access '${repo}' — run: gh auth switch --user ${suggestion}" 1
  fi
  die "gh-identity" "no authenticated gh account can access '${repo}' — run 'gh auth status' to review accounts, or 'gh auth login' to add the owning account" 1
}

# --- Manifest helpers ---
manifest_get() {
  local manifest="$1" path="$2"
  jq -r "${path} // \"\"" "$manifest"
}

manifest_get_array() {
  local manifest="$1" path="$2"
  jq -c "${path} // [] | .[]" "$manifest"
}

# --- Summary block (rules/script-output-conventions.md) ---
wim_print_summary() {
  echo "=================================="
  if (( WIM_ERROR_COUNT > 0 )); then
    echo "FAIL — ${WIM_ERROR_COUNT} error(s), ${WIM_WARN_COUNT} warning(s)"
    return 1
  fi
  echo "PASS — 0 errors, ${WIM_WARN_COUNT} warning(s)"
  return 0
}
