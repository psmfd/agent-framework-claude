# .review/

Artifact handoff channel for line-anchored human review of large agent-produced
artifacts (ADR drafts, synthesized multi-reviewer reports, evidence payloads).
See [`rules/artifact-handoff.md`](../rules/artifact-handoff.md) and
[ADR-064](../adrs/064-artifact-handoff-channel.md).

## Contract

- Write artifacts here with a plain filesystem write — no MCP, no network call.
- Artifacts are tracked so reviewers can comment inline on the PR diff.
- Artifacts are ephemeral: delete them before the PR merges. Only this file
  and `.gitkeep` persist.
- `artifact-review-guard` (CI, required on `protect-dev`) fails any PR whose
  diff adds files here beyond `.gitkeep` and this README.
