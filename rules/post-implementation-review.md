---
description: 'Run a review pass after each task and again before opening a PR; couple review completion to work-item state transitions'
---

# Post-Implementation Review

This rule defines a two-tier review gate: a **per-task gate** that runs after each work item completes, and a **pre-PR gate** that runs once before opening or updating the PR. Both apply to substantive implementation work. Trivial single-line fixes, typo corrections, and documentation-only edits are exempt.

## Per-Task Gate

After completing the work for an individual task (ADO Task, GitHub Issue, or other ticket), and **before starting the next task or moving the ticket to Closed**:

- **Run the linter agent** (`@linter`) on files changed by this task.
- **Verify tests pass** for the affected scope, where the project has a test suite. Do not skip failing tests — investigate and fix or flag them.
- **Self-review the diff** for unintended modifications, leftover debug code, or missed requirements.
- **Update documentation sync pairs** — for every changed file, update its paired documentation in the same task. Use the project's Documentation Sync Map (in `CONTRIBUTING.md` or equivalent) as the authoritative list. For this repo, key pairs include:
  - Adding or removing an agent: `agents/<name>.md`, README Current Agents section, `AGENTS.md` catalog row, `web/instructions.md` Agent Catalog, and `rules/agent-first-selection.md` routing row must all be updated.
  - Adding, removing, or editing an agent catalog row in `AGENTS.md` or `rules/agent-first-selection.md`: the matching row in the `web/instructions.md` Agent Catalog must be updated.
  - Adding or removing a rule: `rules/<name>.md` and README Current Rules section must be updated; if the rule is mirrored in the distillate, the corresponding section in `web/instructions.md` must be added or removed.
  - Substantively editing a mirrored rule (orchestrator-protocol, plan-before-code, agent-first-selection, research-parallelism, consensus-by-replication, github-flow, conventional-commits, semver-tagging, pr-template-standard, adr-required, debian-baseline, post-implementation-review, structured-review-format, no-mcp-servers, secrets-guard, gh-identity-guard, script-output-conventions): the matching section in `web/instructions.md` must be updated.
  - Adding or removing a hook script: `README.md` directory tree `hooks/` listing must be updated.
  - Changes to `validate.sh` checks: `CONTRIBUTING.md` Validation section must reflect the change.
- **Verify the README.md directory tree** reflects actual disk state when `hooks/`, `scripts/`, `templates/`, or `adrs/` contents change — the tree is not checked automatically by `validate.sh`.
- **Transition the ticket to Closed (or equivalent)** only after the gates above pass. Ticket state must reflect actual delivery progress in real time, not be batched until PR merge.

## Pre-PR Gate

Once all tasks for the PR are complete, before opening the PR (or pushing the final commit on an open PR):

- **Run `validate.sh`** when changes touch agents or rules in this repo (or the project's equivalent validation script).
- **Re-review the aggregate diff** for cross-task drift — file conflicts, README aggregation issues, doc-sync pairs touched by multiple tasks.
- **Confirm every task in the PR has its per-task gate evidence** (linter clean, tests passing, ticket Closed).

## When This Rule Does Not Apply

- Documentation-only edits, single-line fixes, or configuration changes where no test suite exists.
- PRs that deliver a single task — the per-task gate and pre-PR gate collapse into one review pass.

## Related

- ADR-045: per-task review gate within multi-task PRs
- ADR-039: documentation sync enforcement
