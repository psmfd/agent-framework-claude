# Contributing to Agent Framework

## Technology Standards

See [`standards/tooling.md`](standards/tooling.md) for the canonical list of languages, frameworks, platforms, and tooling. Agents and skills should reference this document when making technology choices or providing technology-specific guidance.

## Documentation Standards

See [`standards/documentation.md`](standards/documentation.md) for Markdown formatting rules, README conventions, and CLAUDE.md guidance. All `.md` files in this repo should follow those standards.

## Architecture

This repo uses a **monolithic single-file agent** architecture (ADR-074). Domain expertise, tool restrictions, model selection, and all behavioral guidance for each agent live in one file: `agents/<name>.md`. Rules are single-file `rules/<name>.md` (ADR-075). There are no separate skill files and no platform wrappers.

The framework has three layers:

- **Rules** (`rules/`) — always-loaded behavioral constraints for all sessions
- **Commands** (`commands/`) — slash commands (e.g. `/review`) that orchestrate agent fan-outs
- **Agents** (`agents/`) — monolithic domain-expert agents with inline expertise

### Naming Convention

Names use lowercase letters, numbers, and hyphens only. No leading, trailing, or consecutive hyphens. Max 64 characters.

- Agent file: `agents/<name>.md`; the `name:` frontmatter field must match the filename (without `.md`)
- Rule file: `rules/<name>.md`

### Hook Configuration

Hooks are configured in `settings.json` under the `hooks` key, keyed by Claude Code event name (PascalCase: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `WorktreeCreate`, `WorktreeRemove`, and others). The optional `matcher` field restricts a hook to specific tool names.

Git-native hooks (pre-commit, pre-push) are installed by `setup.sh` into `.git/hooks/` and run independently of the Claude Code hook system.

When adding a global guard hook, register it in `settings.json` and ensure the hook script in `hooks/` passes `shellcheck` (gated by `validate.sh`).

#### Global Destructive Command Guard

The `bash-destructive-guard.sh` hook is a global `PreToolUse` guard registered in `settings.json`. It fires on every Bash tool call across all agents and denies `rm` and `mv` commands targeting paths outside a configurable safe list.

Safe paths are defined in `~/.claude/bash-guard-safe-paths.conf` (created by `setup.sh`). `/tmp` and relative paths within the current project directory are always allowed. Paths containing shell metacharacters (`$`, backticks, pipes) are denied unconditionally. The command is split into segments (`&&`, `||`, `|`, `;`, newline) and a canonical verb is resolved past wrapper commands (`env`/`sudo`/`xargs`/`time`/`nice`/`nohup`/`command`/`builtin`), so `env rm`, a newline-hidden `rm`, `find -delete`/`-exec rm`, and shell-interpreter `-c` are caught while `git rm`/`grep rm` are not. Accepted gaps (defense-in-depth, not a sandbox) are listed in the hook header — e.g. a wrapper value-flag before the verb (`sudo -u root rm`), non-shell interpreters (`perl -e`), and quoted separators.

This guard works alongside the `Bash(rm:*)` and `Bash(mv:*)` entries in `permissions.allow` — the allow list suppresses the approval dialog and prevents silent subagent denial, while the hook controls actual execution. A hook deny always overrides an allow-list entry.

#### Global In-Session Secrets Guard

The `session-secrets-guard.sh` hook is a global `PreToolUse` guard registered in `settings.json` (matcher `^(Bash|Write|Edit|MultiEdit|NotebookEdit)$`). It is the in-session (layer 2) counterpart to the `secrets-guard.sh` pre-commit hook (layer 1) and shares its pattern set and overrides (`SKIP_SECRETS_GUARD=1`, `.secrets-guard-allowlist`). It denies tool calls that would surface a secret before it reaches disk: inline secret literals or credential-file reads in a `Bash` command, and PEM/AWS/GitHub-PAT material (or a sensitive/unencrypted-vault path) written via `Write`/`Edit`/`MultiEdit`/`NotebookEdit`. Only NEW content (`new_string`/`new_source`/`content`) is scanned, so edits that REMOVE a secret are never blocked. Write-capable tools fail CLOSED when the target path cannot be extracted; `Bash` with an empty command and unrecognized tools fail OPEN. See ADR-053. When changing the secret pattern set, update `hooks/secrets-guard.sh`, `hooks/session-secrets-guard.sh`, and `web/instructions.md` together (no shared source by design).

