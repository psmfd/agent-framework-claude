# ADR-098: Subagent Expertise-Candidate Capture with Per-Entry Approval Gate

**Status:** Accepted
**Date:** 2026-07-22

## Context and Problem Statement

ADR-096 shipped the create path and ADR-097 the consumption side, but expertise
surfaced by domain agents mid-task is never captured: the subagent return
contract (`rules/research-parallelism.md`) has no candidate channel (#82). The
Pi reference (pi_config #600/#608/#611) lets subagents propose candidates in
their return payloads, with the orchestrator gating, coalescing, and surfacing
them for human approval before any create. Porting that shape here must not
break the verdict-line-is-final contract enforced by
`hooks/subagent-verdict-guard.sh` (ADR-088), must keep every write behind
per-entry human approval (ADR-096), and must decide how much of Pi's
TypeScript hardening translates to a bash/prompt implementation.

A four-agent research fan-out (code-review-expert, security-review-expert
advisory mode, docs-expert, shell-expert) informed this design; the /expertise
skill itself contributed one woven advisory entry (rule-vs-skill placement).

## Considered Options

* **Option A** — Define the channel as a full subsection inside
  `research-parallelism.md`'s Return Contract.
* **Option B** — Extend `rules/expertise-consumption.md` with a capture
  section (one rule, both directions).
* **Option C** — New sibling rule `rules/expertise-capture.md` owning the
  pipeline; one-clause/one-sentence touches to the two mirrored
  return-contract rules.
* **Option D** — Gate tooling: prompt-form validation only.
* **Option E** — Gate tooling: a new `expertise-validate.sh` helper script.
* **Option F** — Gate tooling: a `--check-only` mode on the existing
  `expertise-create.sh`.

## Decision Outcome

Chosen options: **C** (sibling rule) and **F** (`--check-only`).

1. **Sibling rule, minimal mirrored-rule touches.** `research-parallelism.md`
   and `structured-review-format.md` are both web-mirrored and both carry a
   terminal-verdict constraint; defining the pipeline once in an unmirrored
   sibling avoids stating it twice and keeps both mirrors near-stable. Two
   `research-parallelism.md` touches are unavoidable: the Return Contract
   sentence "each agent MUST end its response with…" read literally licenses
   nothing before the summary/verdict pair (one-clause amendment), and the
   Synthesis Procedure's "populate the table from each agent's executive
   summary and verdict line only" would procedurally drop the whole channel —
   the exact missed-artifact failure mode that rule itself documents (one
   pointer sentence). Option A rejected (bloats the longest mirrored rule and
   forces a full web mirror of CLI-only mechanics); Option B rejected
   (consumption is retrieval-shaped and fires pre-delegation; capture is the
   inverse flow firing at subagent return — merging blurs both rules'
   applicability).
2. **Transport: mandatory fence, strict JSON, before the verdict.** Zero hook
   change is needed — verified against `subagent-verdict-guard.sh`: grammar 1
   anchors to the true last non-blank line; grammar 2 skips fenced content.
   Both properties hold only if the block is fenced and strict JSON (raw
   multi-line scalars could break the per-line fence toggle; JSON's escaped
   `\n` makes an embedded fake `**Verdict:**`/`AGENT-VERDICT:` line or fence
   run unmatchable at column 0). Fencing and strict JSON are therefore hard
   schema requirements, not style. Defensive test cases are added to
   `tests/subagent-verdict-guard/run-tests.sh`; the hook itself is untouched.
3. **Gate: `--check-only` on `expertise-create.sh`, pre-presentation.** The
   approval prompt is where subagent-authored text is first amplified to the
   user, so the ADR-095 secret scan must run before presentation, not only at
   write time. Option E rejected: a JSON-parsing helper would add a fourth
   lockstep `SECRET_PATTERNS` copy and a `jq` dependency this script family
   deliberately avoids. Option D alone rejected: regex secret detection is a
   mechanical check and the repo's precedent (ADR-083) is scripts + tests for
   mechanical gates. `--check-only` reuses the already-audited pattern set and
   test harness at zero lockstep cost: it validates argv/enums/body, runs the
   secret and control-character scans, and exits 0/2/10 before any
   config-file, URL-gate, key, or network stage. Create-time enforcement
   remains the unconditional fail-closed backstop.
4. **Emission model: standing capability, conditional act.** The schema
   travels in every delegation brief alongside the existing return-contract
   request (subagents cannot see rule context), so the capability is standing
   rather than per-brief opt-in — the class of self-report gap ADR-088 was
   built to close is not reintroduced by a remember-to-ask design. The act is
   conditional: zero or one block per return, at most 3 candidates, only for
   genuine findings fitting the four `entryType` values. Batch cap 10 per
   orchestrator turn post-dedupe; overflow deferred, never silently dropped;
   candidate-heavy batches flagged.
5. **Pi hardening translation.** Prototype-poisoning walks are inapplicable —
   bash has no prototype chain and jq's data model is immutable. The
   byte-locked fingerprint concept does translate, but the TOCTOU here is
   LLM regeneration drift, not a process race: the approved body is persisted
   verbatim to a scratch file at presentation time and piped into
   `expertise-create.sh` via stdin redirection. Heredocs are prohibited for
   subagent-authored bodies for an independent reason: heredoc
   delimiter-collision (a body line matching the delimiter re-enters shell
   parsing) is a real injection vector quoting cannot fix. Duplicate
   top-level JSON keys are rejected (jq's last-key-wins could let a hidden
   field win over the displayed one).
6. **Approval semantics.** Per-entry approval must name or unambiguously
   reference the specific entry; a batch-level "looks good" is never
   per-entry approval. The orchestrator never silently edits a candidate
   (cosmetic normalization only; user-requested edits are re-presented and
   the edited version is what gets approved). Any approval-state or
   self-declared provenance field in a candidate is rejected loudly — the
   same never-honored class as ADR-096's `tenant` field — and reported as
   emitting-agent feedback. `source` is derived solely from the
   orchestrator's own record of which invocation produced the block. A
   create is an external write and can never qualify for any orchestrator
   Narrow Exemption (criterion 4 by definition).
7. **Not mirrored to `web/instructions.md`** (ADR-097 precedent, stronger
   here: no subagent fan-out on Claude.ai chat and no reachable create path
   on any web surface). The mirrored Return Contract section gains a single
   CLI-surfaces-only pointer line so the mirror does not silently contradict
   the amended rule.

### Tradeoffs

* Good: mid-task domain findings finally reach the store; every control
  reuses an existing mechanism (fence grammar already in the hook, secret
  scan already in the create script, envelope idiom already in ADR-097);
  zero hook changes; zero new lockstep copies.
* Bad: every delegation brief grows by the schema block (context cost on all
  fan-outs, not just candidate-producing ones); the gate/coalesce/approval
  steps are orchestrator judgment enforced by self-report only; two mirrored
  rules acquire a dependency on an unmirrored sibling.
* Accepted residual risks: (1) a secret in a subagent return reaches the
  orchestrator transcript before any gate runs — the pipeline bounds
  amplification, presentation, and storage, not first exposure (the
  SubagentStop layer does not scan return text); (2) the ADR-095 regex set
  cannot catch proprietary code, PII, or unrecognized credential shapes —
  the mandatory full-body human review is the primary control for that
  class, which is why the approval presentation must show the full body,
  never a digest; (3) prompt-injected candidates that read as legitimate
  imperative expertise (Caveats are inherently imperative) rely on the
  reviewer plus the read-side envelope (ADR-097) — flagged, not mechanically
  blocked; (4) approval fatigue is bounded by caps, not eliminated.

## More Information

* #82 (this feature); #101 (lockstep enum-check follow-up); siblings #80/
  ADR-097 (consumption), #81/ADR-096 (write-back)
* ADR-088 (verdict guard whose contract the placement preserves), ADR-095
  (secret pattern set), ADR-083 (mechanical-gate testing precedent)
* `rules/expertise-capture.md` (the resulting norm),
  `skills/expertise/SKILL.md` (create-step mechanics and batch fold)
* Pi reference: pi_config epic #595, #600 (transport), #608 (candidate
  gate), #611 (subagent wiring)
