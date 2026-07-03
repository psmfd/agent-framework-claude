# ADR-091: No Skills-Based Lazy Loading for Topic-Triggered Rules

**Status:** Accepted
**Date:** 2026-07-03

## Context and Problem Statement

Behavioral rules load into context every session (~23–31k always-loaded
tokens, multiplied under parallel sub-agent fan-out — #27). #50/ADR-089 already
`paths:`-scoped the rules with a reliable file trigger. The remaining costly
rules (`debian-baseline`, `semver-tagging`, and similar) are topic-triggered
with no file signal, and first-party guidance assigns topic-triggered loading to
**skills**. #51 asks whether to convert such rules to on-demand skills to cut the
always-loaded baseline — a change that would revisit ADR-074/075's no-skill-layer
architecture. A three-agent research fan-out (platform mechanics, architecture
fit, silent-miss risk) evaluated the tradeoffs.

## Considered Options

* **Option A** — Native skill layer: convert candidate rules to `~/.claude/skills/`
  SKILL.md files, model-invoked on description match.
* **Option B** — Read-on-demand: de-symlink candidate rules from auto-load, keep
  them on disk, rely on AGENTS.md's existing per-rule pointer paragraphs + an
  agent `Read` when relevant.
* **Option C** — Status quo: keep candidate rules always-loaded and unscoped.

## Decision Outcome

Chosen option: **Option C (no-go)**, because the bounded savings do not justify
the structural costs, and the framework's "all policy always present and
auditable" guarantee is a core value the alternatives erode:

1. **Bounded savings, structural cost.** The candidate set is ~5 small,
   low-frequency rules. Option A reintroduces the `skills/` directory, frontmatter
   schema, and `validate.sh` machinery ADR-074 deliberately removed, and breaks
   `web/instructions.md`'s zero-install paste distribution model.
2. **Sub-agent propagation breaks.** Rules auto-load into every custom agent (a
   full independent re-read — the fan-out cost #27 measured). A skill reaches a
   sub-agent only via a per-agent `skills:` frontmatter entry, so converting a
   rule silently strips it from every `agents/*.md` unless each is edited — a new
   doc-sync liability the rules model does not have.
3. **Unquantified reliability, eroded guarantee.** No first-party skill
   trigger-reliability rate exists; platform docs frame rules/skills as "a
   request, not a guarantee," and description-matching fails on lexical mismatch
   ("Ubuntu VPS firewall" never says "Debian"). Conversion trades guaranteed
   presence for match-dependent presence on policy content, reopening the
   self-invocation surface `disable-model-invocation: true` (ADR-074) exists to
   close — for higher-stakes content than the advisory agents it was built for.
4. **The proposed go-criterion is unsound.** "Topic-triggered + no backstop +
   non-security" inverts the risk logic: no-backstop / model-only rules
   (`no-mcp-servers`, `orchestrator-protocol`) are precisely the ones that must
   stay loaded, since the text is the entire control; and mixed-risk rules
   (`debian-baseline`'s SSH-lockout clause, `conventional-commits`' feat/fix and
   no-authorship clauses feeding permanent public artifacts) cannot be
   binary-classified.

Option B is cheaper than A (no new machinery, no web-parity break) but carries
the same trigger-reliability gap — the agent must still *choose* to Read — and
AGENTS.md's per-rule summary already duplicates the key content, so its marginal
saving is small. It is the correct first thing to evaluate **if** the
always-loaded budget later becomes a genuine constraint, and only after #52's
observability logger can measure real trigger hit-rate — shipping an unmeasured
reliability mitigation is itself a risk.

This ADR affirms ADR-074/075 with fuller rationale; it does not supersede them.

### Tradeoffs

* Good: preserves the always-present, auditable policy guarantee; no second
  content-loading mechanism, no web-parity break, no sub-agent-propagation gap;
  records the rejection so #51 is not re-litigated.
* Bad: the ~23–31k always-loaded baseline (×N under fan-out) is unchanged; the
  bounded saving is left on the table pending a measured, lower-risk revisit.

## More Information

* #51 (this decision), #27 (rule loading-cost classification)
* #50 / ADR-089 (`paths:` scoping — the file-triggerable subset, already handled)
* ADR-074, ADR-075 (no-skill-layer architecture — affirmed, not superseded)
* #52 (InstructionsLoaded observability logger — prerequisite for any future
  revisit via Option B)
