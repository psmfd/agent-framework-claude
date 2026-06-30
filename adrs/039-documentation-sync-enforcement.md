# ADR-039: Documentation Sync Enforcement via Three-Layer Prevention

**Status:** Accepted
**Date:** 2026-04-14

## Context and Problem Statement

The repo maintains multiple catalog documents (README.md Current Skills/Agents/Rules sections, AGENTS.md agent table, directory tree) that must stay in sync with actual files on disk. No automated checks or process guards exist for these catalog sections. Drift has occurred silently — the README hooks/ directory tree was missing two hook scripts after a merge — and would have gone undetected without a manual audit. The risk grows as the repo adds more skills and rules.

## Considered Options

* **Option A** — Three-layer prevention: automated detection in validate.sh, PR process checklist in the PR template, and review guidance in the post-implementation-review rule
* **Option B** — Automated detection only (validate.sh) — rely on validation to catch drift post-hoc
* **Option C** — Process-only (PR template + review rule) — rely on author discipline, no automation
* **Option D** — Status quo — no enforcement, rely on ad-hoc audits

## Decision Outcome

Chosen option: **Option A**, because no single layer is sufficient. Automated detection catches drift before push but does not prevent it from entering a PR branch. Process checklists encourage authors to make paired updates at authoring time but can be skipped. Review guidance ensures a final cross-file check before merge. The layers are complementary — automation catches drift at any time, the checklist catches it at authoring time, and review catches what both miss.

### Tradeoffs

* Good: drift is detectable via `./validate.sh` at any point, not just during audits
* Good: authors are reminded of sync requirements at PR-authoring time via the checklist
* Good: reviewers have explicit guidance to check paired files during post-implementation review
* Good: the Documentation Sync Map in CONTRIBUTING.md serves as a single authoritative reference for all known sync pairs
* Bad: README catalog checks are warnings, not errors — intentional drift during in-progress work is permitted, meaning drift will not block a push
* Bad: the README directory tree (hooks/, scripts/) is not automatically checked — it requires the review layer to catch
* Bad: adds new sections to already-long documents (CONTRIBUTING.md, PR template)

## More Information

* Issue: #173 (consolidates #139, #138, #137, #165)
* `check_readme_catalog()` in validate.sh is modeled on `check_agent_catalog()` — same bidirectional comparison approach, same warning-not-error policy
* The Documentation Sync Map in CONTRIBUTING.md is the canonical list of all known sync pairs and should be updated when new paired files are introduced