#### Global GH Identity Guard

A two-layer, fail-closed guard against pushing or mutating GitHub from the wrong account on a multi-account host (ADR-054):

- **In-session** (`session-gh-identity-guard.sh`) — a `PreToolUse` guard registered in `settings.json` (matcher `Bash`). A cheap string pre-check fires the identity probe only on a mutating `gh`/`git push` op, then denies it if the active login is wrong.
- **Git pre-push** (`gh-identity-guard.sh`) — a **git-native** hook (no `settings.json` entry) chained into `.git/hooks/pre-push` by `setup.sh` ahead of `validate.sh`. It closes the raw-terminal/IDE/script vector.

Signal is hybrid: a local-only (gitignored) `<repo>/.gh-expected-identity` pin (strict login match) when present, else repo accessibility. Fail closed on indeterminate identity; github.com only; CI/`GH_TOKEN` verifies access instead of login. Overrides (all announced): `GH_IDENTITY_OVERRIDE=<login>` (env var only — the in-session layer does not honor a command-string prefix, ADR-070), `.gh-identity-allowlist`, `SKIP_GH_IDENTITY_GUARD=1`. The identity logic is duplicated across the two bash hooks (no shared sourced lib) — keep them in lockstep.

The git pre-push hook is the first **git-only** hook category in this repo: unlike the Claude Code `PreToolUse` hooks, it has no `settings.json` entry. `validate.sh check_hooks` verifies the git-only scripts (`secrets-guard.sh`, `gh-identity-guard.sh`) exist and are executable.

#### Inline Agent-Level Hooks

Agent files can define hooks directly in their frontmatter using the `hooks:` field. These hooks are scoped to that specific agent and fire after global hooks. They are not configured in `settings.json`.

No agent in the current framework uses inline hooks. The pattern remains supported and is additive with global hooks — when present, the global destructive-command guard checks path safety first, then the per-agent guard applies further restrictions.

Inline hooks are not inspected by `validate.sh` — ensure hook scripts referenced in agent frontmatter exist and are tested manually.

#### Worktree Hooks (Claude Code Only)

The `WorktreeCreate` and `WorktreeRemove` hooks redirect worktree creation from `.claude/worktrees/` to `.wt_tmp/`. This avoids a path permission conflict where `.claude/` is a restricted write path and subagents cannot Edit/Write files inside worktrees placed there.

**WorktreeCreate** (`hooks/worktree-create.sh`):

