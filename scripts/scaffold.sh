#!/usr/bin/env bash
#
# Agent Framework — Scaffold Script
#
# Creates a new monolithic agent or rule file from templates (ADR-074).
#
# Usage:
#   ./scripts/scaffold.sh agent <name>
#   ./scripts/scaffold.sh rule <name>
#
# Templates are read from templates/agent/ and templates/rule/.
# Placeholder {{NAME}} is replaced with the given name in all output files.
#
# Exit codes:
#   0 — files created successfully
#   1 — validation error or file already exists
#

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$REPO_DIR/templates"

# Shared output helpers (rules/script-output-conventions.md, ADR-061).
# shellcheck source=scripts/lib/log.sh
. "$REPO_DIR/scripts/lib/log.sh"

# scaffold exits on first error; map the old die() onto fatal() (err + exit 1).
die() { fatal "scaffold" "$*"; }

usage() {
  echo "Usage: $(basename "$0") agent|rule <name>"
  echo ""
  echo "  agent <name>  — Create a monolithic agents/<name>.md (ADR-074)"
  echo "  rule <name>   — Create rules/<name>.md"
  echo ""
  echo "Names must be lowercase letters, digits, and hyphens (max 64 chars)."
  exit 1
}

check_not_exists() {
  local file="$1"
  if [[ -e "$file" ]]; then
    die "already exists: ${file#"$REPO_DIR"/}"
  fi
}

replace_placeholder() {
  local file="$1" value="$2"
  local tmp
  tmp=$(mktemp)
  # Clean up the temp file on any failure path — under set -e a failed sed or
  # mv would otherwise exit and leak it. A successful mv consumes the temp,
  # so the rm -f is a harmless no-op on the success path.
  if ! sed "s/{{NAME}}/${value}/g" "$file" > "$tmp" || ! mv "$tmp" "$file"; then
    rm -f "$tmp"
    die "failed to substitute placeholder in ${file#"$REPO_DIR"/}"
  fi
}

validate_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z][a-z0-9-]{0,62}[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z]$ ]]; then
    die "invalid name '$name' — must be lowercase letters, digits, and hyphens (2-64 chars, no leading/trailing hyphens)"
  fi
  if [[ "$name" == *--* ]]; then
    die "invalid name '$name' — consecutive hyphens are not allowed"
  fi
}

scaffold_agent() {
  local name="$1"

  local agent_file="$REPO_DIR/agents/${name}.md"

  # Pre-flight: refuse if the target already exists
  check_not_exists "$agent_file"

  # Verify template exists
  local tmpl_agent="$TEMPLATES_DIR/agent/agent.md"
  [[ -f "$tmpl_agent" ]] || die "template not found: ${tmpl_agent#"$REPO_DIR"/}"

  # Create the monolithic agent file (ADR-074)
  cp "$tmpl_agent" "$agent_file"
  replace_placeholder "$agent_file" "$name"

  echo "Created:"
  echo "  agents/${name}.md"
  echo ""
  echo "Next steps:"
  echo "  1. Fill in the TODOs (persona, scope, and the full expertise inline)"
  echo "  2. Add the agent to the catalog table in AGENTS.md"
  echo "  3. Run ./validate.sh to check consistency"
}

scaffold_rule() {
  local name="$1"

  local rule_file="$REPO_DIR/rules/${name}.md"

  # Pre-flight: refuse if the target already exists
  check_not_exists "$rule_file"

  # Verify template exists
  local tmpl_rule="$TEMPLATES_DIR/rule/rule.md"
  [[ -f "$tmpl_rule" ]] || die "template not found: ${tmpl_rule#"$REPO_DIR"/}"

  # Create the rule file
  cp "$tmpl_rule" "$rule_file"
  replace_placeholder "$rule_file" "$name"

  echo "Created:"
  echo "  rules/${name}.md"
  echo ""
  echo "Next steps:"
  echo "  1. Fill in the rule content"
  echo "  2. Run ./validate.sh to check consistency"
}

# --- Argument parsing ---
[[ $# -eq 2 ]] || usage

type_arg="$1"
name_arg="$2"

validate_name "$name_arg"

case "$type_arg" in
  agent) scaffold_agent "$name_arg" ;;
  rule)  scaffold_rule  "$name_arg" ;;
  *)     die "unknown type '$type_arg' (expected: agent, rule)" ;;
esac
