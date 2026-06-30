# ADR-047: Pre-Commit Guard for Unencrypted Vault Files and Secrets

**Status:** Superseded by [ADR-059](059-secrets-guard-staged-blob-scan.md)
**Date:** 2026-04-30

## Context and Problem Statement

A real incident in an internal service repo had `ansible/inventory/production/group_vars/all/vault.yml` decrypted locally for editing while the committed version was properly encrypted. Only human vigilance prevented the plaintext file being staged and committed. The framework has no automated guard against this class of mistake. The same gap covers other secrets — PEM private keys, AWS access key IDs, GitHub personal access tokens, plaintext `.env` files. Once a secret reaches a remote, rotation is the only remediation; prevention at commit time is significantly cheaper than detection after push.

## Considered Options

* **Option A** — New thin pre-commit hook in `hooks/`, installed via `setup.sh` into the framework repo's own `.git/hooks/`. Header-based vault detection, regex-based secret pattern detection, opt-out via env var and allowlist file.
* **Option B** — Adopt `gitleaks` as the primary detection mechanism via `.pre-commit-config.yaml`. Adds a Python toolchain (`pre-commit` framework) and a Go binary as runtime dependencies on every contributor machine.
* **Option C** — Adopt `git-secrets` (awslabs). Stale upstream — last release 2020, no commits since 2021.
* **Option D** — Server-side gate only (GitHub Actions secret scanning, Azure DevOps equivalent). Detection happens after the secret reaches the remote; rotation rather than amend becomes the remediation path.

## Decision Outcome

Chosen option: **Option A**, because it stays consistent with the framework's existing "zero runtime dependencies beyond bash and jq" philosophy and the established pattern of distributing thin shell scripts via `setup.sh` (see `hooks/bash-destructive-guard.sh`, `hooks/stop-preflight-check.sh`). Option B introduces a Python toolchain on every contributor's machine and a separate configuration surface (`.pre-commit-config.yaml`) — a non-trivial expansion of the framework's surface and an opt-in tool many contributors do not already run. Option C is a non-starter on liveliness grounds (`git-secrets` is effectively abandoned per the framework's liveliness-evaluation rule). Option D does not prevent commits — it detects secrets that already reached the remote, requiring rotation rather than amend; it is complementary to a local hook and is filed as a separate follow-up issue, not a substitute.

The hook detects:

* Vault-named files (`**/vault*.yml`, `**/vault*.yaml`, `**/host_vars/*/vault*`, `**/group_vars/*/vault*`) whose first line does not match `^\$ANSIBLE_VAULT;[0-9]+\.[0-9]+;[A-Z0-9]+` (covers vault format 1.1 and 1.2 with vault IDs)
* PEM-style private keys (RSA, EC, OPENSSH, DSA, generic)
* AWS access key IDs with `AKIA`, `ASIA`, `ABIA`, and `ACCA` prefixes followed by 16 alphanumerics
* GitHub personal access tokens (`ghp_*`, `github_pat_*`)
* SSH private key file paths and `*.pem` / `*.key` files

Skip patterns: `*.example`, `*.sample`, `*.template`, `*.j2`, paths under `molecule/`, `tests/`, `spec/`. Override mechanisms in increasing blast radius: `SKIP_SECRETS_GUARD=1` env var (one-shot, audit-visible), `.secrets-guard-allowlist` file at the repo root (auditable, version-controlled), and `git commit --no-verify` (emergency, disables all hooks). The hook does NOT detect inline `!vault |` scalars in partially-encrypted files — that gap requires semantic YAML parsing and is documented as out-of-scope.

This PR ships the hook, the rule that mandates it, and this ADR. **Distribution to target repos is scoped to a separate follow-up issue** because the existing `setup.sh` only installs git hooks into the framework's own `.git/hooks/`. As a result, the framework repo itself is the only consumer of this hook until the target-repo installer ships.

### Tradeoffs

* Good: prevents accidental secret commits at the smallest reversible unit (pre-commit), before the secret enters object storage or reflog
* Good: zero new runtime dependencies; consistent with existing hook distribution model
* Good: header-based vault detection has zero false positives; regex-based secret detection is tunable via the allowlist file
* Good: override mechanisms are auditable — env-var bypass shows in shell history, allowlist entries show in PR review
* Bad: pre-commit hooks are bypassable via `git commit --no-verify` — must be paired with a server-side gate to fully close the loop (separate follow-up issue)
* Bad: inline `!vault |` partial-encryption gap is not addressed; semantic YAML parsing required to close it
* Bad: hook only runs in the framework repo until the target-repo installer ships

## More Information

* Issue #100 — original feature request
* Follow-up issue (TBD) — `setup.sh` target-repo hook installer
* Follow-up issue (TBD) — server-side secret scanning gate (GitHub Actions, Azure DevOps)
* Related: `rules/script-output-conventions.md` — output format the hook follows
* Related: `rules/secrets-guard.md` — the rule that mandates the hook
