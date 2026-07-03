#!/usr/bin/env bash
#
# Agent Framework — Validation Script
#
# Checks that all monolithic agents, rules, and symlinks are consistent
# with the single-file agent architecture (ADR-074). Run before committing.
#
# Usage:
#   ./validate.sh
#
# Exit codes:
#   0 — all checks passed (warnings are informational only)
#   1 — one or more errors found
#

set -euo pipefail

# Bash 4.0+ required: this script uses an associative array (declare -A FM).
# macOS system bash is 3.2 — fail loudly with a clear message rather than a
# cryptic `declare: -A: invalid option` mid-run. Exit 2 = precondition failure
# (rules/script-output-conventions.md).
if (( ${BASH_VERSINFO[0]:-0} < 4 )); then
  echo "ERROR [env] validate.sh requires bash 4.0 or later (found ${BASH_VERSION:-unknown})" >&2
  echo "INFO  On macOS install a modern bash: brew install bash" >&2
  exit 2
fi

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Deterministic collation/classification regardless of host locale: sort order
# feeds ADR-numbering and catalog comparisons, and CI/dev machines differ in
# their default locale. The script never localizes output, so this is safe.
export LC_ALL=C

# --- Counters ---
error_count=0
warn_count=0

# --- Output helpers ---
error() {
  echo "ERROR [$1] $2" >&2
  ((error_count++)) || true
}

warn() {
  echo "WARN  [$1] $2" >&2
  ((warn_count++)) || true
}

ok() {
  echo "OK    [$1] $2"
}

info() {
  echo "INFO  $1"
}

skip() {
  echo "SKIP  [$1] $2"
}

# Indented detail line, only printed when VALIDATE_VERBOSE=1
detail() {
  if [[ "${VALIDATE_VERBOSE:-}" == "1" ]]; then
    echo "      $*"
  fi
}

# --- Agents permitted to carry execution tools (ADR-069) ---
# Bash is granted only to agents with a documented execution workflow in their
# agent file. Adding an agent here requires a PR citing the workflow; per-agent
# justifications are recorded in ADR-069.
CLAUDE_BASH_ALLOWED=(
  gh-cli-expert work-item-management-expert gitflow-expert
  shell-expert linter
)

# --- External agents (referenced but not in this repo) ---
EXTERNAL_AGENTS=()

# --- Frontmatter parser ---
# Reads YAML frontmatter between --- markers into associative array FM[].
# Scalar values are stored as FM[key]. YAML list items under a key are
# accumulated as space-separated values in FM[key_list].
# Returns 1 if no frontmatter block found.
declare -A FM
parse_frontmatter() {
  local file="$1"
  FM=()

  local in_fm=0
  local fm_started=0
  local current_key=""

  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if [[ $fm_started -eq 0 ]]; then
        fm_started=1
        in_fm=1
        continue
      else
        break
      fi
    fi
    [[ $in_fm -eq 0 ]] && continue

    # YAML list item (e.g., "  - shell-expert")
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
      local val="${BASH_REMATCH[1]}"
      # Strip quotes
      val="${val#\'}" ; val="${val%\'}"
      val="${val#\"}" ; val="${val%\"}"
      FM["${current_key}_list"]+="${val} "
      continue
    fi

    # Key: value line
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]]*(.*) ]]; then
      current_key="${BASH_REMATCH[1]}"
      local raw_val="${BASH_REMATCH[2]}"
      # Strip surrounding quotes
      raw_val="${raw_val#\'}" ; raw_val="${raw_val%\'}"
      raw_val="${raw_val#\"}" ; raw_val="${raw_val%\"}"
      FM["$current_key"]="$raw_val"
    fi
  done < "$file"

  [[ $fm_started -eq 1 ]]
}

