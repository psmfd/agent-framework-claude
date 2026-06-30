---
description: 'Require structured output format with severity classification, findings table, and machine-readable verdict for all review output'
---

# Structured Review Format

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

## Verdict

End every review with a machine-readable verdict line:

```markdown
**Verdict:** PASS | PASS_WITH_WARNINGS | NEEDS_CHANGES
```

* **PASS** — no findings, or Info-only findings.
* **PASS_WITH_WARNINGS** — Warning-level findings exist but no Critical or Error findings.
* **NEEDS_CHANGES** — one or more Critical or Error findings. The review does not pass.

## When this rule applies

* Any agent performing code review (dedicated review agents, linter, self-review)
* PR review output
* Post-implementation review findings

## When this rule does not apply

* Exploratory research or question-answering — not every analysis needs a verdict
* Linter output that follows its own tool-centric format (the linter may adopt this format in a future update)
* Trivial single-file checks where a prose response is more appropriate
