# ADR-076: Claude-only successor genesis

**Status:** Accepted
**Date:** 2026-06-29

## Context and Problem Statement

The cross-platform agent framework (`psmfd/agent-framework`) supports both Claude
Code and GitHub Copilot. A Claude-only edition is wanted as the framework the
maintainer actually consumes, published to the personal `psmfd` org as
`agent-framework-claude`, starting private and intended to go public. This requires
deciding how the new repository comes into being, how much history and how many
decision records it carries, which agents it ships, and its relationship to the
predecessor going forward.

## Considered Options

* **Fresh init, successor model** — new `git init`, snapshot the predecessor's
  current `dev` working tree, strip Copilot, curate agents, carry the still-relevant
  ADRs at their original numbers, MIT license, build for a later public flip. No
  ongoing sync — a hard fork.
* **GitHub fork + strip** — fork `psmfd/agent-framework`, remove Copilot via commits.
  Rejected: the "forked from" linkage misrepresents an independent product line, and
  Copilot content stays resurrectable in history.
* **`git filter-repo` history rewrite** — preserve shared SHAs for ongoing
  cross-picks. Rejected: there is no ongoing sync; the architecture diverges
  (monolithic agents), so shared history adds confusion, not value.

## Decision Outcome

Chosen option: **Fresh init, successor model**. The new repo is a hard fork: a
clean `git init` with no Copilot ghosts in `log`/`blame`, seeded from a snapshot of
the predecessor's `dev` working tree (capturing in-flight uncommitted agents). The
predecessor remains intact at `psmfd/agent-framework`; this repo does not sync back
to it. Curation: ship 25 agents, drop `ai-crossplatform-expert` (Copilot translator,
obsolete), `checkmarx-expert` (enterprise SAST, redundant with `security-review-expert`
and native code scanning), and `kitty-agent`; the `/full-review` command folds into
`/review` with Checkmarx gone. Still-relevant ADRs are carried verbatim at their
original numbers for provenance; purely Copilot/cross-platform/dead-subsystem ADRs
are dropped; Claude-only decisions get new ADRs (074–079). The repo is MIT-licensed
and engineered for a later public release.

### Tradeoffs

* Good: clean history; honest independent identity; no Copilot baggage.
* Good: the predecessor is untouched and continues to serve cross-platform users.
* Bad: decision archaeology that lived in dropped ADRs is no longer inline (it
  remains in the predecessor repo). Accepted — the new ADRs capture the divergence.
* Bad: a successor that never syncs will drift from the predecessor. Intended.

## More Information

Drives [ADR-074](074-monolithic-agent-pattern.md),
[ADR-075](075-rules-claude-native-single-file.md),
[ADR-077](077-setup-predecessor-migration.md),
[ADR-078](078-ci-security-gitleaks.md), and
[ADR-079](079-branch-protection.md). The agent curation reassigns the
structural-reviewer role formerly held by `ai-crossplatform-expert` (predecessor
ADR-041, not carried) to `docs-expert` / `code-review-expert`.
