---
description: 'Require an ADR for significant convention or architecture changes'
---

# ADR Required for Significant Decisions

**Enforcement:** validate.sh check_adrs (numbering, status, required sections); self-report only (when-to-create judgment)

When making a change that introduces, modifies, or removes a convention, pattern, or architectural decision:

- **Create an ADR** in `adrs/` using the MADR minimal template (`adrs/TEMPLATE.md`).
- The ADR must include: context and problem statement, considered options, and decision outcome with justification.
- **Supersession, not editing:** when revising a prior decision, mark the original as superseded and create a new ADR. Do not edit the body of the superseded ADR.
- **Numbering:** sequential, zero-padded three digits, never reused.

## When this rule applies

- Adding a new development convention or rule
- Changing the architecture or file structure of the repo
- Adopting or dropping a technology, tool, or format
- Any decision where alternatives were seriously considered and the rationale should be preserved

## When this rule does not apply

- Trivial changes: typo fixes, formatting, single-line config edits
- Implementation details that do not affect conventions or architecture
- Adding a new skill or agent that follows existing patterns (the patterns are already covered by ADRs)
- Documentation-only edits that clarify existing decisions without changing them
