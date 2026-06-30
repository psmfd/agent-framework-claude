# ADR-038: Custom worktree path to avoid .claude/ permission conflict

**Status:** Accepted
**Date:** 2026-04-14
**Note:** The `.worktreeinclude` handling clause is superseded by [ADR-070](070-guard-hardening-symlink-override.md) (symlink containment). The custom-path decision itself stands.

## Context and Problem Statement

Claude Code creates worktrees under `.claude/worktrees/<name>/` by default. The `.claude/` directory is a restricted write path — the permission system blocks Edit and Write operations inside it to protect configuration files. Subagents running with `isolation: worktree` inherit this restriction, causing their file modifications to be denied. During a documentation audit (PRs #155–#159), 4 of 5 worktree agents were blocked.

## Considered Options

* **Option A** — Redirect worktrees to `.wt_tmp/` via a `WorktreeCreate` hook
* **Option B** — Add `.claude/worktrees/**` to the Edit/Write permission allowlist in `settings.json`
* **Option C** — Status quo: manually approve each Edit/Write operation in worktree agents

## Decision Outcome

Chosen option: **Option A**, because it eliminates the path collision entirely rather than punching holes in the `.claude/` protection. Option B would weaken the configuration protection that the restriction provides — a broad allowlist for `.claude/worktrees/**` could be exploited by a compromised agent to write to paths adjacent to `settings.json` or `settings.local.json`. Option C is not viable for parallel agent workflows where multiple worktree agents run unattended.

### Tradeoffs

* Good: worktree agents work without permission prompts
* Good: `.claude/` protection remains intact
* Good: orphan cleanup is built into the create hook
* Bad: `.worktreeinclude` processing must be replicated in the hook — registering any `WorktreeCreate` hook disables Claude Code's automatic file copying. The hook adds path traversal filtering (blocking `.`, `..`, and absolute paths) not present in Claude Code's documented behavior
* Bad: `WorktreeRemove` only fires on clean exit, so crash orphans require the prune step in the create hook and physical directory cleanup

## More Information

* Issue: #160
* PR: #171
* WorktreeCreate/WorktreeRemove are Claude Code-only events — no Copilot equivalent exists
* Stdout contamination in WorktreeCreate hooks causes a silent hang (Claude Code bug #27467) — all git output must be redirected