- Creates worktrees under `.wt_tmp/<name>/` instead of the default `.claude/worktrees/<name>/`
- Stdout must contain only the absolute worktree path — any additional stdout causes a silent hang (Claude Code bug #27467). All git commands redirect output with `>/dev/null 2>&1`.
- Handles `.worktreeinclude` file copying (Claude Code disables automatic processing when a hook is registered); rejects symlink entries and entries whose parent resolves outside the repo root, and copies nested symlinks as links (ADR-070)
- Prunes orphaned worktrees on each invocation for crash recovery

**WorktreeRemove** (`hooks/worktree-remove.sh`):

- Cleans up residual `.wt_tmp/<name>/` directories after Claude Code removes the git worktree
- Only fires on clean session exit — abnormal exits leave orphans that the create hook prunes
- Runs `git worktree prune` to clean stale worktree metadata references

Both hooks are registered in `settings.json` under `WorktreeCreate` and `WorktreeRemove` keys. Both hooks have a 30 s timeout (the `timeout` field in `settings.json` is in seconds).

## Adding a New Agent

Use `scripts/scaffold.sh agent <name>` to create `agents/<name>.md` from the template. Then:

1. Fill in the agent's expertise, tool list, model, and all behavioral guidance in the scaffolded `agents/<name>.md`.

2. Add a catalog row to `AGENTS.md`, a table row to the README "Current Agents" section, a routing row in `rules/agent-first-selection.md`, and a row in the `web/instructions.md` Agent Catalog table.

3. Update the README directory tree — add `agents/<name>.md` and any files added to `hooks/`, `scripts/`, `templates/`, or `adrs/`.

4. Run validation:

   ```bash
   ./validate.sh
   ```

5. Open a PR using the PR template checklist.

## Adding a New Rule

Use `scripts/scaffold.sh rule <name>` to create `rules/<name>.md` from the template. Then:

1. Fill in the rule's behavioral guidance in the scaffolded `rules/<name>.md`, including the `**Enforcement:**` line (see the Rules frontmatter section below for the format and vocabulary).

2. Update README.md — add an H3 entry to "Current Rules" and add `rules/<name>.md` to the README directory tree (not checked by `validate.sh` — hand-verify).

3. Run `./validate.sh` and confirm the `readme-catalog` check passes.

4. Commit the file and open a PR using the PR template checklist.

## Adding a New Command

Commands are Claude Code slash commands (`commands/<name>.md`, symlinked to `~/.claude/commands/`).

1. Create the command file: `commands/<name>.md`. Use YAML frontmatter (`description` quoted, optional `argument-hint`, optional `allowed-tools`); the command name is the filename — do **not** add a `name` field. Arguments are surfaced to the body as `$ARGUMENTS`.
2. If the command codifies an agent fan-out, fan out via the native `Agent` tool (`subagent_type`), not any external tool, and cite `rules/research-parallelism.md` for the Return Contract.
3. Register distribution: add `"commands:commands"` to `CLAUDE_LINKS` in `setup.sh` (once; already present after the first command) and ensure the `check_symlinks` pair exists in `validate.sh`.
4. Update README.md — add an H3 entry under "Current Commands" and list the new file in the directory tree (not checked by `validate.sh`).
5. Run `./validate.sh`, commit all files together, and open a PR.

## Frontmatter Quick Reference

### Agent (`agents/<name>.md`)

```yaml
---
name: agent-name
description: 'What this agent does'
model: opus
tools: Read, Glob, Grep, Bash, WebFetch, WebSearch
disable-model-invocation: true
---
```

| Field | Required | Constraints |
| --- | --- | --- |
| `name` | Yes | Must match filename (without `.md`) |
| `description` | Yes | Always quoted |
| `model` | Yes | `opus`, `sonnet`, `haiku`, or full model ID |
| `tools` | Yes | Comma-separated string (not YAML list) |
| `disable-model-invocation` | Yes | Must be `true` |

Optional fields: `maxTurns`, `isolation`, `effort`, `background`, `hooks`

### Rules (`rules/<name>.md`)

```yaml
---
description: 'What this rule enforces'
paths:
  - "*.py"
---
```

| Field | Required | Constraints |
| --- | --- | --- |
| `description` | Optional | Quoted string recommended |
| `paths` | Optional | YAML list of glob patterns |

Rules without `paths` apply universally.

Every rule body carries an `**Enforcement:**` line immediately after its `# Title` (before the first paragraph), stating what mechanism — if any — actually gates the behavior the rule describes: `PreToolUse hook <name>`, `pre-commit hook <name>`, `pre-push hook <name>`, `validate.sh <check>`, `CI <workflow>.yml`, `GitHub Ruleset <name>`, or `self-report only`. List multiple mechanisms with `; ` when more than one applies. `self-report only` documents current enforcement reality — it does not diminish the rule's mandatory status. A rule with no automated check is exactly the kind of rule where the self-review diligence in `post-implementation-review.md` matters most. See ADR-084.

## PR Review

Every PR uses the checklist in `.github/PULL_REQUEST_TEMPLATE.md`. Key review areas:

### Per-task review gate

PRs that deliver multiple tasks (ADO Tasks, GitHub Issues, or equivalent work items) run a review gate **per task**, not just once before PR open. After each task and before starting the next:

- Run `@linter` on the files changed by that task
- Verify tests for the affected scope (where a test suite exists)
- Update documentation sync pairs that this task touched (see `## Documentation Sync Map` below)
- Transition the work item to Closed only after the gate passes — ticket state must track real-time delivery, not be batched until merge

A separate pre-PR pass (running `./validate.sh` and re-reviewing the aggregate diff) catches cross-task drift. Single-task PRs collapse the per-task and pre-PR gates into one pass. See `rules/post-implementation-review.md` and ADR-045.

### Automated (validate.sh)

- File structure completeness (agent file exists for each catalog entry)
- Frontmatter field presence and correctness
- Name consistency between filename and `name:` frontmatter field
- Execution-tool policy — `Bash` only on agents in the `CLAUDE_BASH_ALLOWED` allowlist (ADR-069)
- `disable-model-invocation: true` present on all agent files

### Manual review

- Agent body is self-sufficient — all expertise is inline
- Tool lists are minimal and match the agent's purpose
- Security: no credentials, no command injection patterns, `Bash` only on agents allowlisted in `validate.sh` (ADR-069)

## Security

- **Minimal tool lists.** Grant only the tools the agent's purpose requires. `Bash` requires a documented execution workflow in the agent body and an entry in `validate.sh`'s `CLAUDE_BASH_ALLOWED` allowlist; per-agent justifications are recorded in ADR-069. Read-only expert agents without such a workflow must not carry it.
- **No credentials in files.** Never embed tokens, keys, or passwords in any agent or rule file.
- **No command injection patterns.** Do not instruct agents to execute user-provided strings without sanitization.
- **Supply chain awareness.** Every agent file committed here is loaded into user sessions. Treat content changes with the same rigor as code changes.

## Architecture Decision Records

Significant architecture and convention decisions are recorded in `adrs/`. Each ADR follows the MADR minimal format (Context and Problem Statement, Considered Options, Decision Outcome).

- **When to create an ADR:** any decision about conventions, patterns, or architecture that is non-obvious and would benefit from recorded rationale — especially decisions where alternatives were seriously considered.
- **Numbering:** zero-padded three digits, sequential, never reused (e.g., `adrs/021-next-decision.md`).
- **Supersession:** when a decision is revised, update the original's Status to `Superseded by [ADR-NNN](NNN-title.md)` and create a new ADR. Do not edit the body of the superseded ADR.
- **Template:** see `adrs/TEMPLATE.md`.

## Commit Messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/) format:

```text
<type>(<scope>): <description>
```

Valid types: `feat`, `fix`, `perf`, `docs`, `chore`, `refactor`, `test`, `ci`, `style`. Scope is optional but recommended — use the agent name or affected area (e.g., `feat(linter):`, `fix(validate):`). Description is imperative, lowercase, no trailing period. No authorship attributions.

See `rules/conventional-commits.md` for the full specification.

## Validation

Run before every push (enforced by the pre-push hook installed by `setup.sh`):

```bash
./validate.sh
```

Requires **bash 4.0+** (associative arrays); it exits 2 with a clear version error on older bash, such as macOS system `/bin/bash` 3.2 — run it under a Homebrew bash.

| Exit code | Meaning |
| --- | --- |
| 0 | All checks passed (warnings are informational) |
| 1 | One or more errors found |
| 2 | Environment or precondition failure (e.g. bash older than 4.0) |

The script checks:

- Every agent in `AGENTS.md` has a matching `agents/<name>.md` file (bidirectional name presence)
- Frontmatter has all required fields with correct values
- Names match between filenames and `name:` frontmatter fields
- `disable-model-invocation: true` is present on all agent files
- Execution-tool policy — `Bash` only on agents in `CLAUDE_BASH_ALLOWED` (ADR-069)
- Symlinks from `~/.claude/` point to the correct targets
- Agent catalog drift (via `scripts/regen-agent-catalog.sh --check`, ADR-062): `AGENTS.md` is canonical — name presence vs `agents/*.md` (bidirectional), Domain/Use-when parity across `AGENTS.md` and the routing mirror (`rules/agent-first-selection.md`), and README Tier vs `AGENTS.md` / README Model vs agent `model:` frontmatter; content drift is an error (fix mirrors with `--write`)
- Agent delegation references resolve to real agent files
- Relative markdown links in all `.md` files resolve to existing targets (superseded ADRs are exempt — their bodies are frozen per the supersession-not-editing rule and may reference files removed by the superseding ADR)
- Markdown documentation standards (no H5+ headings, no language-less code fences)
- Branch/PR state (warns if current branch's PR is already merged)
- README.md catalog sections (Current Agents, Current Rules) match files on disk (warns on drift)
- `web/instructions.md` distillate stays in sync with sources (warns on drift) — every agent on disk must appear as a row in the Agent Catalog table; changes to `AGENTS.md`, `rules/agent-first-selection.md`, or any mirrored rule (orchestrator-protocol, plan-before-code, agent-first-selection, research-parallelism, consensus-by-replication, github-flow, conventional-commits, semver-tagging, pr-template-standard, adr-required, debian-baseline, post-implementation-review, structured-review-format, no-mcp-servers, secrets-guard, gh-identity-guard, script-output-conventions) without a corresponding `web/instructions.md` change emit a WARN. Override via a `Web-Sync-Skip: <reason>` Git trailer in any commit since the diff base — reason text is required and is logged loudly in the warning output. Run with `VALIDATE_VERBOSE=1 ./validate.sh` to see per-warning detail lines.
- Frozen work-item scripts (`scripts/wim/*.sh`) match the SHA-256 pins in `scripts/wim/.frozen-shas` (errors on drift) — see ADR-050 for the rationale and the `work-item-management-expert` agent `## Frozen Work-Item Scripts` section for the agent-side constraint.
- Active `gh` account can resolve the `origin` repository (warns on mismatch) — guards against the wrong identity on multi-account hosts. Skipped when `GH_TOKEN`/`GITHUB_TOKEN` is set or the remote is not `github.com`. See ADR-052/ADR-054 and `docs/multi-account-git-identity.md`.
- Hook and shared-lib scripts pass `shellcheck` (`hooks/*.sh` and `scripts/lib/*.sh`) — security-critical guards and sourced helpers must be statically clean; findings are errors (resolve a genuine false positive with a reviewed inline `# shellcheck disable=SCxxxx`). Skipped (non-fatal) when `shellcheck` is not installed.
- Shared-lib self-tests pass (`scripts/lib/*.sh --self-test`) — each sourced helper module is run as a subprocess and must exit 0; a failure is an error. Skipped when `scripts/lib/` is absent or empty. See ADR-061.
- Hook-pair lockstep (errors on drift) — the deliberately duplicated `SECRET_PATTERNS` (secrets-guard pair) and identity-helper functions (`sanitize`, `is_valid_login`, `parse_owner_repo`, `GH_LOGIN_RE`; gh-identity pair) must stay byte-identical across their two hooks. The extractor errors loudly when a target is not found in its expected shape rather than silently passing. See ADR-083.

## Documentation Sync Map

When changing one file in a pair, the partner must be updated in the same commit. `validate.sh` checks most of these automatically; the table documents all known pairs including those that require manual attention.

| Primary | Mirror / Paired file | What must stay in sync |
| --- | --- | --- |
| `agents/<name>.md` (add/remove/rename) | `AGENTS.md`, `README.md` (Current Agents), `rules/agent-first-selection.md`, `web/instructions.md` (Agent Catalog) | All four must be updated together |
| `rules/<name>.md` (add/remove) | `README.md` (Current Rules) | One H3 entry per rule file |
| `README.md` (Current Agents) | `agents/` directory | One table row per agent file |
| `README.md` (Current Rules) | `rules/` directory | One H3 entry per rule file |
| `README.md` (Current Commands) | `commands/` directory | One H3 entry per command file (not gated by `validate.sh` — hand-verify) |
| `README.md` (directory tree) | actual files on disk | Tree listing must reflect actual `hooks/`, `scripts/`, `templates/`, `adrs/` contents |
| `commands/*.md` | `setup.sh` (`CLAUDE_LINKS`) + `validate.sh` (`check_symlinks` pairs) | A new command artifact type must be symlinked into `~/.claude/commands/` and registered in the symlink-pair check |
| `AGENTS.md` (agent table) | `agents/` directory | Bidirectional name presence — checked by `check_agent_catalog()` (delegates to `scripts/regen-agent-catalog.sh --check`, ADR-062) |
| `AGENTS.md` (Tier/Domain/Use-when) | `rules/agent-first-selection.md` | `AGENTS.md` canonical; regenerate mirror with `scripts/regen-agent-catalog.sh --write`; `--check` gates Domain/Use-when drift (error). README Tier/Model also checked; README Description + web catalog intentionally divergent (ADR-062) |
| `AGENTS.md` (Validation) | `validate.sh` check list | Narrative description must reflect current checks |
| `CONTRIBUTING.md` (Validation) | `validate.sh` check list | New checks must be documented; removed checks must be de-listed |
| `CONTRIBUTING.md` (Adding a New Agent) | `.github/PULL_REQUEST_TEMPLATE.md` | Step list and PR checklist must cover the same required actions |
| `CONTRIBUTING.md` (Adding a New Rule) | `.github/PULL_REQUEST_TEMPLATE.md` | Same as above for rules |
| `scripts/wim/<script>.sh` | `scripts/wim/.frozen-shas` | Frozen scripts under `scripts/wim/` are SHA-pinned. Any legitimate re-authoring must update the corresponding pin entry in the same commit, or `validate.sh check_frozen_scripts` errors. See ADR-050. |
| `scripts/wim/` (any change) | `agents/work-item-management-expert.md` `## Frozen Work-Item Scripts` and `## Script Workflow` sections | Adding or removing a frozen script, renaming the manifest file, or changing the driver's invocation contract must propagate to the agent file so the constraint and operational flow stay accurate. |
| `AGENTS.md` (agent table) and matching row in `rules/agent-first-selection.md` | `web/instructions.md` (Agent Catalog table) | Catalog row edits (description, domain, use-when text) propagate so web-session users see the same routing reference |
| `rules/<name>.md` (rules mirrored in the distillate — orchestrator-protocol, plan-before-code, agent-first-selection, research-parallelism, consensus-by-replication, github-flow, conventional-commits, semver-tagging, pr-template-standard, adr-required, debian-baseline, post-implementation-review, structured-review-format, no-mcp-servers, secrets-guard, gh-identity-guard, script-output-conventions) | `web/instructions.md` (matching section) | Substantive rule edits propagate to the matching section. Editorial tweaks that do not change semantics are not required to propagate. |
| `AGENTS.md` (Orchestrator Protocol, Development Conventions, Security Policies) | `rules/<name>.md` (the canonical rule each pointer names) | Pointer text only (ADR-085) — keep the pointer accurate when a rule is renamed/added/removed; substantive changes live in the rule and propagate to `web/instructions.md` via the row above |

## Setup

```bash
# Initial setup (clone + link + hooks)
git clone git@github.com:<your-account>/agent-framework.git ~/.agent-framework
~/.agent-framework/setup.sh

# After pulling changes on another machine
cd ~/.agent-framework && git pull
# Re-run setup.sh only if new top-level directories were added
```

**Bash version:** `setup.sh` and the `hooks/*.sh` scripts run on bash 3.2+ (macOS system `/bin/bash`). `validate.sh` requires bash 4.0+ — it uses an associative array — and exits with a clear error on older versions. On macOS install a modern bash (`brew install bash`); Debian 13 ships bash 5.x. Check with `bash --version`.

The setup script:

- Creates symlinks from `~/.claude/` into the repo
- Creates `~/.claude/bash-guard-safe-paths.conf` for the destructive command guard
- Installs a pre-push git hook that runs `gh-identity-guard.sh` then `validate.sh` before every push, and a pre-commit hook that runs `secrets-guard.sh`
- Backs up existing files with timestamped `.bak` suffix before replacing
- Skips items already correctly linked
- Is safe to re-run at any time
- Follows `rules/script-output-conventions.md` — `OK`/`SKIP`/`INFO`/`WARN`/`ERROR` labels, a summary block, and a non-zero exit when any step errors

`setup.sh` supports `--dry-run` (print every mutation without executing), `--non-interactive` (skip prompts with safe defaults, for CI/headless), and `-h`/`--help` (usage extracted from the header). Individual sections can be skipped with `SETUP_SKIP_SYMLINKS=1` or `SETUP_SKIP_GIT_HOOKS=1`. It sources the shared output helpers from `scripts/lib/log.sh` (ADR-061).

`setup.sh` optionally prompts to create a local-only `.gh-expected-identity` pin for the gh-identity guard, but does not otherwise configure git or `gh` identity. On a host that authenticates to more than one GitHub account, configure per-repo identity separately — see [`docs/multi-account-git-identity.md`](docs/multi-account-git-identity.md).
