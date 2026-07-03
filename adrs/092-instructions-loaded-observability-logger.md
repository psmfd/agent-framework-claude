# ADR-092: InstructionsLoaded Observability Logger

**Status:** Accepted
**Date:** 2026-07-03

## Context and Problem Statement

The rule-loading cost model (#27) rests on `bytes/4` token estimates (~23–31k
always-loaded tokens, ×N under sub-agent fan-out), and one question it could not
answer — whether `paths:`-scoped rules re-trigger inside a sub-agent's own file
reads — was left explicitly open by ADR-089 and #50's measurement. Claude Code
exposes an `InstructionsLoaded` hook event (added v2.1.69) that fires per
CLAUDE.md / rules file load with `file_path`, `memory_type`, `load_reason`, and
(for lazy loads) `globs` / `trigger_file_path` / `parent_file_path`. This is the
framework's first *observability* hook and its first hook that writes persistent
local state, so its compatibility with `rules/no-mcp-servers.md` and its data
posture need a recorded decision.

## Considered Options

* **Option A** — Local, metadata-only `InstructionsLoaded` logger writing owner-only
  JSONL to `~/.claude/logs/`.
* **Option B** — No hook: continue with manual `/context` sampling at session start.
* **Option C** — A logger that captures richer data (file content excerpts, or
  emits to stdout for in-context visibility).

## Decision Outcome

Chosen option: **Option A**, because it yields measured load data cheaply while
staying inside the framework's security posture:

1. **No-mcp-servers compatible by construction.** `InstructionsLoaded` is
   observability-only: its exit code is ignored, it cannot block or modify
   loading, and its stdout is *discarded from context* (only
   UserPromptSubmit/UserPromptExpansion/SessionStart inject stdout). A hook that
   writes to a local file and emits nothing to context cannot inject
   network-sourced or any other content into the harness system context, so it
   does not engage the ADR-046 / `no-mcp-servers.md` threat model. Option C's
   stdout path is rejected precisely because it would move data toward context.
2. **Metadata only.** The logger records `ts`, `session_id`, `load_reason`,
   `memory_type`, `bytes` (a `wc -c` count, never content), and `file_path` —
   enough to measure load frequency, size, and reason without ever recording file
   or conversation content. Option C's content excerpts are rejected: they add
   privacy exposure for no measurement benefit over a byte count.
3. **Owner-only local state.** The log dir is `chmod 700` and the file `chmod
   600` — it records which local files loaded and when, so it is kept
   owner-readable only. Location honors `CLAUDE_CONFIG_DIR` for test isolation.
4. **Fail-open, never disruptive.** The hook always exits 0; missing jq, empty
   stdin, an absent `file_path`, or any write error simply skips logging. An
   observability hook must never interfere with a session, so unlike the
   fail-closed `PreToolUse` guards it has nothing to protect by failing closed.

Option B is retained as the zero-code fallback but does not scale to the
per-load, per-`load_reason` granularity needed to settle the sub-agent
re-trigger question.

### Tradeoffs

* Good: converts the loading-cost model from estimates to measured data; can
  settle the open sub-agent `paths:` re-trigger question; zero context/security
  exposure; reuses the established hook + settings.json + tests pattern.
* Bad: two known upstream gaps limit the data — the event does not fire on
  `/clear` (anthropics/claude-code#31017) and duplicates ~3× per file on
  `/compact` (#52176); both are reported-but-unconfirmed for CLI 2.1.199 and are
  handled as analysis caveats (fresh sessions for clean data; dedupe by
  `session_id`+`file_path`+`load_reason`), not worked around in the hook.

## More Information

* #52 (this hook), #27 (loading-cost research), #50 / ADR-089 (`paths:` scoping —
  the measurement this logger extends), ADR-046 / `rules/no-mcp-servers.md`
  (the policy this hook is checked against)
* upstream anthropics/claude-code#31017 (`/clear` gap), #52176 (compact 3× dup)
