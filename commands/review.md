---
description: "Three-way parallel review — code-review-expert + security-review-expert + linter — fanned out as concurrent subagents and synthesized into one merged findings table."
argument-hint: "[base-ref or branch — defaults to dev/main]"
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(git status:*), Agent
---

# /review

Run a parallel review of the current changes using three specialist subagents, then synthesize their findings into a single merged table. This command is the named, codified form of the divergence fan-out described in [research-parallelism.md](../rules/research-parallelism.md) — invoking it guarantees the parallel review actually fires instead of an ad-hoc single-reviewer pass.

## Step 1 — Identify the diff under review

Determine the scope:

- If an argument is supplied (`$ARGUMENTS` — e.g. `/review main`, `/review HEAD~3`), use it as the base ref.
- Otherwise default to the current branch's diff against `dev` (or `main` when already on `dev`/`main`). Run `git rev-parse --abbrev-ref HEAD` and `git log --oneline <base>..HEAD` to confirm what is in scope.

Surface the chosen scope (base ref, commit count, file count) to the user before fanning out.

## Step 2 — Fan out to three concurrent subagents

Invoke the `Agent` tool **three times in a single message** so the subagents run concurrently with isolated context. Set `subagent_type` to `code-review-expert`, `security-review-expert`, and `linter`. Each brief must be self-contained — subagents share no memory — and must include the absolute repo path and the `<base>..HEAD` revision so each agent can read the diff and surrounding context directly:

- **code-review-expert** — "Review the diff `<base>..HEAD` in `<absolute-repo-path>`. Read the diff and the surrounding context for each touched file. Produce findings per `rules/structured-review-format.md`."
- **security-review-expert** — "Security review of the diff `<base>..HEAD` in `<absolute-repo-path>`. Map trust boundaries; identify auth/authz/secret/crypto concerns; cite first-party docs. Produce findings per `rules/structured-review-format.md`."
- **linter** — "Lint the files changed in `<base>..HEAD` in `<absolute-repo-path>`. Run the appropriate linter per file type in report-only mode."

Each review agent ends with the `**Verdict:** PASS | PASS_WITH_WARNINGS | NEEDS_CHANGES` line defined in [structured-review-format.md](../rules/structured-review-format.md). An agent that cannot proceed returns `BLOCKED` per the Return Contract in [research-parallelism.md](../rules/research-parallelism.md) — surface that to the user rather than synthesizing around it.

## Step 3 — Synthesize the merged report

When all three return, produce a single output. Because reviewers are merged into one table, include the `Source` column (per [structured-review-format.md](../rules/structured-review-format.md)) identifying which reviewer produced each finding:

````markdown
# Review Summary

**Scope:** `<base>..HEAD` (`<n>` commits, `<m>` files)
**Reviewers:** code-review-expert, security-review-expert, linter

## Findings

| Severity | File | Line | Finding | Source |
| --- | --- | --- | --- | --- |
| Critical | src/auth.cs | 42 | Missing authorization check on admin route | security-review-expert |
| Error | src/db.py | 118 | Off-by-one truncates the last record | code-review-expert |
| Warning | setup.sh | 7 | SC2086 — unquoted `$var` risks word-splitting | linter |

**Aggregate Verdict:** PASS | PASS_WITH_WARNINGS | NEEDS_CHANGES

## Notes

- Cross-reviewer agreement: <findings flagged by two or more reviewers — highest confidence>
- Escalations: <any cross-domain concern a subagent surfaced for routing>
````

Aggregate verdict is **most-severe-wins** (command-local synthesis policy):

- Any reviewer reports `NEEDS_CHANGES` → aggregate is `NEEDS_CHANGES`.
- Otherwise any `PASS_WITH_WARNINGS` → aggregate is `PASS_WITH_WARNINGS`.
- Otherwise `PASS`.

This is a divergence fan-out (three different agents, different lenses), so the aggregation ladder in `consensus-by-replication.md` does not apply — that ladder governs replication of one agent on identical prompts.

## Constraints

- Do **not** inline a review yourself instead of fanning out — that defeats the workflow.
- Do **not** add a fourth agent. Three is the standard divergence fan-out per [research-parallelism.md](../rules/research-parallelism.md).
- Do **not** mutate any files. This workflow is read-only end to end.
