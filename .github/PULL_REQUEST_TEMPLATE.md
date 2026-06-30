## Summary

<!-- What this PR does and why. The "why" is mandatory. 2-4 sentences. -->

## Type of Change

- [ ] `feat` — new feature
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `chore` — maintenance
- [ ] `refactor` — restructuring without behavior change
- [ ] `test` — adding or updating tests
- [ ] `ci` — CI/CD changes
- [ ] `style` — formatting or linting fixes
- [ ] Breaking change (add `!` to PR title)

## Test Plan

<!-- How the change was verified. Do not delete this section. -->
<!-- Valid entries: specific tests run, validate.sh output, "No testable behavior changed" -->

## Checklist

### All PRs

- [ ] `./validate.sh` passes with 0 errors
- [ ] No credentials, tokens, or machine-specific paths in any file
- [ ] Per-task review gate completed for each task in this PR — `@linter` clean, tests pass, doc sync pairs updated, work-item state transitioned (see `rules/post-implementation-review.md`)

### Merge Method

| PR target | Method |
|---|---|
| `dev` (feature branches) | **Squash and merge** |
| `main` (release promotions from `dev`) | **Create a merge commit** |

Using the wrong merge method on `dev` → `main` promotions causes SHA divergence and persistent merge conflicts. See `rules/github-flow.md`.

## New Agent

_Delete this section if not adding a new agent._

### Agent File (`agents/<name>.md`)

- [ ] Single monolithic file — frontmatter + full expertise inline; no separate SKILL.md or wrapper
- [ ] `name` matches filename; `description` is a quoted string
- [ ] `tools:` is a minimal allowlist scoped to what the agent needs
- [ ] Body contains full domain knowledge — persona, scope, constraints, and expertise all inline

### README Update

- [ ] H3 entry added to README.md "Current Agents" section with file path and 1-sentence description
- [ ] Row added to AGENTS.md agent catalog table

### Security

- [ ] Tool lists are minimal — `Bash` present only on agents in validate.sh's `CLAUDE_BASH_ALLOWED` allowlist (ADR-069)
- [ ] No instructions to execute user-provided strings without sanitization
- [ ] Read-only constraint stated in agent description and body (for `*-expert` agents)

## New Rule

_Delete this section if not adding a new rule._

### Single-File Pattern

- [ ] `rules/<name>.md` created with YAML frontmatter (`description:` field)
- [ ] Scoping language (`does not apply to`, `skip for`) present when the rule has exclusions

### README Update

- [ ] H3 entry added to README.md "Current Rules" section with file path and 1-sentence description

### Validation

- [ ] `./validate.sh` passes with 0 errors — `readme-catalog` check shows no warnings

## Content Update

_Delete this section if not updating existing content._

- [ ] Agent file updated with the content change — all expertise is inline in `agents/<name>.md`
- [ ] validate.sh section coverage warnings reviewed

## Documentation Sync

_Delete this section if no documentation files were changed._

- [ ] All sync pairs from the Documentation Sync Map in CONTRIBUTING.md have been checked
- [ ] README.md directory tree updated if files were added/removed from `hooks/`, `scripts/`, `templates/`, or `adrs/`
- [ ] README.md catalog sections updated if skills, agents, or rules were added/removed
- [ ] `web/instructions.md` updated if a skill / agent catalog row was added, removed, or renamed, or if a mirrored rule was substantively edited (see Documentation Sync Map)
- [ ] CONTRIBUTING.md "Validation" section updated if validate.sh checks were added/removed
- [ ] `./validate.sh` passes with 0 errors — `readme-catalog` check shows no warnings

## Tooling / Infrastructure

_Delete this section if not changing validate.sh, setup.sh, or CONTRIBUTING.md._

- [ ] Schema changes (allowed/blocked field lists) are reflected in both validate.sh and CONTRIBUTING.md
- [ ] Existing agents still pass validation after changes
