# ADR-066: Annotated tags for the manual path, lightweight for automated releases

**Status:** Accepted
**Date:** 2026-06-09

## Context and Problem Statement

`rules/semver-tagging.md` required all version tags to be annotated (`git tag -a`).
The release automation (`semantic-release` via `@semantic-release/github`, ADR-042)
creates tags through the GitHub Releases API, which produces **lightweight** tags.
A pre-release review found `v2.0.0`–`v2.2.0` are all lightweight, so the stated
rule and the actual automated behavior diverge. The rule cannot be satisfied by the
automated path without adding `@semantic-release/git` (a heavier pipeline change),
and converting automation-created tags by hand defeats the point of automation.

## Considered Options

* **Option A** — Scope the annotated requirement to manually-cut tags; accept that
  automated release tags are lightweight by design and document it.
* **Option B** — Add `@semantic-release/git` (plus config) so the pipeline produces
  annotated tags and back-commits a changelog to `main`.
* **Option C** — Status quo: leave the rule stating "annotated" while automation
  keeps producing lightweight tags (a standing rule-vs-reality mismatch).

## Decision Outcome

Chosen option: **Option A**, because lightweight tags from the Releases API are the
industry-standard, expected output of `semantic-release`, and they carry the same
SemVer information the project needs. Option B adds moving parts (a back-committing
plugin that would itself create `dev`/`main` divergence) for no practical gain, and
Option C leaves a documented falsehood that misleads reviewers and future tooling.
The annotated requirement is retained for the manual path, where `git tag -a`
provides authorship/date metadata and a signing anchor for out-of-band tags.

### Tradeoffs

* Good: rule matches reality; no pipeline change; reviewers stop flagging a non-issue.
* Good: the manual path keeps annotated tags where they add value.
* Bad: release tags lack a tagger identity/date in the object (the GitHub Release
  object carries that metadata instead), and `git describe` shows lightweight tags.

## More Information

* ADR-042 — release automation via `semantic-release` on pushes to `main`.
* `rules/semver-tagging.md` — updated Tag Format section.
* Surfaced by the pre-release solution review (gh-cli-expert finding).
