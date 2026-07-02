---
description: 'Require structured output format with severity classification, findings table, machine-readable verdict, and fail-closed unable-to-review/missing-verdict handling for all review output'
---

# Structured Review Format

**Enforcement:** self-report only — no automated check parses review-agent output for format compliance (#24 tracks mechanical enforcement)

When producing review output — whether from a dedicated review agent, the linter, or a self-review pass — use this structured format.

## Severity Classification

Every finding must be assigned one of these severity levels:

* **Critical** — data loss, security vulnerability, or outage risk. Must be fixed before merge.
* **Error** — incorrect behavior, logic bug, or broken functionality. Must be fixed before merge.
* **Warning** — code smell, design concern, or non-idiomatic pattern. Should be addressed but does not block merge.
* **Info** — suggestion, minor improvement, or style observation. Optional to address.

## Findings Table

Present all findings in a single `## Findings` section with this table format:

```markdown
## Findings

| Severity | File | Line | Finding |
| --- | --- | --- | --- |
| Critical | src/auth.py | 42 | SQL injection via unsanitized user input |
| Warning | lib/utils.ts | 118 | Unused import — `lodash` is imported but never referenced |
```

Every finding must include a `file:line` reference. Do not report findings without location information.

### Multi-reviewer synthesis — the `Source` column

When an orchestrator merges findings from **more than one reviewer** into a single table (for example the `/review` command, which fans out to `code-review-expert`, `security-review-expert`, and `linter`), add a `Source` column as the **last** column, identifying which reviewer produced each finding:

```markdown
## Findings

| Severity | File | Line | Finding | Source |
| --- | --- | --- | --- | --- |
| Critical | src/auth.py | 42 | SQL injection via unsanitized user input | security-review-expert |
| Warning | lib/utils.ts | 118 | Unused import — `lodash` is never referenced | code-review-expert |
```

The `Source` column is **required only for multi-reviewer output** and is omitted for single-reviewer output — a solo review agent uses the four-column table above unchanged.

For the full fan-out-shape comparison (divergence vs. replication vs. multi-reviewer command), see the Fan-Out Shapes and Aggregation Policy table in [orchestrator-protocol.md](orchestrator-protocol.md).

## Verdict

End every review with a machine-readable verdict line:

```markdown
**Verdict:** PASS | PASS_WITH_WARNINGS | NEEDS_CHANGES | UNABLE_TO_REVIEW
```

* **PASS** — no findings, or Info-only findings.
* **PASS_WITH_WARNINGS** — Warning-level findings exist but no Critical or Error findings.
* **NEEDS_CHANGES** — one or more Critical or Error findings. The review does not pass.
* **UNABLE_TO_REVIEW** — the review could not be performed at all. See below.

### Unable to Review

A review agent that cannot form a judgment — the diff is inaccessible, unreadable, or empty; the target is outside the reviewer's stated domain entirely; required tooling is missing and no report-only fallback exists — MUST NOT default to `PASS`. `PASS` asserts "reviewed, no blocking findings"; it is never a stand-in for "did not review." Emit `**Verdict:** UNABLE_TO_REVIEW` with a one-line reason immediately below the verdict (e.g. "diff argument did not resolve to a valid ref" or "target file is binary and cannot be reviewed"). `UNABLE_TO_REVIEW` is not a passing state and not a failing state — it is an incomplete-review signal. Downstream aggregation (`consensus-by-replication.md`, and any multi-reviewer command's most-severe-wins policy) treats it as equivalent to a research agent's `BLOCKED` return (see Return Contract in `research-parallelism.md`).

**Not valid reasons for `UNABLE_TO_REVIEW`:** the diff is large, the change is architecturally complex, the reviewer is uncertain about one judgment call, or the reviewer disagrees with the change's approach. Size and complexity are reasons to review more carefully, not reasons to decline — report uncertainty as an Info-severity finding with the caveat stated, and disagreement with an approach is a Warning or Error finding, not an inability to review. `UNABLE_TO_REVIEW` is reserved for the review being genuinely impossible to perform, not merely hard.

### Fail-Closed Default for a Missing Verdict Line

A review agent response with no `**Verdict:**` line at all — truncated output, a crashed subagent, malformed formatting — is treated as `NEEDS_CHANGES` by the consuming orchestrator, never as `PASS`. This is a fail-closed default: an orchestrator that cannot confirm a review passed must not proceed as though it did. This deliberately does not match the research-agent default in `research-parallelism.md` (`PARTIAL`) — a partial finding on a research question is still usable input; a review response with no verdict is not usable evidence that a diff is safe to merge.

## When this rule applies

* Any agent performing code review (dedicated review agents, linter, self-review)
* PR review output
* Post-implementation review findings

## When this rule does not apply

* Exploratory research or question-answering — not every analysis needs a verdict
* Linter output that follows its own tool-centric format (the linter may adopt this format in a future update)
* Trivial single-file checks where a prose response is more appropriate
