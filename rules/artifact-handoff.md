---
description: 'Write large review artifacts to the tracked .review/ handoff channel; never merge them to the integration branch'
---

# Artifact Handoff

**Enforcement:** CI artifact-review-guard.yml

When an agent or the orchestrator produces a large artifact that needs
line-anchored human review — an ADR draft, a synthesized multi-reviewer report,
an evidence payload — write it to the tracked `.review/` directory rather than
dumping it inline in the conversation or to an arbitrary path.

This is a plain filesystem write (Claude `Write` / `Edit`)
to a path inside the repo. It uses no MCP server and no network call, so it is
fully compatible with `rules/no-mcp-servers.md` and ADR-046.

## Contract

- Write artifacts to `.review/<descriptive-name>` (e.g. `.review/adr-draft.md`).
- Artifacts are **tracked** — they appear in the pull-request diff so reviewers
  can comment line-by-line. Do **not** add a `.gitignore` rule for `.review/`.
- Artifacts are **ephemeral**: they live on the feature branch during review and
  must be deleted before the PR merges. Only `.gitkeep` and `README.md` persist.
- The `.review/` content must **never reach the integration branch** (`dev`). A
  squash merge preserves the branch tree at merge time, so any artifact present
  at merge would land on `dev`.

## Enforcement

The never-merge contract is enforced by the `artifact-review-guard` CI check
(`.github/workflows/artifact-review-guard.yml`), a required status check on the
`protect-dev` ruleset. It fails any PR whose diff adds files under `.review/`
other than the `.gitkeep` / `README.md` stubs. Enforcement is **path-based** (it
keys on the files in the diff), not on a label — the presence of the files is the
invariant.

## When this rule does not apply

- Outside a local repository checkout. In a Claude.ai / Claude Code Web session
  there is no working tree and no `.review/` directory, so this convention is
  inapplicable; return artifacts inline instead.
- Small results that belong in the conversation or in a normal source path (a
  code change, a one-paragraph finding). Reserve `.review/` for large artifacts
  staged specifically for human review before merge.
