# ADR-093: Install the Claude Code CLI via the Native Installer in setup.sh

**Status:** Accepted
**Date:** 2026-07-03

## Context and Problem Statement

`setup.sh` symlinks the framework into `~/.claude/` but assumes the `claude`
binary already exists; on a clean machine setup completes yet nothing consumes
the distribution (#48). Installing the CLI means fetching and executing a remote
installer — a materially bigger, security-relevant action than symlinking local
files, and one that must be reconciled with the repo's strict stance against
remote-loaded content (`rules/no-mcp-servers.md`, ADR-046). A three-agent
research fan-out (platform truth, supply-chain security, shell integration)
informed this decision.

## Considered Options

* **Option A** — Native installer, **download-then-execute** (`curl -fsSL … -o`
  then `bash <file>`) from a pinned `claude.ai` domain; one cross-platform path
  for macOS and Linux.
* **Option B** — Platform-native signed channels: apt DEB822 + GPG-fingerprint
  verify on Debian, Homebrew cask on macOS; native installer only as fallback.
* **Option C** — `npm install -g @anthropic-ai/claude-code`.
* **Option D** — Status quo: assume the CLI is pre-installed.

## Decision Outcome

Chosen option: **Option A**, for one simple cross-platform install path, gated by
the supply-chain invariants that make fetch-and-execute acceptable here:

1. **Different threat class than no-mcp-servers.** A one-time, user-initiated,
   first-party install of the trust root the framework already depends on is not
   the runtime, session-scoped, external-context-injection threat that
   `no-mcp-servers.md` / ADR-046 target. This ADR records the feature as a
   deliberate, **scoped exception** — not a precedent for any other remote-fetch
   mechanism.
2. **Supply-chain invariants the implementation holds.** Pinned, literal,
   non-overridable source (`https://claude.ai/install.sh`); **download-then-
   execute, never a streamed `curl | bash` pipe** (avoids partial-download /
   partial-execute and yields an inspectable artifact); **fail-safe abort** on
   download or installer failure with manual-install instructions (never fall
   through to executing failed/unverified code); **explicit consent distinct
   from `--non-interactive`** (interactive prompt, or `CLAUDE_CLI_INSTALL=1` for
   automation); `--dry-run` never fetches or executes; pinned channel (`stable`).
3. **Native over B and C for this footprint.** Option B has stronger native
   verification (apt/Homebrew signatures) and aligns with `debian-baseline.md`,
   but adds per-platform machinery (keyring + GPG fingerprint + `sudo` on Debian,
   a Homebrew dependency on macOS) for a single-maintainer, two-platform target;
   the maintainer chose the single native path for simplicity. Option C (npm) is
   discouraged by Anthropic's own docs (load-bearing postinstall, `sudo`
   warning, larger dependency surface) for no benefit over the native binary.
4. **No hosted bootstrap one-liner.** A `curl | bash` bootstrap that clones and
   runs setup is the same fetch-and-execute shape the repo distrusts; the
   shareable floor stays the documented `git clone` + `./setup.sh` sequence.

The step always returns 0 so a failure never aborts the rest of setup; an install
failure is reported `ERROR` and reflected in the summary. Idempotent: `SKIP`/`OK`
when `claude` is already present. bash-3.2-safe.

### Tradeoffs

* Good: a clean machine reaches a working `claude` in one consented step; no new
  per-platform machinery; strong fetch-execute hygiene; setup stays bash-3.2-safe
  and re-runnable.
* Bad: weaker artifact verification than Option B's signed channels — which
  remains the documented future enhancement if the platform footprint or security
  bar grows. Anthropic's `install.sh` bootstrap itself carries **no detached
  signature** (only the resulting manifest/binaries do), so verification coverage
  is asymmetric — accepted for v1. Native installs self-update by default
  (`DISABLE_AUTOUPDATER=1` is available but not set by setup).

## More Information

* #48 (this feature); the three-agent research (platform-truth install commands,
  supply-chain posture, shell integration)
* ADR-046 / `rules/no-mcp-servers.md` (the policy reconciled), `debian-baseline.md`
  (Option B alignment noted)
* Install location: `~/.local/bin/claude`. Verification/pinning available upstream
  (GPG-signed `manifest.json`, `bash -s <version>`) is the path an Option-B
  hardening would adopt.
