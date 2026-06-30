# ADR-077: setup.sh predecessor uninstall and repoint migration

**Status:** Accepted
**Date:** 2026-06-29

## Context and Problem Statement

This framework becomes the one the maintainer consumes, replacing the cross-platform
predecessor on the same machine. The predecessor's `setup.sh` symlinks its `rules/`,
`agents/`, `skills/`, `commands/`, and `settings.json` into `~/.claude/` (and
Copilot artifacts into `~/.copilot/`) per [ADR-012](012-symlink-distribution.md).
If this framework's `setup.sh` simply creates its own symlinks, the result is an
ambiguous or conflicting `~/.claude/` state where two frameworks fight over the same
link targets.

## Considered Options

* **Detect and repoint** — `setup.sh` detects an existing predecessor install (links
  resolving to the predecessor's path) and, with confirmation, tears them down and
  repoints `~/.claude/` (and removes the now-orphaned `~/.copilot/` links) to this
  repo. Leaves the predecessor repo on disk and on GitHub untouched.
* **Document a manual uninstall** — tell the user to run the predecessor's teardown
  first. Rejected: error-prone, easy to leave a half-migrated state.
* **Delete the predecessor** — remove its working copy. Rejected: out of scope; the
  predecessor must remain intact for cross-platform users.

## Decision Outcome

Chosen option: **Detect and repoint**. `setup.sh` gains an idempotent migration step
that identifies predecessor-owned symlinks under `~/.claude/` and `~/.copilot/`,
reports them, and (under a `--dry-run`-able confirm prompt) removes and repoints them
to this repository. It is uninstall-and-repoint only: the predecessor repo's files on
disk and its GitHub remote are never touched. Re-running is safe — already-correct
links are left alone.

### Tradeoffs

* Good: a single `setup.sh` run cleanly transitions consumption to this framework.
* Good: reversible — the predecessor's `setup.sh` can re-claim the links later.
* Bad: `setup.sh` must reason about another repo's link layout, coupling it loosely
  to the predecessor's conventions. Mitigated by detecting by link-target resolution,
  not hard-coded paths.

## More Information

Extends [ADR-012](012-symlink-distribution.md) (the symlink distribution model).
Driven by [ADR-076](076-claude-only-successor-genesis.md).
