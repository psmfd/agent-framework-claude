# Claude Code — Project Configuration

@AGENTS.md

This file contains Claude Code-specific configuration that cannot be expressed in `AGENTS.md`. Project conventions and standards are defined in AGENTS.md (imported above).

## Rule Discovery

Rules in `rules/` are loaded automatically by Claude Code at session start via symlink to `~/.claude/rules/`. You do not need to read them manually — they are already in your context.

## Hooks

Hooks configured in `settings.json` load at session start. The `PreToolUse` Bash guard (`bash-destructive-guard.sh`) rejects destructive shell commands targeting paths outside the project. A second `PreToolUse` guard (`session-secrets-guard.sh`) fires on `Bash`/`Write`/`Edit`/`MultiEdit`/`NotebookEdit` and denies any call that would surface a secret in-session (inline literal, credential-file read, or a secret written to a file) — the in-session counterpart to the `secrets-guard.sh` pre-commit hook (ADR-053). A third `PreToolUse` guard (`session-gh-identity-guard.sh`) denies a mutating `gh`/`git push` Bash call when the active GitHub identity is wrong for the repo; its companion git pre-push hook (`gh-identity-guard.sh`, installed by `setup.sh`) closes the raw-shell vector (ADR-054). A `SubagentStop` guard (`subagent-verdict-guard.sh`) blocks a framework custom agent from returning without its machine-parseable verdict line, delivering the fix instruction back to the subagent (fail-open on indeterminate state; ADR-088). A `PostToolBatch` guard (`fanout-nudge.sh`) emits an advisory nudge — never a block (always exit 0) — when a parallel batch's `Agent`/`Task`-call count and distinct-`subagent_type` signal is too weak for a Research divergence fan-out; it fails open and cannot see task classification, so it notifies rather than enforces (ADR-090). An `InstructionsLoaded` logger (`instructions-loaded-log.sh`) is observability-only: it appends metadata about each CLAUDE.md/rules load (timestamp, load reason, memory type, byte size, path — never content) to an owner-only `~/.claude/logs/` file and always exits 0; its stdout is discarded from context, so it is no-mcp-servers-compatible (ADR-092). The `Stop` hook outputs a self-check reminder when a non-empty assistant message exists and the stop hook is not already active — it does not detect file modifications.

Restart Claude Code after any hook configuration changes.

## Hook Types

Claude Code supports 4 hook types: `command` (shell execution), `http` (webhook POST), `prompt` (single-turn LLM evaluation), and `agent` (multi-turn subagent with tool access). The hooks configured in this repo's `settings.json` use `command` type. See `CONTRIBUTING.md` for hook configuration details.
