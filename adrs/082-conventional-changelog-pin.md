# ADR-082: Pin the conventional-changelog preset below the writer-skew break

**Status:** Accepted
**Date:** 2026-06-30

## Context and Problem Statement

Releases are cut by `semantic-release@25` ([ADR-042](042-release-automation.md)) with
`preset: "conventionalcommits"`, which requires a direct devDependency on
`conventional-changelog-conventionalcommits`. On 2026-06-26 the `conventional-changelog`
monorepo published a coordinated major bump: `conventional-changelog-writer@9` replaced
Handlebars template strings with JavaScript render functions (and raised the Node floor to
`>=22`), and `conventional-changelog-conventionalcommits@10` emits those render functions.
But `semantic-release@25`'s bundled `@semantic-release/release-notes-generator@14` still
depends on `conventional-changelog-writer@^8` (Handlebars). The two are coupled at the API
level only — npm prints no error — so installing preset v10 against writer v8 **silently
breaks changelog generation the first time a release runs**. Dependabot opened that exact v10
bump (PR #4). The repo had not yet cut a release, so the toolchain was unexercised.

## Considered Options

* **Pin the preset to a safe major (`^9`) + a Dependabot `ignore` for its next major.** v9 is
  `writer@8`-compatible and a drop-in; v8 is frozen (one release, no patches).
* **npm `overrides`.** Targets the wrong layer — the preset has no graph dependency on the
  writer, and Dependabot ignores the `overrides` field (dependabot-core #5590), so an `ignore`
  rule is still required. Redundant.
* **Drop the preset, inline `parserOpts`/`writerOpts`/`releaseRules` in `.releaserc.json`.**
  Removes the moving dependency but transfers permanent maintenance of preset logic to the repo.
* **Switch release tooling** (git-cliff, release-please, release-it, changesets). Only git-cliff
  truly escapes the conventional-changelog coupling, but it replaces only changelog generation
  and forces a bespoke bump→tag→release workflow; release-please flips to PR-mediated releases;
  release-it shares the identical coupling; changesets abandons commit-derived automation.
* **Take v9.3.1 for the security fix.** v9.3.1 includes a markup-injection fix (skip mention
  linkification inside inline code) that the frozen v8 line will never receive.

## Decision Outcome

Chosen option: **pin `conventional-changelog-conventionalcommits` to `^9.0.0` and add a
Dependabot `ignore` for its `version-update:semver-major`**, keeping `semantic-release`. The
`^9` pin takes the v9.3.1 security fix and stays `writer@8`-compatible; the `ignore` prevents
Dependabot from re-proposing the breaking v10 (safe v9.x minor/patch PRs still flow). Switching
tools is rejected as over-correction for a transient (if recurring-class) ecosystem lag, and
`overrides`/inline-config are rejected as the wrong layer / higher maintenance.

### When to revisit

v10 becomes safe once `@semantic-release/release-notes-generator` adopts
`conventional-changelog-writer@^9` (a major bump of that plugin, tracked upstream in
`semantic-release/release-notes-generator#996`). Watch signal:

```bash
npm view @semantic-release/release-notes-generator dependencies
# safe when: conventional-changelog-writer: ^9.0.0
```

At that point: lift the Dependabot `ignore`, bump the preset to v10, and verify the Actions
runner's `lts/*` still satisfies the writer@9 Node `>=22` floor. Realistic timeline: weeks to
months (no upstream milestone yet). If the conventional-changelog ecosystem produces this break
repeatedly, reopen the git-cliff migration — its Rust toolchain has no npm coupling and the
class cannot recur.

### Tradeoffs

* Good: one-time, two-line configuration change; keeps the existing release pipeline; takes a
  real security fix; the breaking major cannot land by accident.
* Good: fully reversible — delete the `ignore` and bump to v10 when the signal fires.
* Bad: the repo deliberately tracks one major behind latest for this package; the `ignore` must
  be lifted manually (the watch signal and this ADR are the reminder).

## More Information

Extends [ADR-042](042-release-automation.md) (release automation) and
[ADR-081](081-security-scanning.md) (Dependabot configuration). Decision informed by a divergent
research fan-out per `rules/research-parallelism.md` (release-engineering, alternative-tooling,
and dependency-mechanics lenses).
