# ADR-097: Orchestrator-Mediated Expertise Consumption in Delegation Briefs

**Status:** Accepted
**Date:** 2026-07-22

## Context and Problem Statement

ADR-094 shipped `/expertise` retrieval and ADR-096 added gated write-back, but
nothing directs the orchestrator to consume stored expertise during normal
work — subagent delegation briefs carry no expertise today (#80). The Pi
reference methodology (pi_config epic #595, ADR-0028) searches expertise at
task time and prepends bounded results to each subagent brief. Porting that
shape here must stay inside the `rules/no-mcp-servers.md` boundary (visible
tool-call retrieval, untrusted tool output, never system-role context) and
must reckon with a risk ADR-094 never had to: one retrieval woven into N
briefs is a 1-to-N propagation amplifier for a poisoned or ambiguously-worded
entry. The API's draft/review queue is a soft trust boundary (one local
reviewer, not the signed-provenance bar ADR-046 named), so approval reduces
likelihood, not blast radius.

A three-agent research fan-out (security-review-expert advisory mode,
docs-expert, code-review-expert) informed this design.

## Considered Options

* **Option A** — Hook- or session-start-driven automatic expertise injection.
* **Option B** — Subagents self-invoke `/expertise` mid-task as needed.
* **Option C** — Orchestrator-mediated: one search at task-classification
  time, results woven into briefs as bounded, delimited, untrusted advisory
  blocks; governed by a new always-loaded rule.
* **Option D** — Status quo: retrieval exists but consumption is ad hoc.

## Decision Outcome

Chosen option: **Option C**, recorded in `rules/expertise-consumption.md`.
Option A recreates the injection surface ADR-046 removed and is prohibited by
`rules/no-mcp-servers.md`. Option B multiplies the untrusted-content entry
points, breaks the Sub-Agent Obligations model (`orchestrator-protocol.md`),
and defeats single-point containment. Option D leaves the expertise store
write-mostly.

Key design points, and where they deliberately deviate from issue #80's text:

1. **Trigger reuses existing mandatory steps.** The search fires immediately
   after a Research or Implementation task classification plus the
   agent-catalog scan — both already mandatory and audited. The issue's
   "plausibly covered by stored expertise" judgment is not adopted: a second
   fuzzy threshold would hand an instruction-following agent a second
   rationalization surface ("not plausibly covered") on top of the one the
   protocol already polices ("this seems simple"). Exempt-classified tasks
   and the established trivial carve-outs are excluded for free.
2. **"Skip silently" narrowed to "non-blocking but announced."** The issue's
   literal wording conflicts with `SKILL.md`'s per-exit-code user-messaging
   table and would make a mandatory step silently and permanently inert under
   a broken config, indistinguishable from "ran, found nothing." A skip is
   legitimate only after an attempted call returns a nonzero exit, and is
   announced as a one-line append to the already-mandatory classification
   announcement. No retry loops, no blocking. (Two of the three fan-out
   agents independently converged on this override.)
3. **Anti-laundering is the load-bearing containment control.** Woven content
   is verbatim truncated excerpt inside the preserved hygiene envelope, with
   a per-brief untrusted-advisory preamble that travels with the content
   (subagents cannot see the orchestrator's rule context). Paraphrasing entry
   text into the brief's own imperative language strips the provenance marker
   that lets a subagent tell data from instruction — prohibited.
4. **Non-authorization clause.** Woven content never satisfies plan-approval,
   authorization, or consent requirements — for the delegate or,
   reflexively, for the orchestrator's own actions. Uniform framing across
   all delegate types was chosen over excluding write-capable delegates
   (brittle against tool-grant drift, and it loses the audience the
   mechanism serves best).
5. **Bounds adopted from the Pi reference: 4 KB per entry, 24 KB per woven
   block.** These are context-budget controls, not security controls (one
   sentence can carry an injection). Per-entry overflow: truncate-and-mark
   inside the envelope, never through a delimiter; block overflow: drop
   lowest-relevance whole entries and state the drop count — fragments from
   many entries are harder to provenance-check than fewer complete ones.
6. **Not mirrored to `web/instructions.md`.** The skill is loopback/Lima-
   gated and unprovisioned on every web surface, so every invocation there
   is a guaranteed no-op; mirroring would be a false affordance. Consistent
   with skills being absent from the web sync map.

### Tradeoffs

* Good: the expertise store starts paying rent on every substantive task;
  containment is enforced at a single choke point (the orchestrator) with
  provenance preserved end-to-end; zero new mechanism — the trigger, the
  announcement line, and the skill all exist already.
* Bad: one more always-loaded rule competing for session-start context
  budget (kept terse; mechanics stay in the on-demand `SKILL.md`); a search
  call added to the critical path of every Research/Implementation task
  (bounded by the skill's 3 s connect / 15 s max timeouts and the non-retry
  posture); the 4 KB/24 KB caps are judgment values inherited from Pi, not
  measured for this framework.
* Accepted residual risks: (1) a poisoned entry that survives the review
  queue still reaches N subagent contexts — mitigated by framing and the
  non-authorization clause, not eliminated; (2) enforcement is self-report
  only — no hook verifies the search ran or the framing was preserved;
  (3) relevance filtering ("2 omitted") is an orchestrator judgment and only
  auditable via the announced counts.

## More Information

* #80 (this feature); siblings #81/ADR-096 (write-back, shipped) and #82
  (subagent candidate capture, open)
* ADR-094 (retrieval skill), ADR-096 (write-back), ADR-046 (removal of the
  injection mechanism this design must not recreate)
* `rules/expertise-consumption.md` (the resulting norm),
  `skills/expertise/SKILL.md` (mechanics)
* Pi reference: pi_config epic #595, ADR-0028 (`buildCanonicalQuery`, 4 KB/24
  KB caps)
