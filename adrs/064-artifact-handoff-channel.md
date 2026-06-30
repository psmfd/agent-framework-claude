# ADR-064: Tracked `.review/` artifact handoff channel with path-based merge guard

**Status:** Accepted
**Date:** 2026-06-01

## Context and Problem Statement

Agents and the orchestrator sometimes produce large artifacts that need line-anchored human review before they are acted on — ADR drafts, synthesized multi-reviewer reports, evidence payloads. There is no channel for handing these off: they end up dumped inline in the conversation or written to arbitrary paths, and there is no guarantee they do not accidentally merge to the integration branch. A handoff channel must let reviewers comment line-by-line (so artifacts must be tracked and appear in the PR diff) while guaranteeing the artifacts never reach `dev`.

## Considered Options

* **Option A** — Inline artifacts in the conversation. No line-anchored review, no persistence, no merge risk but no review affordance.
* **Option B** — A tracked `.review/` directory whose contents are blocked from merging by a **label-based** CI guard (fail PRs carrying an `artifact-review` label).
* **Option C** — A tracked `.review/` directory whose contents are blocked by a **path-based** CI guard (fail any PR whose diff adds `.review/` files beyond the stubs), with the convention codified as a rule.

## Decision Outcome

Chosen option: **Option C**. A tracked `.review/` directory (shipped with a `.gitkeep` and a `README.md`) is the handoff channel. Artifacts are written there with a plain filesystem write (no MCP, no network — compatible with `rules/no-mcp-servers.md` and ADR-046), are visible in the PR diff for inline review, and must be deleted before merge. The never-merge guarantee is enforced by `artifact-review-guard` (`.github/workflows/artifact-review-guard.yml`), a required status check on the `protect-dev` ruleset that fails any PR whose diff adds files under `.review/` other than `.gitkeep` / `README.md`.

Enforcement is **path-based, not label-based** (rejecting Option B). A label is voluntary: an unlabeled PR that adds `.review/` files would merge with no resistance, and a label-gated CI job that skips leaves a required check in an ambiguous non-reporting state. The invariant is the presence of the files in the diff, so the guard keys on the files. The guard runs on every PR and decides pass/fail at the step level so the required check always reports. Because feature branches squash-merge into `dev`, and squash preserves the branch tree at merge time, a file present at merge would land on `dev` — the guard is what prevents that.

The convention is codified as a **rule** (`rules/artifact-handoff.md` + Copilot instruction mirror) rather than a CONTRIBUTING section, because it must bind agent behavior at session-load time — agents need to know to use the channel. It is omitted from the `web/instructions.md` distillate: the convention is inapplicable outside a local repository checkout (no working tree, no `.review/`), and the rule states this explicitly.

**CODEOWNERS is intentionally not added.** With the current `protect-dev` configuration (`required_approving_review_count: 0`, `require_code_owner_review: false`), a CODEOWNERS entry on `.review/**` enforces nothing — it would be false assurance. It becomes a meaningful control only if required approvals are raised and `require_code_owner_review` is enabled, which is a separate workflow decision.

No `.gitignore` rule is added for `.review/`: artifacts must be tracked to be reviewable in the PR diff.

### Tradeoffs

* Good: a real never-merge guarantee — path-based enforcement closes the unlabeled-PR and skipped-job bypasses that a label-based guard leaves open.
* Good: artifacts get line-anchored review via the normal PR diff; the convention binds agents because it is a loaded rule.
* Bad: contributors must remember to delete artifacts before merge; the guard blocks the PR until they do (intended friction).
* Bad: the guard cannot be registered as a required check until it has run once, so required-check registration on `protect-dev` is a manual post-merge step, not part of the introducing PR.

## More Information

* Issue #190 (re-spec'd from a label-based design after a 4-agent fan-out: gh-cli-expert, gitflow-expert, ai-crossplatform-expert, code-review-expert).
* Source: a sibling repo tier-3 artifact handoff (its ADR-0006/0007/0008).
* Related: `rules/github-flow.md` (branch protection / required checks), `rules/no-mcp-servers.md`, ADR-046.
