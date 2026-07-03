# ADR-087: Diff Ingestion Contract for Review Agents

**Status:** Accepted
**Date:** 2026-07-02

## Context and Problem Statement

`code-review-expert` and `security-review-expert` instructed reviewers to run `git diff`/`git show`, but neither agent carries `Bash` — correctly, per the minimal-tool-lists policy (ADR-069). The instructions were unfollowable: the #14 seam-repair review hit this in practice, returning `UNABLE_TO_REVIEW` until re-run with a pre-computed diff artifact (issue #31). `commands/review.md` compounded the gap by briefing both agents to "read the diff directly" from a revision range they cannot resolve. `Read`/`Glob` operate on the filesystem, not git refs, so "reconstruct the diff from base/head refs" is equally infeasible without shell access.

## Considered Options

* **Option A** — Add `Bash` to both review agents with an ADR-069 justification (read-only git plumbing as a documented execution workflow).
* **Option B** — Diff Ingestion Contract: keep no-Bash; the orchestrator materializes the diff to a file and passes its absolute path (plus the changed-file list) in the brief; a missing/unreadable artifact on a diff review maps to `UNABLE_TO_REVIEW`.
* **Option C** — Status quo: leave the `git diff` instruction and rely on orchestrators to notice the failure.

## Decision Outcome

Chosen option: **Option B**, because it codifies the workaround that already worked in practice while preserving the ADR-069 posture — review agents stay incapable of arbitrary command execution, which matters most for exactly the agents that read untrusted diffs. Option A widens the execution surface of two security-relevant reviewers to fix what is purely an input-delivery problem; Option C leaves an agent instructed to do something its toolset cannot do.

The contract, stated in both agent files and consumed by `commands/review.md`:

1. The orchestrator supplies a **pre-computed unified diff artifact** by absolute path (e.g. `git diff <base>..HEAD > <scratchpad>/review-diff.patch`) plus the **changed-file list**; surrounding context is read from the working tree at head state.
2. A diff review with no artifact (or an empty/unreadable one) returns `**Verdict:** UNABLE_TO_REVIEW` with a one-line reason — never a guessed change set, and never a reclassification to advisory mode to avoid the verdict.
3. Both agents' output templates carry the full four-state verdict line, including `UNABLE_TO_REVIEW` (previously omitted, contradicting `rules/structured-review-format.md`).
4. Deliberate advisory work (no diff ever in scope) keeps `structured-review-format`'s exploratory-research carve-out; it is distinguished from a failed diff review by whether a diff review was requested.

### Tradeoffs

* Good: instructions match the toolset; fail-closed verdict instead of silent partial reviews; no execution-surface growth on security-relevant agents; the orchestrator-side cost is one `git diff` redirect it can already perform.
* Bad: one more orchestrator obligation per review fan-out — a brief that forgets the artifact now fails loudly (`UNABLE_TO_REVIEW`) and costs a re-run rather than degrading gracefully.

## More Information

* Issue #31 (both failure observations), PR #230/#231 lineage for the requirement-fidelity review pattern
* ADR-069 (minimal tool lists), ADR-063 (parallel-agent return contract — the sibling cross-cutting contract)
* `rules/structured-review-format.md` (`UNABLE_TO_REVIEW` semantics), `commands/review.md` (consuming briefs)
