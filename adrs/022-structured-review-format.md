# ADR-022: Structured review output format

**Status:** Accepted
**Date:** 2026-03-27

## Context and Problem Statement

Agents performing code review produce inconsistent output. The linter emits tool-centric per-tool sections with PASS/WARN/FAIL/SKIP status. The post-implementation review rule prescribes what steps to take but defines no output format. When agents self-review diffs, the output is unstructured prose. There is no unified format for review findings, no consistent severity classification, and no machine-readable verdict.

## Considered Options

* **Rule only** — define a structured output format rule that any agent performing review must follow, without creating a dedicated review agent
* **Skill only** — create a `code-review-expert` Domain Specialist agent with the format embedded in its SKILL.md, but no rule requiring other agents to follow the format
* **Both rule and skill** — a rule defines the output format contract (severity tiers, findings table, verdict), and a skill provides the semantic review domain expertise

## Decision Outcome

Chosen option: **Both rule and skill**, because the format and the expertise are separable concerns. The `structured-review-format` rule governs output format for any agent producing review findings — the linter, a dedicated reviewer, or the session doing a self-review pass. The `code-review-expert` skill provides semantic review knowledge (logic errors, design quality, security, requirement fidelity) that static analysis tools cannot detect.

### Tradeoffs

* Good: the format rule applies universally — any agent producing review output follows the same contract
* Good: the review skill fills a gap the linter cannot cover (semantic correctness, design quality, security patterns)
* Good: the separation allows the linter to adopt the format later without coupling it to the review skill
* Bad: the linter's existing output format (per-tool sections, PASS/WARN/FAIL/SKIP) does not yet conform to the new rule — alignment is deferred as separate work
* Bad: two new files in rules/ and copilot/instructions/, plus three new files for the skill — increases the file count by five

### Linter alignment

The linter's current output format is intentionally left unchanged. The structured-review-format rule includes an explicit carve-out: "Linter output that follows its own tool-centric format" does not apply. This avoids a breaking change to an established agent. A future issue should align the linter's output with the structured format if unified reporting is desired.

## More Information

* Issue #26 — original proposal for structured review mode
* ADR-021 — agent tiering taxonomy (code-review-expert is a Domain Specialist)
* `rules/post-implementation-review.md` — workflow rule (when to review, not how to format)
* `rules/structured-review-format.md` — format rule (how to present findings)
