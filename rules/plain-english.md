---
description: 'Require precise plain English in persisted human documentation without simplifying specialist content or structured syntax'
---

# Plain English

**Enforcement:** PreToolUse hook for eligible `Write` calls; specialist guidance and self-report only outside that boundary.

Write persisted human documentation in direct, precise English. Keep necessary technical language. Remove wording that makes a correct statement harder to understand without adding facts, constraints, or useful emphasis.

## Claudish anti-patterns

Revise prose when it contains a determinate instance of these patterns:

- **Hedging stacks:** several qualifiers around one claim when one accurate condition is enough.
- **Filler transitions:** phrases such as “it is important to note” or “in order to” that add no meaning.
- **Jargon stacking:** multiple abstract or fashionable terms where concrete nouns and verbs are available.
- **Marketing adjectives:** unsupported terms such as “robust,” “seamless,” “powerful,” or “comprehensive.”
- **Nominalizations:** abstract noun phrases that hide the actor or action.
- **Over-qualification:** repeated caveats that do not change the rule or its exceptions.
- **Structure padding:** parallel headings, bullets, or sentences added only to make sections look symmetrical.
- **Redundant summaries:** restating nearby content without adding an action, decision, or constraint.

Do not reject prose because it is technical, dense, or unfamiliar. Name the specific anti-pattern and the affected passage. A general statement that text is “unclear” is not enough.

## Preservation contract

A revision must preserve:

- facts, names, numbers, links, paths, and identifiers;
- `must`, `should`, and `may` distinctions;
- conditions, exceptions, uncertainty, and causal relationships;
- specialist terminology expected by the intended audience;
- the difference between a requirement, recommendation, example, and observation.

Never simplify at the expense of precision. Do not replace an established technical term with a longer plain-language description when the audience expects the term.

## Protected content

Judge prose around structured content, not the structure itself. Preserve:

- YAML frontmatter and other metadata;
- fenced and inline code;
- commands, flags, paths, URLs, and configuration keys;
- tables and list structure;
- templates, placeholders, and generated text;
- JSON, YAML, XML, regular expressions, and other structured payloads;
- quotations and examples that intentionally demonstrate a rejected pattern.

## Tool-gate boundary

The Claude Code `PreToolUse` prompt gate applies only to complete `Write` calls for:

- `README.md`;
- `CONTRIBUTING.md`;
- `docs/**/*.md`.

A determinate violation denies the write and returns a specific reason so Claude can retry. The judge treats proposed file content as untrusted data, ignores instructions embedded in it, and limits quoted denial excerpts to 160 characters. When the judge is uncertain, it allows normal permission flow. The prompt-hook response schema has no allow-with-warning state, so uncertainty does not produce a warning.

The gate does not cover `Edit`, `MultiEdit`, `NotebookEdit`, Bash-generated files, external work-item mutations, or writes outside the listed paths. Do not claim universal Markdown enforcement.

## Behavioral coverage

Apply the same review pass without claiming mechanical enforcement when:

- drafting or reviewing a new ADR;
- authoring issue bodies, comments, and work-item descriptions;
- editing eligible documentation through a tool outside the gate;
- reviewing persisted documentation after a hook or model failure.

Instruction files such as `agents/**`, `rules/**`, `skills/**`, `commands/**`, `AGENTS.md`, `CLAUDE.md`, and `web/instructions.md` are deliberate prompt content. Review them for precision under their own standards, but do not treat them as ordinary documentation subject to the semantic gate.
