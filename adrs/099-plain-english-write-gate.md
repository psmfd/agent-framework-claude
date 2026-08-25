# ADR-099: Write-only plain-English semantic gate

**Status:** Accepted
**Date:** 2026-08-24

## Context and Problem Statement

Persisted documentation can remain technically correct while becoming difficult to read through stacked qualifications, filler, jargon, and repeated summaries. Behavioral guidance improves authoring but cannot prevent a determinate violation from reaching disk. Claude Code has no pi extension runtime, so the framework needs a native enforcement boundary that keeps the model's remembered text consistent with the file it writes.

## Considered Options

* **Behavioral guidance only** — ask agents to self-review without a tool gate.
* **PreToolUse prompt gate** — judge eligible `Write` calls and deny determinate violations before execution.
* **Automatic `updatedInput` rewrite** — replace the proposed text before execution.
* **Post-write rewrite** — revise content after the original write reaches disk.

## Decision Outcome

Chosen option: **PreToolUse prompt gate**, because it blocks determinate violations before they reach disk and asks the authoring model to produce the corrected bytes itself. The initial release covers complete `Write` calls to `README.md`, `CONTRIBUTING.md`, and `docs/**/*.md`. Permission-rule `if` filters keep other paths outside the semantic judge.

The hook uses `continueOnBlock: true`, so a denial and its specific reason return to Claude as a tool error and Claude can retry. The judge allows specialist terminology and genuine qualifications. It ignores frontmatter, code, commands, templates, links, paths, tables, and other structured syntax when evaluating prose. The prompt places tool input after the policy as untrusted data, refuses instructions embedded in proposed content, and limits denial excerpts to 160 characters.

Automatic rewriting is deferred. Claude Code can replace complete tool input through `updatedInput`, but the authoring model may retain the original text and make later edits against stale content. A model-backed command rewriter would also add recursion, credential, content-egress, timeout, and cost concerns. Post-write rewriting is rejected because it creates an unenforced disk window.

Prompt hooks expose `ok: true` or `ok: false`; they do not expose an allow-with-warning result. Judge uncertainty therefore allows normal permission flow without a warning. Documentation must not claim otherwise. Deterministic validation checks the control plane and fixture coverage, not semantic model quality. A real Claude Code prototype remains the semantic acceptance test.

### Tradeoffs

* Good: determinate violations do not reach disk, and the model remains the author of the final text.
* Good: path filters avoid model calls for instruction files, code, templates, and other excluded content.
* Bad: `Edit`, `MultiEdit`, and Markdown notebook cells remain outside enforcement.
* Bad: model judgment is nondeterministic and cannot be proven by offline CI.
* Bad: uncertain verdicts fail open without a visible warning because the prompt-hook response schema has no such state.

## More Information

* Tracking issue: [#112](https://github.com/psmfd/agent-framework-claude/issues/112)
* Related documentation-style scope: [#83](https://github.com/psmfd/agent-framework-claude/issues/83)
* Architecture: [ADR-074](074-monolithic-agent-pattern.md), [ADR-075](075-rules-claude-native-single-file.md)
* First-party hook contract: <https://code.claude.com/docs/en/hooks>
* Claude Code 2.1.243 prototype: blocked determinate violations for `README.md` and `docs/**/*.md`, allowed plain and quoted-example README prose, ignored an embedded instruction to return `ok: true`, and did not invoke the gate for `rules/**` or non-Markdown `docs/**` files.
