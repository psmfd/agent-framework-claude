# ADR-060: Make the gh-identity Pin Local-Only and Genericize Distributed Content

**Status:** Accepted
**Date:** 2026-05-29

> **Amended:** the ADR-body archival-exemption clause is amended for the public-release
> context by [ADR-080](080-genericize-private-identifiers-for-public-release.md); this
> ADR's local-only gh-identity-pin decision otherwise stands.

## Context and Problem Statement

This repository is a shared, distributed framework: its rules, instructions, and example files are consumed by other repos and other developers. ADR-054 made the gh-identity guard's strict layer active here by **committing** `.gh-expected-identity` with one developer's login (`account-a`), and `rules/gh-identity-guard.md` described the motivating incident using this repo's concrete account and org names (`account-a`, `account-b`, `a sandbox org`). Several other committed files carried the same hardcoded identity: the `git clone` URLs in `README.md`, `CONTRIBUTING.md`, and `setup.sh` (which also pointed at the stale pre-migration owner), and the `scripts/wim/manifest.example.json` / `manifest.schema.json` example values.

Hardcoding a specific developer's or org's identity in distributed, shared content is wrong: an adopter who clones or reads the framework inherits a pin that fails their pushes until they delete it, sees a rule that names accounts meaningless to them, and copies examples wired to someone else's org. Identity is per-developer, per-machine personalization — it must not live in shared version control.

## Considered Options

* **Option A** — Make `.gh-expected-identity` local-only (gitignore + `git rm --cached`, add a `.example` template), genericize the distributed rule/docs/example files, and keep the guard mechanism unchanged.
* **Option B** — Keep committing the pin but add a "replace this value" comment. Does not fix the problem — a real account name still ships in distributed content.
* **Option C** — Remove the pin mechanism entirely and rely on accessibility-only. Loses the wrong-but-also-authorized-account detection that motivated ADR-054's hybrid signal.

## Decision Outcome

Chosen option: **Option A.**

The pin file is per-developer local config, analogous to `.git/` — it configures personal identity, not shared project behavior. `.gh-expected-identity` and `.gh-identity-allowlist` are added to `.gitignore`; the committed pin is removed from tracking with `git rm --cached` (the local copy remains, so an existing developer's guard is unaffected). A committed, **comment-only** `.gh-expected-identity.example` documents the opt-in (a copy made without editing yields zero valid logins, so the guard fails closed and tells the developer to fix it, rather than silently pinning a placeholder). `setup.sh` gains an optional prompt to create the local pin. The hooks need no code change — they already resolve the pin by path at runtime and fall back to the accessibility probe when it is absent (with a fail-closed path for a present-but-empty pin).

The distributed rule `rules/gh-identity-guard.md` is genericized to describe the mechanism abstractly (no account/org names). The prior content already carried no account names in `AGENTS.md`, `web/instructions.md`, the Copilot mirror, and `docs/multi-account-git-identity.md`, but several of those (plus the rule's override table) described the pin as "committed" / "version-controlled" — now corrected to "local-only (gitignored)" to match the new convention. The Copilot mirror needed no change (it never used that descriptor). The stale `git clone` URLs and the wim example/schema files are genericized to placeholders (`<your-account>`, `your-org`, an `example.com` schema `$id`).

`.secrets-guard-allowlist` is deliberately **not** gitignored: `rules/secrets-guard.md` designates it as version-controlled for shared fixture suppression (visible in PR review), a different design intent from the per-developer identity files.

**ADRs are exempt from this de-hardcoding.** The account names appear in roughly ten ADR bodies (both Accepted and Superseded) as archival incident context — what actually happened and why a guard was built — not as instructions an adopter follows. `rules/adr-required.md` forbids editing superseded ADR bodies, and the same supersession-not-editing principle keeps Accepted ADR bodies as faithful historical records. Scrubbing them would be revisionist and would destroy the audit trail. This mirrors the existing `validate.sh` treatment of superseded ADRs as a frozen special class. Any future automated "no account names" lint must exempt `adrs/`.

This ADR **amends** ADR-054 (the convention "this repo commits the pin"); it does not supersede it. ADR-054's architecture — the two-layer fail-closed guard and the hybrid pin/accessibility signal — is unchanged and remains the live record, so ADR-054 keeps `Accepted` status (consistent with the ADR-057/058 amend-not-supersede precedent).

### Tradeoffs

* Good: no developer/org account name ships in distributed config, rules, examples, or setup; adopters and forks are unaffected; the `.gitignore` entry is self-documenting.
* Good: the guard mechanism, fail posture, and signal model are unchanged; an existing developer's local pin keeps working.
* Bad: the framework repo's own pin value is no longer visible in PR review — accepted, because it affects only the local developer's guard and the hooks report a mismatch immediately if it is wrong.
* Bad: a fresh clone defaults to the weaker accessibility signal until the developer opts into a pin — accepted, and documented in the rule and the `.example`.

## More Information

* Amends [ADR-054](054-gh-identity-enforcement-layers.md) (the two-layer guard and hybrid signal are unchanged). Pin/allowlist override semantics: [ADR-052](052-gh-identity-preflight-guard.md). Frozen wim scripts that bound the example-file edits: [ADR-050](050-frozen-wim-scripts.md).
* Files: `.gitignore`, `.gh-expected-identity` (untracked), `.gh-expected-identity.example` (new), `setup.sh`, `rules/gh-identity-guard.md`, `AGENTS.md`, `web/instructions.md`, `docs/multi-account-git-identity.md`, `README.md`, `CONTRIBUTING.md`, `scripts/wim/manifest.example.json`, `scripts/wim/manifest.schema.json`.
* Prompted by a maintainer directive: a shared framework must not hardcode developer/org identity outside local-only personalization.
