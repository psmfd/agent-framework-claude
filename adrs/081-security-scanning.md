# ADR-081: Security scanning for the public repository

**Status:** Accepted
**Date:** 2026-06-30

## Context and Problem Statement

This repository is public ([ADR-076](076-claude-only-successor-genesis.md),
[ADR-080](080-genericize-private-identifiers-for-public-release.md)). Its existing
security stack is strong for its content type — `gitleaks` ([ADR-078](078-ci-security-gitleaks.md)),
`shellcheck` on hooks/lib, the pre-commit and in-session secrets/identity guards,
and the per-agent execution-tool allowlists ([ADR-069](069-execution-tool-allowlist.md)).
Two gaps remained: no CI layer validates **GitHub Actions** security semantics
(template injection, dangerous triggers, excessive permissions, action pinning),
and there is no Dependabot (a follow-up [ADR-055](055-sha-pin-third-party-actions.md)
explicitly deferred) nor a `SECURITY.md`. A divergent research fan-out (three
agents: a security-review lens, an AI-agent-scanner survey, and a conventional-SAST
survey) converged on a clear high-ROI set.

## Considered Options

* **zizmor + CodeQL (actions) + Dependabot + SECURITY.md** — close the Actions and
  supply-chain gaps with first-party / well-audited tools, free on public repos.
* **Add Semgrep / Trivy / TruffleHog as well** — broader, but the research found
  high overlap (Semgrep vs shellcheck/zizmor), no matching content (Trivy: no
  IaC/containers; also a 2026 `trivy-action` supply-chain incident), and gitleaks
  already sufficient (TruffleHog).
* **Adopt a dedicated AI-agent-config scanner now** (e.g. Aguara, SkillSpector) —
  the category is immature (mid-2026), targets skill-marketplace threat models, and
  none validate Claude agent frontmatter permission semantics.
* **Do nothing** — leaves the Actions attack surface unscanned.

## Decision Outcome

Chosen option: **zizmor + CodeQL (actions) + Dependabot + SECURITY.md**, plus
scoping `merge-method-check.yml` permissions to the job. `zizmor` and `codeql`
upload SARIF to the Security tab and become **required status checks on
`protect-dev`** once they run green. `lint-pr-title.yml`'s documented-safe
`pull_request_target` is suppressed via `.github/zizmor.yml` rather than weakening
the audit globally. Trivy, Semgrep, and TruffleHog are **not** adopted (overlap /
no matching content). Dedicated **agent-config scanning is deferred** — the
framework's own guardrails (ADR-069 allowlists, the secrets/identity/destructive
guards, the no-MCP policy) cover the material risks better than the immature
tooling; revisit when those tools have production maturity and Claude-frontmatter
support.

### Tradeoffs

* Good: the GitHub Actions attack surface — the repo's primary executable surface —
  is now statically analyzed by two complementary engines; supply-chain drift is
  visible via Dependabot; a public disclosure path exists.
* Good: all additions are free on a public repo and SHA-pinned ([ADR-055](055-sha-pin-third-party-actions.md)).
* Bad: more CI jobs and third-party actions to keep current — mitigated by Dependabot
  bumping their pins.
* Bad: no dedicated agent-config scanning yet — accepted; the framework's own static
  enforcement (ADR-069) exceeds what the current tools offer.

## More Information

Builds on [ADR-055](055-sha-pin-third-party-actions.md) (SHA-pinning),
[ADR-069](069-execution-tool-allowlist.md) (tool allowlists),
[ADR-078](078-ci-security-gitleaks.md) (gitleaks). The research was a divergent
fan-out per `rules/research-parallelism.md`. Aguara (`garagon/aguara`) is the
tracked re-evaluation candidate for agent-config scanning (~2027).
