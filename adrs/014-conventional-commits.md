# ADR-014: Conventional Commits format with no authorship attributions

**Status:** Accepted
**Date:** 2026-03-25

## Context and Problem Statement

Commit messages in the repo were inconsistent — varying formats made it difficult to scan the git log for the type of change (feature, fix, refactor). Additionally, AI-assisted commits were adding `Co-Authored-By` trailers that added noise without value in a solo-contributor repo.

## Considered Options

* **Conventional Commits** — structured `<type>(<scope>): <description>` format with a fixed set of types; no authorship attributions
* **Free-form messages** — no enforced format, rely on author discipline
* **Gitmoji** — emoji-prefixed commit messages for visual categorization

## Decision Outcome

Chosen option: **Conventional Commits**, because the structured format makes the git log scannable by type (feat, fix, chore, etc.) and enables future automated changelog generation. The no-attribution policy keeps messages focused on what changed, not who did it.

### Tradeoffs

* Good: git log is instantly scannable — `git log --oneline` shows type at a glance
* Good: enables automated changelog generation if needed in the future
* Good: scope field provides quick context without reading the full diff
* Bad: requires learning the type vocabulary (low overhead — 8 types)
* Bad: the format is enforced by convention (rule file), not by a commit-msg hook

## More Information

* `rules/conventional-commits.md` — the enforcing rule
* [conventionalcommits.org](https://www.conventionalcommits.org/) — specification
* CONTRIBUTING.md Commit Messages section
