# ADR-080: Genericize predecessor private identifiers for public release

**Status:** Accepted
**Date:** 2026-06-30

## Context and Problem Statement

This repository is the Claude-only successor bound for **public** release
([ADR-076](076-claude-only-successor-genesis.md)). [ADR-060](060-local-only-gh-identity-pin.md)
established that ADR *bodies* are exempt from de-hardcoding — predecessor account
names and incident references were preserved as an archival audit trail, on the
reasoning that scrubbing them would be revisionist. That reasoning held while the
predecessor was a **private** repo. Public release inverts it: predecessor private
identifiers — the employer enterprise name, work GitHub accounts, a sandbox org,
private sibling repositories, internal service/component names, private issue-tracker
URLs, and personal infrastructure detail — must not enter permanent public git
history. A consensus-by-replication private-content audit (N=3 `security-review-expert`)
found these identifiers across roughly two dozen ADR bodies plus several live files.

## Considered Options

* **Genericize across all content, including ADR bodies** — replace each private
  identifier with a stable neutral placeholder, preserving every decision's substance
  and narrative.
* **Honor ADR-060's exemption unchanged** — leave ADR bodies as-is. Rejected: it
  publishes the employer name, work account logins, private repo names, and a real
  security incident.
* **Delete the affected ADRs** — rejected: destroys the decision record entirely,
  far more lossy than genericization.

## Decision Outcome

Chosen option: **genericize across all content, including ADR bodies.** Predecessor
private identifiers are replaced with stable placeholders that preserve each ADR's
decision and rationale; only the identifying strings change. This **amends the
ADR-body archival-exemption clause of ADR-060 for the public-release context** —
ADR-060's local-only gh-identity-pin decision otherwise stands unchanged. The
canonical mapping:

| Private identifier | Placeholder |
|---|---|
| employer enterprise name | "an external enterprise" |
| work GitHub account / old personal handle | `account-a` / `account-b` |
| sandbox GitHub org | "a sandbox org" |
| private sibling repos (config repo, service repo) | "a sibling repo" / "an internal service repo" |
| internal service + its components / env var | "an internal service" / generic component descriptions |
| predecessor issue-tracker URLs | plain `#NN`, private org stripped |
| personal VPS detail | "ARM64 VPS" |

Kept as intentional public references: the `psmfd` org, `psmfd/agent-framework`
(predecessor) and `psmfd/agent-framework-claude` (this repo), the MIT copyright holder,
and public technologies (e.g. `k3s`).

### Tradeoffs

* Good: no employer, client, PII, or private-infrastructure leakage in public history.
* Good: decision records remain intact and useful — substance and rationale preserved.
* Bad: ADR bodies lose literal archival fidelity (specific account names and incident
  repos become placeholders). Accepted as the cost of public release; the narrative
  and the reason each guard exists are retained.

## More Information

Amends [ADR-060](060-local-only-gh-identity-pin.md) (ADR-body exemption, for the public
context only). Driven by [ADR-076](076-claude-only-successor-genesis.md). The audit was
performed via the consensus-by-replication shape (`rules/consensus-by-replication.md`).
