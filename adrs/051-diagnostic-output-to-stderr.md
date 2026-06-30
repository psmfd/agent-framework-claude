# ADR-051: Diagnostic Output (WARN and ERROR) to stderr

**Status:** Accepted
**Date:** 2026-05-12

## Context and Problem Statement

ADR-034 codified the framework's script output conventions and specified that `ERROR` output goes to stderr while all other labels — including `WARN` — go to stdout. This decision did not consider a failure mode that surfaced in the WIM (Work-Item Management) script suite: scripts that use stdout as a return-value channel via command substitution (`result=$(child.sh ...)`) capture both the intended return value and any `WARN` lines emitted along the way. When the child emits a `WARN` before the return value, the captured variable contains the concatenated text, and downstream string interpolation (e.g., into a REST URL) fails.

Concretely: `scripts/wim/apply-manifest.sh` captures the issue number from `create-epic.sh` via command substitution. `gh_set_issue_type` in `_lib.sh` emits `WARN` on the GraphQL `issueTypes` fallback path — the universal case for user-owned repos and orgs without Issue Types configured. Every sub-issue parent-child link then failed with `net/url: invalid control character in URL` because the captured "parent number" contained the WARN line followed by the actual number. The script's summary block falsely reported `PASS — 0 errors, 0 warning(s)` because `WIM_WARN_COUNT` is bash-process-scoped and child increments never reach the parent. See issue #287.

This pattern — helper functions that return values via stdout while also emitting diagnostic output — is universal in Unix shell scripting. The framework will produce more such scripts over time. A convention that routes diagnostic output to stdout is incompatible with this pattern.

## Considered Options

* **Option A** — Local deviation: redirect `warn()`/`err()` to stderr in `scripts/wim/_lib.sh` only, document the deviation in a header comment, leave the framework-wide convention as ADR-034 specifies.
* **Option B** — Convention amendment: route `WARN` (and confirm `ERROR`) to stderr framework-wide. Diagnostic stream is stderr; stdout is the value channel.
* **Option C** — Call-site redirection: add `>&2` at every call site in the WIM scripts where a helper emits diagnostics that might pollute captured output. Helpers themselves unchanged.
* **Option D** — Side-channel return value: pass a temp file path to children via env var; children write their return value to the file; helpers continue emitting on stdout. Reserves stdout for diagnostics rather than return values.

## Decision Outcome

Chosen option: **Option B**, because:

1. **POSIX alignment.** POSIX.1-2017 §12.2 (Utility Conventions) requires: "Diagnostic messages shall be written to standard error." `WARN` is a diagnostic message — it signals a non-fatal anomaly the invoking process may need to act on. Routing it to stdout violates the spec.
2. **Reference-tool alignment.** Every major CLI tool the framework cites (`git`, `gh`, `docker`, every coreutil) routes warnings and errors to stderr while reserving stdout for machine-consumable return values. The framework's prior choice diverged from a universal convention without a documented benefit.
3. **Eliminates the root cause.** Path A and Path C are workarounds that leave the broken convention in place. Any future script that uses command substitution to capture a return value will hit the same bug. Path B fixes the bug for every present and future script in one change.
4. **Bounded blast radius.** Only three helper-function definitions need updating: `validate.sh`, `hooks/secrets-guard.sh`, `scripts/wim/_lib.sh`. No call site changes behavior; call sites continue to invoke `warn()` and `err()` the same way — only the stream changes.
5. **Path D rejected as over-engineered.** Side-channel return values are appropriate for binary or multi-line payloads but are friction for the common case of returning an integer ID. Stdout-as-value-channel is the natural shell idiom; the right move is to keep stdout clean, not to abandon it.

### Tradeoffs

* Good: aligns with POSIX, with every reference CLI tool, and with standard shell idioms for command substitution
* Good: command-substitution capture patterns become safe — no more accidental WARN pollution into captured values
* Good: the WIM bug (#287) is fixed without per-script deviations
* Good: forward-compatible — future helpers that use stdout as a return channel will not need exceptions
* Bad: existing `scripts/wim/*.sh` are SHA-pinned per ADR-050 — `scripts/wim/.frozen-shas` must be updated in the same change set
* Bad: any CI or external consumer that parses `WARN` lines via stdout will need to switch to `2>&1` capture (mitigation: every framework CI invocation already uses `2>&1 | tee` or `2>&1`)
* Bad: ADR-034 must be superseded rather than amended

## More Information

* Issue: #287 — fix(wim): apply-manifest.sh sub-issue linking fails — child WARN output pollutes captured issue number
* Supersedes: ADR-034 (Standardized Script Output Conventions)
* Related: ADR-050 (Frozen Work-Item Scripts with SHA-Pin Enforcement) — frozen-SHA repin is part of this change set
* External: POSIX.1-2017 §12.2 Utility Description Defaults; `git` and `gh` CLI man pages exemplify the diagnostic-to-stderr pattern

### Doc-sync cascade applied

| File | Edit |
|---|---|
| `rules/script-output-conventions.md` | Convention statement + helper block |
| `copilot/instructions/script-output-conventions.instructions.md` | Mirror |
| `web/instructions.md` | Skill Catalog row + helper block (distillate) |
| `validate.sh` | `warn()` body adds `>&2` |
| `hooks/secrets-guard.sh` | `warn()` body adds `>&2` |
| `scripts/wim/_lib.sh` | `warn()` and `err()` bodies add `>&2`; child-counter file append |
| `scripts/wim/apply-manifest.sh` | `WIM_COUNTS_FILE` setup + child-counter aggregation before summary |
| `scripts/wim/.frozen-shas` | Recompute SHA-256 for `_lib.sh` and `apply-manifest.sh` |
| `adrs/034-script-output-conventions.md` | Status line: `Superseded by ADR-051` |
