# ADR-012: Symlink-based distribution from version-controlled repo

**Status:** Accepted
**Date:** 2026-03-24

## Context and Problem Statement

Agent skills, rules, and settings need to be present at platform-specific paths (`~/.claude/skills/`, `~/.claude/agents/`, `~/.copilot/agents/`, etc.) for discovery. These files are version-controlled in `~/.agent-framework`. The content needs to stay synchronized between the repo and the platform discovery paths across multiple machines.

## Considered Options

* **Symlinks** — `setup.sh` creates symlinks from platform paths into the repo; `git pull` immediately updates both platforms
* **Copy on setup** — `setup.sh` copies files to platform paths; re-run after every `git pull`
* **Direct authoring** — author directly in `~/.claude/` and `~/.copilot/`, no repo

## Decision Outcome

Chosen option: **Symlinks**, because changes to the repo via `git pull` are immediately reflected in both platforms without re-running setup. This makes the dotfiles portable across machines — clone, run `setup.sh` once, and all future pulls are live.

### Tradeoffs

* Good: zero-friction updates — `git pull` is all that is needed after initial setup
* Good: the repo is the single source — no copy/sync divergence possible
* Good: `setup.sh` backs up existing files before replacing and is safe to re-run
* Bad: symlinks can break if the repo is moved or deleted
* Bad: some tools may not follow symlinks correctly (not observed in practice with Claude Code or Copilot)

## More Information

* [ADR-015](015-validation-pre-push-gate.md) — validate.sh checks symlink correctness
* `setup.sh` — creates symlinks and installs hooks
* CONTRIBUTING.md Setup section
