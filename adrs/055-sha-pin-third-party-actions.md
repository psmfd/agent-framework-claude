# ADR-055: SHA-Pin Third-Party GitHub Actions

**Status:** Accepted
**Date:** 2026-05-28

## Context and Problem Statement

The repo's CI workflows reference GitHub Actions by floating major-version tag (`actions/checkout@v6`, `amannn/action-semantic-pull-request@v6`). A Git tag is mutable: a maintainer (or an attacker who compromises a maintainer's account) can move or re-point a tag, so `@v6` resolves to whatever commit the tag names at run time, not the commit that was reviewed. For a repo whose own purpose is supply-chain hygiene — the no-MCP policy (ADR-046), frozen wim scripts SHA-pinned in `.frozen-shas` (ADR-050) — leaving a third-party action resolvable by mutable tag is the weakest link in the CI trust chain. This surfaced during the 2026-05-28 currency review (#208) alongside the Node-20 runner deprecation that forced an action-version bump.

GitHub's own hardening guidance states that pinning an action to a full-length commit SHA is currently the only way to use it as an immutable release. The tension: SHA pins are immutable but opaque (a bare 40-hex string hides which version it is) and do not auto-update, so they trade run-time mutability risk for a manual-maintenance cost.

## Considered Options

* **Option A — SHA-pin third-party actions; floating major tags for GitHub-owned (`actions/*`) actions** — pin `amannn/...` and any future non-`actions/*` action to a full commit SHA with a trailing `# vX.Y.Z` comment; keep `actions/checkout` / `actions/setup-node` on `@vN`.
* **Option B — SHA-pin every action, including GitHub-owned** — maximal immutability, maximal maintenance.
* **Option C — Status quo: floating major tags for all** — simplest, no maintenance, accepts tag-mutability risk on third-party code.

## Decision Outcome

Chosen option: **Option A**, because the supply-chain risk is concentrated in third-party actions while the maintenance cost of SHA pins scales with how many you pin. A compromised `amannn/action-semantic-pull-request` runs in the `pull_request_target` context of `lint-pr-title.yml` (base-branch context, repo secret access) — the highest-blast-radius action in the repo — so pinning it to an immutable SHA closes the most dangerous vector. GitHub-owned `actions/*` are first-party to the platform that already hosts and runs the workflow; pinning them to SHA adds churn (Dependabot/manual bumps across every workflow on every patch) without a proportional risk reduction, since trusting `@v6` of `actions/checkout` is trusting the same party that runs the action. Option B pays that churn everywhere; Option C leaves the one genuinely-third-party, secret-exposed action mutable.

Every SHA pin carries a trailing `# vX.Y.Z` comment and a note to bump the SHA and comment together, so the opaque-string downside is mitigated and version intent stays visible in the diff.

### Tradeoffs

* Good: the highest-risk action (third-party, `pull_request_target`, secret access) is immutable and cannot be silently re-pointed.
* Good: version intent stays legible via the `# vX.Y.Z` comment; upgrades are an explicit, reviewable SHA change.
* Good: scope is bounded — only non-`actions/*` actions carry the pin, so maintenance cost stays small.
* Bad: SHA pins do not auto-update; a security patch to `amannn/...` requires a manual SHA bump (no Dependabot is configured yet — a future follow-up).
* Bad: the policy is a convention, not enforced by `validate.sh`; a new third-party action added with a floating tag would not be caught automatically.

## More Information

* **Implementation** — `.github/workflows/lint-pr-title.yml` pins `amannn/action-semantic-pull-request` to `48f256284bd46cdaab1048c3721360e808335d50` (tag `v6.1.1`). `actions/checkout` and `actions/setup-node` remain on `@v6`.
* **Originating work** — #208 (GitHub Actions v6 bump driven by the Node-20 runner deprecation), filed from the 2026-05-28 currency review.
* **Related** — ADR-050 (frozen wim scripts, SHA-pin enforcement via `.frozen-shas`); ADR-046 (no-MCP / supply-chain threat model); [GitHub Actions security hardening — using third-party actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions).
* **Possible follow-up** — configure Dependabot for GitHub Actions to automate SHA bumps with version-comment updates, or add a `validate.sh` check that flags floating-tag third-party actions.