# --- Check a single monolithic agent (ADR-074) ---
# Each expert is one self-contained agents/<name>.md: operational frontmatter
# (name, description, model, tools, disable-model-invocation) plus the full
# expertise inline. There is no skills/ layer and no separate wrapper.
check_agent() {
  local file="$1"
  local name
  name="$(basename "$file" .md)"
  local had_error=0

  # 1. Frontmatter present
  if ! parse_frontmatter "$file"; then
    error "$name" "agent: no frontmatter block found"
    return
  fi

  # 2. Required fields
  local field
  for field in name description model tools; do
    if [[ -z "${FM[$field]:-}" ]]; then
      error "$name" "agent: missing required field '$field'"
      had_error=1
    fi
  done

  # 3. name matches filename
  if [[ -n "${FM[name]:-}" && "${FM[name]}" != "$name" ]]; then
    error "$name" "agent: name '${FM[name]}' does not match file name '$name'"
    had_error=1
  fi

  # 4. disable-model-invocation must be explicitly true (ADR-074, supersedes
  #    ADR-033): all delegation is orchestrator-controlled, so an agent must
  #    not be auto-invocable by the main model.
  if [[ "${FM[disable-model-invocation]:-}" != "true" ]]; then
    error "$name" "agent: missing required field 'disable-model-invocation: true' (ADR-074)"
    had_error=1
  fi

  # 5. No obsolete 'skills:' reference — the monolithic pattern inlines the
  #    expertise; a skills: block means content was not collapsed (ADR-074).
  if [[ -n "${FM[skills_list]:-}" || -n "${FM[skills]:-}" ]]; then
    error "$name" "agent: 'skills:' is obsolete under the monolithic pattern (ADR-074) — inline the expertise"
    had_error=1
  fi

  # 6. Execution-tool policy (ADR-069): Bash only for allowlisted agents.
  #    Comma-to-space normalization gives word-boundary matching, so a
  #    hypothetical tool name merely containing "Bash" cannot false-positive.
  local tools_normalized=" ${FM[tools]:-} "
  tools_normalized="${tools_normalized//,/ }"
  if [[ "$tools_normalized" == *" Bash "* ]]; then
    local bash_ok=0
    local bash_allowed_agent
    for bash_allowed_agent in "${CLAUDE_BASH_ALLOWED[@]}"; do
      if [[ "$name" == "$bash_allowed_agent" ]]; then
        bash_ok=1
        break
      fi
    done
    if [[ $bash_ok -eq 0 ]]; then
      error "$name" "agent: 'Bash' requires a documented execution workflow — add '$name' to CLAUDE_BASH_ALLOWED in validate.sh with justification (ADR-069) or remove Bash from tools"
      had_error=1
    fi
  fi

  # 7. No MCP server wiring — an 'mcp-servers'/'mcpServers' frontmatter key is
  #    prohibited (rules/no-mcp-servers.md, ADR-002; closes #25). Grep the raw
  #    frontmatter block rather than FM[]: parse_frontmatter stores "" for a
  #    bare `mcp-servers:` key whose value is a YAML list on following lines,
  #    so an FM emptiness test would miss exactly the form the policy targets.
  local fm_raw
  fm_raw="$(awk '/^---[[:space:]]*$/{c++; next} c==1' "$file")"
  if printf '%s\n' "$fm_raw" | grep -qE '^[[:space:]]*(mcp-servers|mcpServers):'; then
    error "$name" "agent: 'mcp-servers'/'mcpServers' frontmatter is prohibited (rules/no-mcp-servers.md, ADR-002)"
    had_error=1
  fi

  # 8. Body must carry the expertise inline (monolithic — ADR-074)
  local body
  body="$(get_body_after_frontmatter "$file")"
  if [[ ${#body} -lt 200 ]]; then
    error "$name" "agent: body is only ${#body} chars — a monolithic agent must contain its full expertise inline (ADR-074)"
    had_error=1
  fi

  if [[ $had_error -eq 0 ]]; then
    ok "$name" "All checks passed"
  fi
}

# --- Get body content after frontmatter ---
# Returns everything after the second --- marker.
get_body_after_frontmatter() {
  local file="$1"
  local found_first=0
  local found_second=0
  local body=""

  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if [[ $found_first -eq 0 ]]; then
        found_first=1
        continue
      elif [[ $found_second -eq 0 ]]; then
        found_second=1
        continue
      fi
    fi
    if [[ $found_second -eq 1 ]]; then
      body+="$line"$'\n'
    fi
  done < "$file"

  echo "$body"
}

# --- Check rule Enforcement lines (#23, ADR-084) ---
# Every rules/*.md must carry a '**Enforcement:**' line within the first 5
# lines after its H1 (the named-mechanism convention from ADR-084; vocabulary
# documented in CONTRIBUTING.md's Rules frontmatter reference). The mechanism
# vocabulary check is WARN, not ERROR: compound `;`-joined lines and
# parenthetical caveats are legitimate, and a genuinely new mechanism token
# should not hard-block validation on a taxonomy gap (same posture as
# check_readme_catalog's drift warnings). Presence is ERROR — a rule shipped
# without the line is exactly the silent gap #23 closes.
check_enforcement_line() {
  local rules_dir="$DOTFILES_DIR/rules"
  if [[ ! -d "$rules_dir" ]]; then
    skip "enforcement" "rules/ not present — nothing to check"
    return
  fi
  local vocab_re='PreToolUse hook|PostToolBatch hook|SubagentStop hook|pre-commit hook|pre-push hook|validate\.sh|CI [A-Za-z0-9._-]+\.ya?ml|GitHub Ruleset|self-report only'
  local checked=0 missing=0 f rel hit mech
  for f in "$rules_dir"/*.md; do
    [[ -f "$f" ]] || continue
    checked=$((checked + 1))
    rel="${f#"$DOTFILES_DIR"/}"
    hit="$(awk '
      h1==0 && /^# / { h1=NR; next }
      h1>0 && NR<=h1+5 && /^\*\*Enforcement:\*\*/ { print; exit }
      h1>0 && NR>h1+5 { exit }
    ' "$f")"
    if [[ -z "$hit" ]]; then
      error "enforcement" "$rel: no '**Enforcement:**' line within 5 lines after the H1 (ADR-084)"
      missing=$((missing + 1))
      continue
    fi
    mech="${hit#\*\*Enforcement:\*\*}"
    if [[ ! "$mech" =~ $vocab_re ]]; then
      warn "enforcement" "$rel: Enforcement mechanism outside the documented vocabulary:${mech}"
    fi
  done
  if [[ $checked -eq 0 ]]; then
    warn "enforcement" "no rule files found under rules/"
  elif [[ $missing -eq 0 ]]; then
    ok "enforcement" "$checked rule(s) carry an Enforcement line"
  fi
}

# --- Check for concrete MCP package references in distributed prose ---
# rules/no-mcp-servers.md also prohibits referencing MCP server packages in
# the content this repo distributes. check_agent covers the frontmatter key
# (#25); this heuristic covers prose bodies (#37). It matches concrete
# package-name shapes only — the '@modelcontextprotocol/' npm scope and the
# 'mcp-server-<name>' npm/PyPI naming convention — never the bare substring
# 'mcp', so policy discussion (rules/no-mcp-servers.md itself, references to
# the 'mcp-servers' frontmatter key, and the rule's filename) does not
# false-positive. WARN-level: a heuristic over prose, not a hard gate.
check_no_mcp_prose() {
  local pattern='@modelcontextprotocol/|mcp-server-[a-z0-9]'
  local scanned=0 flagged=0 f rel lineno rest
  for f in "$DOTFILES_DIR"/rules/*.md "$DOTFILES_DIR"/agents/*.md \
           "$DOTFILES_DIR"/commands/*.md "$DOTFILES_DIR"/skills/*/SKILL.md \
           "$DOTFILES_DIR"/web/instructions.md; do
    [[ -f "$f" ]] || continue
    scanned=$((scanned + 1))
    rel="${f#"$DOTFILES_DIR"/}"
    while IFS=: read -r lineno rest; do
      [[ -n "$lineno" ]] || continue
      warn "mcp-prose" "$rel:$lineno: concrete MCP package reference in distributed prose (rules/no-mcp-servers.md, ADR-002)"
      detail "$rest"
      flagged=$((flagged + 1))
    done < <(grep -inE "$pattern" "$f")
  done
  if [[ $scanned -eq 0 ]]; then
    skip "mcp-prose" "no distributed prose surfaces found"
  elif [[ $flagged -eq 0 ]]; then
    ok "mcp-prose" "$scanned file(s) free of concrete MCP package references"
  fi
}

# --- Check for committed plugin/MCP manifests ---
# rules/no-mcp-servers.md (as amended per ADR-094) prohibits bundling MCP
# servers via plugin packaging. A committed `.mcp.json` anywhere, or a
# `.claude-plugin/` directory, is the concrete artifact of that prohibited
# shape — ERROR-gated, since a manifest is unambiguous in a way prose is not.
check_no_mcp_manifests() {
  local hits=0 f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    error "mcp-manifests" "${f#"$DOTFILES_DIR"/}: committed MCP/plugin manifest is prohibited (rules/no-mcp-servers.md, ADR-094)"
    hits=$((hits + 1))
  done < <(find "$DOTFILES_DIR" \( -name node_modules -o -name .git \) -prune -o \
             \( -name '.mcp.json' -o -type d -name '.claude-plugin' \) -print 2>/dev/null)
  if [[ $hits -eq 0 ]]; then
    ok "mcp-manifests" "no committed .mcp.json or .claude-plugin/ manifests"
  fi
}

# --- Valid ADR status values ---
ADR_VALID_STATUSES=(
  "Proposed"
  "Accepted"
  "Deprecated"
)
# "Superseded by ..." is also valid — checked via prefix match

# --- ADR required sections ---
ADR_REQUIRED_SECTIONS=(
  "Context and Problem Statement"
  "Considered Options"
  "Decision Outcome"
)

# --- Check ADRs ---
check_adrs() {
  local adrs_dir="$DOTFILES_DIR/adrs"
  [[ ! -d "$adrs_dir" ]] && return

  local prev_num=-1
  local had_adr=0

  # Collect ADR files (exclude TEMPLATE.md), sorted by name
  local adr_files=()
  while IFS= read -r f; do
    adr_files+=("$f")
  done < <(find "$adrs_dir" -maxdepth 1 -name '[0-9]*.md' -type f | sort)

  for adr_file in "${adr_files[@]}"; do
    had_adr=1
    local filename
    filename="$(basename "$adr_file")"

    # Check sequential numbering
    local num_str="${filename%%-*}"
    # Enforce the zero-padded three-digit form (rules/adr-required.md).
    if [[ ! "$num_str" =~ ^[0-9]{3}$ ]]; then
      error "adrs" "$filename: ADR number '$num_str' must be zero-padded to three digits (e.g. 042-)"
    fi
    local num=$((10#$num_str))
    # Numbers must be unique and ascending; gaps ARE allowed — ADRs may be
    # dropped when forking the framework (ADR-076) and numbers are never reused.
    if [[ $num -eq $prev_num ]]; then
      error "adrs" "$filename: duplicate ADR number $(printf '%03d' "$num") — numbers must never be reused"
    elif [[ $num -lt $prev_num ]]; then
      error "adrs" "$filename: ADR number $(printf '%03d' "$num") out of order (follows $(printf '%03d' "$prev_num"))"
    fi
    prev_num=$num

    # Check Status line
    local status_line
    status_line="$(grep -m1 '^\*\*Status:\*\*' "$adr_file" 2>/dev/null || true)"
    if [[ -z "$status_line" ]]; then
      error "adrs" "$filename: missing **Status:** line"
    else
      local status_val="${status_line#\*\*Status:\*\* }"
      local valid_status=0
      for s in "${ADR_VALID_STATUSES[@]}"; do
        if [[ "$status_val" == "$s" ]]; then
          valid_status=1
          break
        fi
      done
      # Check for "Superseded by ..." prefix
      if [[ $valid_status -eq 0 && "$status_val" == Superseded\ by* ]]; then
        valid_status=1
      fi
      if [[ $valid_status -eq 0 ]]; then
        error "adrs" "$filename: invalid status '$status_val' (expected: ${ADR_VALID_STATUSES[*]}, or 'Superseded by ...')"
      fi
    fi

    # Check Date line
    local date_line
    date_line="$(grep -m1 '^\*\*Date:\*\*' "$adr_file" 2>/dev/null || true)"
    if [[ -z "$date_line" ]]; then
      warn "adrs" "$filename: missing **Date:** line"
    fi

    # Check required sections
    local body
    body="$(cat "$adr_file")"
    for section in "${ADR_REQUIRED_SECTIONS[@]}"; do
      if ! echo "$body" | grep -q "^## $section"; then
        error "adrs" "$filename: missing required section '## $section'"
      fi
    done
  done

  # Check TEMPLATE.md exists
  if [[ ! -f "$adrs_dir/TEMPLATE.md" ]]; then
    warn "adrs" "TEMPLATE.md not found in adrs/"
  fi

  if [[ $had_adr -eq 1 && $error_count -eq 0 ]]; then
    ok "adrs" "All ADRs valid (${#adr_files[@]} records)"
  elif [[ $had_adr -eq 0 ]]; then
    info "No ADR files found in adrs/"
  fi
}

# --- Check branch PR state ---
check_branch_pr_state() {
  # Skip if gh is not available or not in a git repo
  command -v gh >/dev/null 2>&1 || return 0
  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  local branch
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
  [[ -z "$branch" ]] && return

  # Skip default branches — they never have PRs targeting themselves
  [[ "$branch" == "main" || "$branch" == "master" ]] && return

  # Check if a merged PR exists for this branch. A gh failure (network, auth,
  # rate limit) is a visible SKIP, not a silent pass — "no merged PR" and
  # "could not check" must be distinguishable in the output.
  local pr_num rc=0
  pr_num="$(gh pr list --head "$branch" --state merged --json number --jq '.[0].number // empty' 2>/dev/null)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    skip "branch" "gh pr list failed for branch '$branch' — network or auth unavailable; merged-branch check skipped"
    return
  fi

  if [[ -n "$pr_num" ]]; then
    warn "branch" "PR #${pr_num} for branch '$branch' is already merged — create a new branch for additional changes"
  fi
}

# --- Check active gh account can resolve the origin repo (multi-account hosts) ---
# Non-fatal: a mismatch is a WARN, never an ERROR. Skipped when a token is in the
# environment (CI sets GH_TOKEN/GITHUB_TOKEN) and for non-github.com remotes.
# See ADR-052 and docs/multi-account-git-identity.md.
check_gh_identity() {
  command -v gh >/dev/null 2>&1 || return 0
  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  # A token in the environment overrides keyring accounts — skip to avoid CI
  # noise, but say so: a silent return is indistinguishable from "checked OK".
  if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
    skip "gh-identity" "GH_TOKEN/GITHUB_TOKEN present — identity check not applicable under a scoped token"
    return
  fi

  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  [[ -z "$remote_url" ]] && return

  # Only plain github.com remotes; SSH host aliases and GHES are out of scope.
  case "$remote_url" in
    *github.com[:/]*) ;;
    *) return 0 ;;
  esac

  local slug
  slug="$(printf '%s' "$remote_url" | sed -E 's/(\.git)$//; s#.*github\.com[:/]([^/]+/[^/]+)$#\1#')"
  [[ "$slug" == */* ]] || return 0

  if gh api "repos/${slug}" --silent >/dev/null 2>&1; then
    ok "gh-identity" "active gh account can resolve ${slug}"
  else
    local active
    active="$(gh api user --jq '.login' 2>/dev/null || true)"
    warn "gh-identity" "active gh account '${active:-unknown}' cannot resolve ${slug} — run 'gh auth switch' to the owning account before using gh-backed tooling"
  fi
}

# --- Check agent catalog in AGENTS.md ---
check_agent_catalog() {
  # Delegates to the canonical drift gate (ADR-062, mirror retired by ADR-085).
  # scripts/regen-agent-catalog.sh --check verifies name presence vs agents/*.md,
  # that rules/agent-first-selection.md carries the AGENTS.md pointer (and no
  # reintroduced table copy), and README Tier/Model. AGENTS.md is canonical.
  local script="$DOTFILES_DIR/scripts/regen-agent-catalog.sh"
  if [[ ! -x "$script" ]]; then
    warn "catalog" "scripts/regen-agent-catalog.sh missing or not executable — skipping catalog drift check"
    return
  fi

  local out rc=0
  out="$("$script" --check 2>&1)" || rc=$?

  # Re-emit the sub-script's presence warnings through our own counter.
  while IFS= read -r msg; do
    [[ -n "$msg" ]] && warn "catalog" "$msg"
  done < <(printf '%s\n' "$out" | sed -n 's/^WARN  \[[^]]*\] //p')

  if [[ $rc -eq 0 ]]; then
    ok "catalog" "Agent catalog consistent (AGENTS.md canonical; routing pointer + README tier/model checked)"
  else
    # Surface the drift detail (stderr, per output conventions), fold into one error.
    printf '%s\n' "$out" | grep '^ERROR' >&2 || true
    error "catalog" "Agent catalog drift — AGENTS.md is canonical; fix it (and README tier/model) by hand, see scripts/regen-agent-catalog.sh --check output"
  fi
}

# --- Check README catalog sections ---
# Verifies that README.md Current Agents/Rules sections match files on disk.
# All discrepancies are warnings, not errors — drift may be intentional during
# in-progress work.
check_readme_catalog() {
  local readme="$DOTFILES_DIR/README.md"
  local readme_warns=0

  if [[ ! -f "$readme" ]]; then
    warn "readme-catalog" "README.md not found — cannot verify catalog sections"
    return
  fi

  # --- Agents catalog ---
  local agents_dir="$DOTFILES_DIR/agents"
  if [[ -d "$agents_dir" ]]; then
    # Extract agent names from README "Current Agents" table rows
    # Format: | `agent-name` | ... |
    local readme_agents=()
    local in_section=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]] && ! "$line" =~ ^### ]]; then
        if [[ "$line" =~ ^##[[:space:]]Current[[:space:]]Agents ]]; then
          in_section=1
        else
          in_section=0
        fi
      fi
      if [[ $in_section -eq 1 && "$line" =~ ^\|[[:space:]]*\`([a-zA-Z0-9_-]+)\`[[:space:]]*\| ]]; then
        readme_agents+=("${BASH_REMATCH[1]}")
      fi
    done < "$readme"

    # Forward: every README entry must have an agents/ file
    for name in "${readme_agents[@]}"; do
      if [[ ! -f "$agents_dir/${name}.md" ]]; then
        warn "readme-catalog" "README lists agent '$name' but agents/${name}.md not found"
        ((readme_warns++)) || true
      fi
    done

    # Reverse: every agents/ file must have a README entry
    for agent_file in "$agents_dir"/*.md; do
      [[ ! -f "$agent_file" ]] && continue
      local name
      name="$(basename "$agent_file" .md)"
      local found=0
      for readme_name in "${readme_agents[@]}"; do
        if [[ "$readme_name" == "$name" ]]; then
          found=1
          break
        fi
      done
      if [[ $found -eq 0 ]]; then
        warn "readme-catalog" "agents/${name}.md exists but not listed in README Current Agents"
        ((readme_warns++)) || true
      fi
    done
  fi

  # --- Rules catalog ---
  local rules_dir="$DOTFILES_DIR/rules"
  if [[ -d "$rules_dir" ]]; then
    # Extract rule names from README "Current Rules" section H3 headings
    # Format: ### Display Name (`rules/<name>.md`)
    local readme_rules=()
    local in_section=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]] && ! "$line" =~ ^### ]]; then
        if [[ "$line" =~ ^##[[:space:]]Current[[:space:]]Rules ]]; then
          in_section=1
        else
          in_section=0
        fi
      fi
      if [[ $in_section -eq 1 && "$line" =~ rules/([a-zA-Z0-9_-]+)\.md ]]; then
        readme_rules+=("${BASH_REMATCH[1]}")
      fi
    done < "$readme"

    # Forward: every README entry must have a rules/ file
    for name in "${readme_rules[@]}"; do
      if [[ ! -f "$rules_dir/${name}.md" ]]; then
        warn "readme-catalog" "README lists rule '$name' but rules/${name}.md not found"
        ((readme_warns++)) || true
      fi
    done

    # Reverse: every rules/ file must have a README entry
    for rule_file in "$rules_dir"/*.md; do
      [[ ! -f "$rule_file" ]] && continue
      local name
      name="$(basename "$rule_file" .md)"
      local found=0
      for readme_name in "${readme_rules[@]}"; do
        if [[ "$readme_name" == "$name" ]]; then
          found=1
          break
        fi
      done
      if [[ $found -eq 0 ]]; then
        warn "readme-catalog" "rules/${name}.md exists but not listed in README Current Rules"
        ((readme_warns++)) || true
      fi
    done
  fi

  local sections_checked=0
  [[ -d "$DOTFILES_DIR/agents" ]] && ((sections_checked++)) || true
  [[ -d "$DOTFILES_DIR/rules" ]] && ((sections_checked++)) || true

  if [[ $sections_checked -gt 0 && $readme_warns -eq 0 ]]; then
    ok "readme-catalog" "README catalog sections consistent (agents/rules)"
  fi
}

# --- Check web/instructions.md sync drift ---
# Detects drift between source-of-truth files and the curated web distillate.
# Two layers:
#   (a) Heuristic — every agent on disk must appear as a row in the Agent Catalog table
#   (b) Manifest — diff-aware: source file change without web/instructions.md change warns
# Override: a "Web-Sync-Skip: <reason>" trailer in any commit since the diff base
# suppresses the manifest layer (with a loud, auditable WARN).
check_web_sync_drift() {
  local web_file="web/instructions.md"
  local warn_start=$warn_count

  # If the distillate is missing entirely, skip both layers with a clear message
  if [[ ! -f "$DOTFILES_DIR/$web_file" ]]; then
    warn "web-sync" "$web_file not found — drift check skipped"
    return
  fi

  # --- Heuristic layer (always runs) ---
  local agent_files=()
  while IFS= read -r d; do
    agent_files+=("$d")
  done < <(find "$DOTFILES_DIR/agents" -mindepth 1 -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)

  local agent_file agent_name
  for agent_file in "${agent_files[@]}"; do
    agent_name="$(basename "$agent_file" .md)"
    [[ "$agent_name" =~ ^[a-z][a-z0-9_-]*$ ]] || continue
    if ! grep -qE "^\| \`$agent_name\` \|" "$DOTFILES_DIR/$web_file"; then
      warn "web-sync" "agent '$agent_name' missing from Agent Catalog table in $web_file"
      detail "Expected a row beginning with: | \`$agent_name\` |"
    fi
  done

  # --- Manifest layer (diff-aware) ---
  # Determine the right base. Prefer --fork-point so an "Update branch" merge
  # commit on the feature branch does not include incoming dev commits in the diff.
  local base=""
  base=$(git -C "$DOTFILES_DIR" merge-base --fork-point origin/dev HEAD 2>/dev/null) || base=""
  if [[ -z "$base" ]]; then
    base=$(git -C "$DOTFILES_DIR" merge-base HEAD '@{upstream}' 2>/dev/null) || base=""
  fi
  if [[ -z "$base" ]]; then
    base=$(git -C "$DOTFILES_DIR" merge-base HEAD origin/dev 2>/dev/null) || base=""
  fi

  if [[ -z "$base" ]]; then
    # "Unable to verify" must not read as "verified clean" — emit a visible
    # SKIP instead of an OK so runs on shallow/untracked clones are auditable.
    skip "web-sync" "manifest layer skipped — no diff base reachable (origin/dev or @{upstream}); heuristic layer only"
    return
  fi

  local head_sha=""
  head_sha=$(git -C "$DOTFILES_DIR" rev-parse HEAD 2>/dev/null) || head_sha=""
  if [[ -z "$head_sha" ]] || [[ "$head_sha" == "$base" ]]; then
    skip "web-sync" "manifest layer skipped — HEAD is at the diff base (no commits since base); heuristic layer only"
    return
  fi

  local is_shallow=""
  is_shallow=$(git -C "$DOTFILES_DIR" rev-parse --is-shallow-repository 2>/dev/null) || is_shallow="false"
  if [[ "$is_shallow" == "true" ]]; then
    warn "web-sync" "shallow clone — diff layer may miss commits beyond fetch depth"
  fi

  # Override: "Web-Sync-Skip: <reason>" trailer (reason text required)
  local trailer_line=""
  trailer_line=$(git -C "$DOTFILES_DIR" log "$base..HEAD" --format=%B 2>/dev/null \
    | grep -E "^Web-Sync-Skip:[[:space:]]+\S" | head -1) || trailer_line=""
  if [[ -n "$trailer_line" ]]; then
    local reason=""
    reason=$(printf '%s' "$trailer_line" | sed -E 's/^Web-Sync-Skip:[[:space:]]+//')
    warn "web-sync" "override active via Web-Sync-Skip trailer: \"$reason\" — manifest layer suppressed"
    detail "Override applies to all manifest pairs in this push. Heuristic layer still ran above."
    return
  fi

  # Collect changed files (portable; no mapfile)
  local changed_files=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && changed_files+=("$line")
  done < <(git -C "$DOTFILES_DIR" diff --name-only "$base" HEAD 2>/dev/null)

  if [[ ${#changed_files[@]} -eq 0 ]]; then
    if [[ $warn_count -eq $warn_start ]]; then
      ok "web-sync" "no Skill Catalog drift detected"
    fi
    return
  fi

  # Helper: was this exact path changed?
  file_in_diff() {
    local target="$1" f
    for f in "${changed_files[@]}"; do
      [[ "$f" == "$target" ]] && return 0
    done
    return 1
  }

  local web_changed=0
  if file_in_diff "$web_file"; then
    web_changed=1
  fi

  # Pair: catalog-bearing files (warn at most once across this category)
  local catalog_files=(
    "AGENTS.md"
    "rules/agent-first-selection.md"
  )
  local f catalog_hit=""
  for f in "${catalog_files[@]}"; do
    if file_in_diff "$f"; then
      catalog_hit="$f"
      break
    fi
  done
  if [[ -n "$catalog_hit" ]] && [[ $web_changed -eq 0 ]]; then
    warn "web-sync" "$catalog_hit changed but $web_file untouched — review Skill Catalog table"
    detail "Target: ## Skill Catalog table in $web_file"
  fi

  # Pair: a monolithic agent file changed (ADR-074)
  local skill_pattern_changed=()
  local file
  for file in "${changed_files[@]}"; do
    if [[ "$file" =~ ^agents/[^/]+\.md$ ]]; then
      skill_pattern_changed+=("$file")
    fi
  done
  if [[ ${#skill_pattern_changed[@]} -gt 0 ]] && [[ $web_changed -eq 0 ]]; then
    local first="${skill_pattern_changed[0]}"
    local rest_count=$((${#skill_pattern_changed[@]} - 1))
    local descr="$first"
    if [[ $rest_count -gt 0 ]]; then
      descr="$first +$rest_count more"
    fi
    warn "web-sync" "agent file(s) changed ($descr) but $web_file untouched — review Agent Catalog table"
    detail "Changed: ${skill_pattern_changed[*]}"
    detail "Target: ## Skill Catalog table in $web_file"
  fi

  # Pair: mirrored rules
  local mirrored_rules=(
    orchestrator-protocol plan-before-code agent-first-selection
    research-parallelism consensus-by-replication github-flow conventional-commits
    semver-tagging pr-template-standard adr-required
    debian-baseline post-implementation-review structured-review-format
    no-mcp-servers secrets-guard gh-identity-guard script-output-conventions
  )
  local rule changed_rules=()
  for rule in "${mirrored_rules[@]}"; do
    if file_in_diff "rules/${rule}.md"; then
      changed_rules+=("$rule")
    fi
  done
  if [[ ${#changed_rules[@]} -gt 0 ]] && [[ $web_changed -eq 0 ]]; then
    warn "web-sync" "mirrored rule(s) changed (${changed_rules[*]}) but $web_file untouched — review matching section(s)"
    detail "Target: matching sections in $web_file (see Documentation Sync Map in CONTRIBUTING.md)"
  fi

  if [[ $warn_count -eq $warn_start ]]; then
    ok "web-sync" "no Skill Catalog or section drift detected"
  fi
}

# --- Check delegation map ---
# Verifies that agents referencing other agents via "delegate to" point to real agents.
check_delegation_map() {
  local agents_dir="$DOTFILES_DIR/agents"
  [[ ! -d "$agents_dir" ]] && return

  local delegation_count=0
  local missing_count=0

  for agent_file in "$agents_dir"/*.md; do
    [[ ! -f "$agent_file" ]] && continue
    local name
    name="$(basename "$agent_file" .md)"
    local body
    body="$(get_body_after_frontmatter "$agent_file")"

    # Match "delegate to <agent-name>" — backtick-wrapped or bare hyphenated names
    # Skips "delegate to the ..." by requiring backtick or hyphenated name
    local delegates
    delegates="$(echo "$body" | grep -oE 'delegate to (the )?`([a-z][a-z0-9_-]*)`' 2>/dev/null | \
      sed -E 's/.*`([^`]+)`.*/\1/' | sort -u || true)"
    # Also match bare "delegate to <hyphenated-name>" (must contain a hyphen to avoid common words)
    local bare_delegates
    bare_delegates="$(echo "$body" | grep -oE 'delegate to ([a-z][a-z0-9]*-[a-z0-9-]*)' 2>/dev/null | \
      sed -E 's/delegate to //' | sort -u || true)"
    delegates="$(printf '%s\n%s' "$delegates" "$bare_delegates" | sort -u)"

    for delegate in $delegates; do
      [[ -z "$delegate" ]] && continue
      ((delegation_count++)) || true

      # Skip external agents
      local is_external=0
      for ext in "${EXTERNAL_AGENTS[@]}"; do
        if [[ "$delegate" == "$ext" ]]; then
          is_external=1
          break
        fi
      done
      [[ $is_external -eq 1 ]] && continue

      # Check agent file exists
      if [[ ! -f "$agents_dir/${delegate}.md" ]]; then
        warn "delegation" "agents/${name}.md delegates to '$delegate' but agents/${delegate}.md not found"
        ((missing_count++)) || true
      fi
    done
  done

  if [[ $delegation_count -gt 0 && $missing_count -eq 0 ]]; then
    ok "delegation" "All delegation references resolved ($delegation_count references)"
  elif [[ $delegation_count -eq 0 ]]; then
    info "No delegation references found in agent wrappers"
  fi
}

# --- Check relative links ---
# Verifies that relative markdown links in .md files resolve to real files.
check_relative_links() {
  local link_count=0
  local broken_count=0

  # Find all .md files in the repo (exclude .git)
  while IFS= read -r md_file; do
    [[ ! -f "$md_file" ]] && continue
    local dir
    dir="$(dirname "$md_file")"
    local rel_path="${md_file#"$DOTFILES_DIR"/}"

    # Skip relative-link check on superseded ADRs. Per rules/adr-required.md
    # the body of a superseded ADR is frozen — it may legitimately reference
    # files that the superseding ADR deletes.
    if [[ "$rel_path" == adrs/*.md ]] && \
       grep -q '^\*\*Status:\*\* Superseded by' "$md_file" 2>/dev/null; then
      continue
    fi

    # Extract markdown links: [text](path). POSIX ERE has no negative lookahead,
    # so we match ALL [text](target) links and filter absolute URLs / mailto in
    # the loop below (pure #anchor links drop out via the empty-target guard).
    local links
    links="$(grep -oE '\[[^]]*\]\([^)]+\)' "$md_file" 2>/dev/null | \
      sed -E 's/\[[^]]*\]\(//;s/\)$//' || true)"

    for link in $links; do
      [[ -z "$link" ]] && continue
      # Skip placeholder links (e.g., NNN-title.md in templates)
      [[ "$link" =~ ^[A-Z]{3}- ]] && continue
      # Skip absolute URLs and mailto (the old PCRE lookahead excluded these)
      case "$link" in
        http://*|https://*|mailto:*) continue ;;
      esac
      # Strip anchor fragments from link target
      local target="${link%%#*}"
      [[ -z "$target" ]] && continue
      ((link_count++)) || true

      # Resolve relative to the file's directory
      local resolved="$dir/$target"
      if [[ ! -e "$resolved" ]]; then
        error "links" "$rel_path: broken link '$link' — target not found"
        ((broken_count++)) || true
      fi
    done
  done < <(find "$DOTFILES_DIR" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' -type f)

  if [[ $link_count -gt 0 && $broken_count -eq 0 ]]; then
    ok "links" "All relative links valid ($link_count links)"
  elif [[ $link_count -eq 0 ]]; then
    info "No relative markdown links found"
  fi
}

# --- Check hooks ---
check_hooks() {
  # Check that hook scripts referenced by settings.json exist and are executable
  local settings_file="$DOTFILES_DIR/settings.json"
  if [[ -f "$settings_file" ]]; then
    # Extract command strings from hooks config
    local commands
    commands="$(grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$settings_file" 2>/dev/null | sed 's/"command"[[:space:]]*:[[:space:]]*"//;s/"$//' || true)"
    # Iterate per command (one grep match per line) rather than word-splitting
    # the whole set, so a command with flags (bash -x …) or interpreter prefix
    # is parsed correctly and the warning shows the full command string.
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      # The script path is the first whitespace token ending in .sh — tolerant
      # of a "bash"/"bash -x" prefix or a bare path.
      local script_path="" tok
      for tok in $cmd; do
        if [[ "$tok" == *.sh ]]; then
          script_path="${tok/#\~/$HOME}"
          break
        fi
      done
      [[ -z "$script_path" ]] && continue
      if [[ ! -f "$script_path" ]]; then
        warn "hooks" "settings.json references '$cmd' but file not found at $script_path"
      elif [[ ! -x "$script_path" ]]; then
        warn "hooks" "$script_path exists but is not executable — run chmod +x"
      fi
    done <<< "$commands"
  fi

  # Git-only hooks are not referenced by settings.json
  # (they are installed into .git/hooks/ by setup.sh), so check them explicitly.
  local git_hook
  for git_hook in "$DOTFILES_DIR/hooks/secrets-guard.sh" "$DOTFILES_DIR/hooks/gh-identity-guard.sh"; do
    if [[ ! -f "$git_hook" ]]; then
      error "hooks" "git hook script not found: ${git_hook#"$DOTFILES_DIR"/}"
    elif [[ ! -x "$git_hook" ]]; then
      warn "hooks" "${git_hook#"$DOTFILES_DIR"/} exists but is not executable — run chmod +x"
    fi
  done
}

# --- Check hook scripts pass shellcheck (security-critical; ERROR-gated) ---
# Hooks enforce security boundaries; a shellcheck defect can silently disable
# one. Findings are ERRORs (blocking). For a genuine false positive, add a
# reviewed inline `# shellcheck disable=SCxxxx` to the hook. SKIP (non-fatal)
# when shellcheck is not installed so CI/dev without it is not blocked.
check_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    # WARN, not SKIP: CI runners ship shellcheck, so a host without it can
    # pass pre-push on a change CI will reject. Same missing-tool posture as
    # check_frozen_scripts. Install: brew/apt install shellcheck.
    warn "shellcheck" "shellcheck not installed — lint skipped locally but ENFORCED in CI (install to close the gap)"
    return
  fi
  local scripts=() f
  while IFS= read -r f; do
    scripts+=("$f")
  done < <(find "$DOTFILES_DIR/hooks" "$DOTFILES_DIR/scripts/lib" \
             "$DOTFILES_DIR"/skills/*/scripts -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort)
  if (( ${#scripts[@]} == 0 )); then
    skip "shellcheck" "no .sh files in hooks/, scripts/lib/, or skills/*/scripts/"
    return
  fi
  # --format=gcc emits exactly one line per finding, so the loop below counts
  # findings (not multi-line context blocks) — one error() per real defect.
  # Capture stdout only; shellcheck's own diagnostics go to stderr.
  local sc_output sc_rc
  sc_output="$(shellcheck --format=gcc "${scripts[@]}" 2>/dev/null)" && sc_rc=0 || sc_rc=$?
  if (( sc_rc == 0 )); then
    ok "shellcheck" "hooks/*.sh + scripts/lib/*.sh + skills/*/scripts/*.sh — ${#scripts[@]} file(s) clean"
  elif [[ -n "$sc_output" ]]; then
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      error "shellcheck" "$line"
    done <<< "$sc_output"
  else
    error "shellcheck" "shellcheck exited $sc_rc with no parseable output — rerun: shellcheck hooks/*.sh scripts/lib/*.sh"
  fi
}

# --- Check scripts/lib/*.sh self-tests pass (sourced-helper integrity) ---
# Each scripts/lib/*.sh exposes a --self-test mode (rules/script-output-conventions.md,
# ADR-061). A defect in a sourced helper silently corrupts every script that
# sources it, so a self-test failure is an ERROR (blocking). The libs are run
# as a subprocess (bash "$lib" --self-test), never sourced, so validate.sh's
# own bash-4.0 floor does not constrain the bash-3.2-safe libs. SKIP when the
# directory is absent or empty.
check_lib_selftests() {
  local lib_dir="$DOTFILES_DIR/scripts/lib"
  if [[ ! -d "$lib_dir" ]]; then
    skip "lib-selftest" "scripts/lib/ not present — nothing to test"
    return
  fi
  local libs=() f
  while IFS= read -r f; do
    libs+=("$f")
  done < <(find "$lib_dir" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort)
  if (( ${#libs[@]} == 0 )); then
    skip "lib-selftest" "no .sh files in scripts/lib/"
    return
  fi
  local lib name out rc line
  for lib in "${libs[@]}"; do
    name="$(basename "$lib")"
    out="$(bash "$lib" --self-test 2>&1)" && rc=0 || rc=$?
    if (( rc == 0 )); then
      ok "lib-selftest" "$name — self-tests passed"
    else
      error "lib-selftest" "$name — self-tests failed (exit $rc)"
      while IFS= read -r line; do
        [[ -n "$line" ]] && detail "$line"
      done <<< "$out"
    fi
  done
}

# --- Check documentation standards ---
check_documentation() {
  local doc_errors=0
  local doc_warns=0

  # Heading depth and code fence checks across all .md files (exclude templates and .git)
  while IFS= read -r md_file; do
    [[ ! -f "$md_file" ]] && continue
    local rel_path="${md_file#"$DOTFILES_DIR"/}"

    # Skip template files — they contain intentional placeholder content
    [[ "$rel_path" == templates/* ]] && continue

    # Check heading depth
    local line_num=0
    while IFS= read -r line; do
      ((line_num++)) || true
      # Match H5+ (##### or deeper)
      if [[ "$line" =~ ^#{5,}[[:space:]] ]]; then
        error "docs" "$rel_path:$line_num: heading depth exceeds maximum (H5+ not permitted)"
        ((doc_errors++)) || true
      # Match H4 (####) — warning only
      elif [[ "$line" =~ ^#{4}[[:space:]] ]]; then
        warn "docs" "$rel_path:$line_num: H4 heading — consider restructuring to stay within H3 depth"
        ((doc_warns++)) || true
      fi
    done < "$md_file"

    # Check code fence language tags (tracks backtick count for nested fences)
    local fence_len=0
    line_num=0
    while IFS= read -r line; do
      ((line_num++)) || true
      if [[ "$line" =~ ^(\`{3,}) ]]; then
        local backticks="${BASH_REMATCH[1]}"
        local blen=${#backticks}
        local rest="${line:$blen}"
        local rest_stripped="${rest//[[:space:]]/}"

        if [[ $fence_len -eq 0 ]]; then
          # Opening fence
          fence_len=$blen
          if [[ -z "$rest_stripped" ]]; then
            warn "docs" "$rel_path:$line_num: code fence without language tag"
            ((doc_warns++)) || true
          fi
        elif [[ $blen -ge $fence_len && -z "$rest_stripped" ]]; then
          # Closing fence — at least as many backticks, nothing else on line
          fence_len=0
        fi
      fi
    done < "$md_file"

    # A non-zero fence_len at EOF means a fence opened but never closed.
    if [[ $fence_len -ne 0 ]]; then
      warn "docs" "$rel_path: unterminated code fence (opened but not closed before EOF)"
      ((doc_warns++)) || true
    fi

  done < <(find "$DOTFILES_DIR" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' -type f)

  # README.md structural checks
  local readme="$DOTFILES_DIR/README.md"
  if [[ -f "$readme" ]]; then
    # Must have an H1
    if ! grep -q '^# ' "$readme"; then
      warn "docs" "README.md: missing H1 title"
      ((doc_warns++)) || true
    fi
    # Must have at least one H2
    if ! grep -q '^## ' "$readme"; then
      warn "docs" "README.md: no H2 sections found"
      ((doc_warns++)) || true
    fi
  fi

  # CLAUDE.md structural checks
  local claudemd="$DOTFILES_DIR/CLAUDE.md"
  if [[ -f "$claudemd" ]]; then
    if ! grep -q '^# ' "$claudemd"; then
      warn "docs" "CLAUDE.md: missing H1 title"
      ((doc_warns++)) || true
    fi
  fi

  if [[ $doc_errors -eq 0 && $doc_warns -eq 0 ]]; then
    ok "docs" "All documentation checks passed"
  elif [[ $doc_errors -eq 0 ]]; then
    ok "docs" "Documentation checks passed with $doc_warns warnings"
  fi
}

# --- Check lockstep duplication between hook pairs (ADR-083) ---
# The secret-pattern set and the identity-helper functions are deliberately
# duplicated across the two guard-hook pairs (ADR-053/ADR-054: no shared
# source for security-critical hooks) with "keep in lockstep" comments. This
# check makes the lockstep mechanical: byte-identical or ERROR. Drift in one
# hook of a pair silently weakens the layer it belongs to, so this is
# ERROR-gated like check_shellcheck and check_frozen_scripts.

# Extract a named shell function body from a file. Matches the repo's two
# function shapes: a one-liner (`name() { ...; }` on one line) or a multi-line
# body whose closing `}` sits alone at column 0. Exits non-zero if the
# function is not found in either shape — callers must treat that as a loud
# failure, never as an empty-vs-empty match.
extract_function() {
  local file="$1" fn="$2"
  awk -v fn="$fn" '
    !infn && index($0, fn "() {") == 1 {
      print
      if ($0 ~ /\}[[:space:]]*$/) { found = 1; exit }
      infn = 1
      next
    }
    infn { print; if ($0 == "}") { found = 1; exit } }
    END { exit found ? 0 : 1 }
  ' "$file"
}

# Compare one extraction target across a hook pair.
#   $1 = target kind: "var" (grep ^NAME=) or "func" (extract_function)
#   $2 = target name, $3/$4 = the two files (repo-relative)
lockstep_compare() {
  local kind="$1" name="$2" file_a="$3" file_b="$4"
  local a b
  if [[ "$kind" == "var" ]]; then
    a="$(grep -E "^${name}=" "$DOTFILES_DIR/$file_a" || true)"
    b="$(grep -E "^${name}=" "$DOTFILES_DIR/$file_b" || true)"
  else
    a="$(extract_function "$DOTFILES_DIR/$file_a" "$name" || true)"
    b="$(extract_function "$DOTFILES_DIR/$file_b" "$name" || true)"
  fi

  if [[ -z "$a" || -z "$b" ]]; then
    error "lockstep" "$name not found in expected form in ${file_a} and/or ${file_b} — extractor cannot verify lockstep"
    return
  fi
  if [[ "$a" == "$b" ]]; then
    ok "lockstep" "$name byte-identical across ${file_a##*/} / ${file_b##*/}"
  else
    error "lockstep" "$name drift between ${file_a} and ${file_b} — the pair must stay byte-identical (ADR-053/ADR-054)"
  fi
}

check_lockstep_duplication() {
  local secrets_a="hooks/secrets-guard.sh" secrets_b="hooks/session-secrets-guard.sh"
  local ident_a="hooks/gh-identity-guard.sh" ident_b="hooks/session-gh-identity-guard.sh"
  local f
  for f in "$secrets_a" "$secrets_b" "$ident_a" "$ident_b"; do
    if [[ ! -f "$DOTFILES_DIR/$f" ]]; then
      error "lockstep" "$f missing — cannot verify hook-pair lockstep"
      return
    fi
  done

  lockstep_compare var  SECRET_PATTERNS  "$secrets_a" "$secrets_b"
  lockstep_compare var  GH_LOGIN_RE      "$ident_a" "$ident_b"
  lockstep_compare func sanitize         "$ident_a" "$ident_b"
  lockstep_compare func extract_host     "$ident_a" "$ident_b"
  lockstep_compare func is_valid_login   "$ident_a" "$ident_b"
  lockstep_compare func parse_owner_repo "$ident_a" "$ident_b"
}

# --- Check ruleset required-checks vs workflow job names (ADR-086) ---
# Fully offline: cross-checks the committed rulesets/*.json (normalized by
# scripts/rulesets.sh — one key per line, so a line-scan is reliable) against
# the effective status-check names of .github/workflows/*.yml jobs (the job's
# name: field, falling back to the job id). Catches the "renamed job turns a
# required check into a never-reporting context that blocks every merge"
# failure BEFORE it reaches live state. Live-vs-committed drift is the
# network-dependent sibling check owned by scripts/rulesets.sh --check.
check_ruleset_job_drift() {
  local rulesets_dir="$DOTFILES_DIR/rulesets"
  local wf_dir="$DOTFILES_DIR/.github/workflows"
  if [[ ! -d "$rulesets_dir" ]]; then
    skip "rulesets" "rulesets/ not present — ruleset-as-code not adopted, drift check skipped"
    return
  fi

  # Effective check names: job name: if present, else job id.
  local job_names
  job_names="$(awk '
    FNR==1 { if (job != "") print (jobname != "" ? jobname : job); job=""; jobname=""; in_jobs=0 }
    /^jobs:/ { in_jobs=1; next }
    in_jobs && /^[A-Za-z]/ { if (job != "") print (jobname != "" ? jobname : job); job=""; jobname=""; in_jobs=0 }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      if (job != "") print (jobname != "" ? jobname : job)
      job=$0; sub(/^  /,"",job); sub(/:.*/,"",job); jobname=""
      next
    }
    in_jobs && /^    name:[[:space:]]/ {
      jobname=$0; sub(/^    name:[[:space:]]*/,"",jobname); gsub(/^"|"$/,"",jobname); next
    }
    END { if (job != "") print (jobname != "" ? jobname : job) }
  ' "$wf_dir"/*.yml 2>/dev/null | sort -u)"

  if [[ -z "$job_names" ]]; then
    error "rulesets" "no workflow jobs parsed from .github/workflows/*.yml — extractor cannot verify required checks"
    return
  fi

  local f name ctx contexts had_issue=0
  for f in "$rulesets_dir"/*.json; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    contexts="$(grep -oE '"context": *"[^"]+"' "$f" | sed -E 's/"context": *"([^"]+)"/\1/')"
    if [[ -z "$contexts" ]] && grep -q 'required_status_checks' "$f"; then
      error "rulesets" "$name: required_status_checks present but no contexts parsed — regenerate via scripts/rulesets.sh --pull"
      had_issue=1
      continue
    fi
    while IFS= read -r ctx; do
      [[ -z "$ctx" ]] && continue
      if ! grep -qxF "$ctx" <<< "$job_names"; then
        error "rulesets" "$name: required check '$ctx' matches no workflow job — a rename or removal will silently block every merge"
        had_issue=1
      fi
    done <<< "$contexts"
  done

  # Inverse: jobs not required by any committed ruleset (informational).
  # Deliberately-unrequired jobs are allowlisted so this WARN only fires on
  # NEW unrequired jobs: release runs on main pushes (not a PR check);
  # check-merge-method posts an advisory comment on promotion PRs by design.
  local unrequired_ok=" release check-merge-method check-pins "
  local all_contexts job
  all_contexts="$(grep -hoE '"context": *"[^"]+"' "$rulesets_dir"/*.json 2>/dev/null | sed -E 's/"context": *"([^"]+)"/\1/' | sort -u)"
  while IFS= read -r job; do
    [[ -z "$job" ]] && continue
    [[ "$unrequired_ok" == *" $job "* ]] && continue
    if ! grep -qxF "$job" <<< "$all_contexts"; then
      warn "rulesets" "job '$job' is not required as a status check by any committed ruleset — confirm this is intentional (allowlist in check_ruleset_job_drift if so)"
    fi
  done <<< "$job_names"

  if [[ $had_issue -eq 0 ]]; then
    ok "rulesets" "all required-check contexts map to workflow jobs"
  fi
}

# --- Check symlinks ---
check_frozen_scripts() {
  local pin_file="$DOTFILES_DIR/scripts/wim/.frozen-shas"

  if [[ ! -f "$pin_file" ]]; then
    if [[ -d "$DOTFILES_DIR/scripts/wim" ]]; then
      error "frozen-scripts" "scripts/wim/ exists but .frozen-shas is missing"
    fi
    return
  fi

  # Resolve a SHA-256 tool: sha256sum (Debian baseline) or shasum -a 256 (macOS)
  local -a sha_cmd
  if command -v sha256sum >/dev/null 2>&1; then
    sha_cmd=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    sha_cmd=(shasum -a 256)
  else
    warn "frozen-scripts" "no SHA-256 tool (sha256sum or shasum) found — frozen-script verification skipped"
    return
  fi

  local checked=0 mismatched=0
  while IFS= read -r line; do
    # Skip blank lines and comments
    [[ -z "${line// /}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Format: "<sha256>  <relative-path>" (sha256sum's two-space separator)
    if [[ ! "$line" =~ ^([a-fA-F0-9]{64})[[:space:]]+(.+)$ ]]; then
      error "frozen-scripts" "malformed entry in .frozen-shas: $line"
      continue
    fi
    local expected="${BASH_REMATCH[1]}"
    local relpath="${BASH_REMATCH[2]}"
    local abspath="$DOTFILES_DIR/$relpath"

    if [[ ! -f "$abspath" ]]; then
      error "frozen-scripts" "pinned file missing: $relpath"
      continue
    fi

    local actual
    actual=$("${sha_cmd[@]}" "$abspath" | cut -d' ' -f1)
    checked=$((checked + 1))
    if [[ "$actual" != "$expected" ]]; then
      error "frozen-scripts" "$relpath SHA-256 mismatch (expected ${expected:0:12}…, got ${actual:0:12}…) — frozen scripts must not be edited"
      mismatched=$((mismatched + 1))
    fi
  done < "$pin_file"

  if (( mismatched == 0 && checked > 0 )); then
    ok "frozen-scripts" "$checked file(s) match .frozen-shas"
  fi
}

check_symlinks() {
  local pairs=(
    "agents:$HOME/.claude/agents"
    "rules:$HOME/.claude/rules"
    "hooks:$HOME/.claude/hooks"
    "settings.json:$HOME/.claude/settings.json"
    "commands:$HOME/.claude/commands"
    "skills:$HOME/.claude/skills"
  )

  for pair in "${pairs[@]}"; do
    local src_rel="${pair%%:*}"
    local tgt="${pair##*:}"
    local src="$DOTFILES_DIR/$src_rel"

    if [[ ! -L "$tgt" ]]; then
      warn "symlinks" "$tgt is not a symlink — run setup.sh"
      continue
    fi

    local actual
    actual="$(readlink "$tgt" 2>/dev/null || true)"
    local expected="$src"

    if [[ "$actual" != "$expected" ]]; then
      warn "symlinks" "$tgt points to $actual, expected $expected — run setup.sh"
    fi
  done
}

# --- Main ---
main() {
  echo "Agent Framework — Validation"
  echo "=================================="
  echo ""

  # Agents (monolithic — ADR-074)
  echo "Agents:"
  local agents_dir="$DOTFILES_DIR/agents"
  if [[ -d "$agents_dir" ]]; then
    for agent_file in "$agents_dir"/*.md; do
      [[ ! -f "$agent_file" ]] && continue
      check_agent "$agent_file"
    done
  else
    info "No agents/ directory found"
  fi
  echo ""

  # Agent catalog
  echo "Agent Catalog:"
  check_agent_catalog
  echo ""

  # README catalog
  echo "README Catalog:"
  check_readme_catalog
  echo ""

  # Web sync drift
  echo "Web Sync:"
  check_web_sync_drift
  echo ""

  # Delegation map
  echo "Delegation Map:"
  check_delegation_map
  echo ""

  # Relative links
  echo "Links:"
  check_relative_links
  echo ""

  # ADRs
  echo "ADRs:"
  check_adrs
  echo ""

  # Rule Enforcement lines
  echo "Enforcement Lines:"
  check_enforcement_line
  echo ""

  # MCP package references in distributed prose
  echo "MCP Prose References:"
  check_no_mcp_prose
  echo ""

  # Plugin/MCP manifest files
  echo "MCP Manifests:"
  check_no_mcp_manifests
  echo ""

  # Hooks
  echo "Hooks:"
  check_hooks
  echo ""

  echo "Shellcheck:"
  check_shellcheck
  echo ""

  echo "Lib Self-Tests:"
  check_lib_selftests
  echo ""

  echo "Lockstep:"
  check_lockstep_duplication
  echo ""

  echo "Rulesets:"
  check_ruleset_job_drift
  echo ""

  # Documentation
  echo "Documentation:"
  check_documentation
  echo ""

  # Branch PR state
  echo "Branch:"
  check_branch_pr_state
  echo ""

  # GitHub identity
  echo "GitHub Identity:"
  check_gh_identity
  echo ""

  # Frozen scripts
  echo "Frozen Scripts:"
  check_frozen_scripts
  echo ""

  # Symlinks
  echo "Symlinks:"
  check_symlinks
  echo ""

  # Summary
  echo "=================================="
  if [[ $error_count -gt 0 ]]; then
    echo "FAIL — $error_count errors, $warn_count warnings"
    exit 1
  else
    echo "PASS — 0 errors, $warn_count warnings"
    exit 0
  fi
}

main
