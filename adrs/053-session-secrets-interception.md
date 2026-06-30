# ADR-053: In-Session Secrets Interception via PreToolUse Hook

**Status:** Accepted
**Date:** 2026-05-27

## Context and Problem Statement

`hooks/secrets-guard.sh` (ADR-047) blocks secrets at `git commit` time. It is the last gate before a secret can reach a remote, but it is also the *only* automated gate, and it fires late: between the moment an agent writes a key to a file (or echoes a token in a `Bash` command) and the moment of commit, the secret already exists on disk and in the session transcript. An agent can also surface a secret without ever committing it — `cat ~/.aws/credentials` pipes a live credential into the model context; `curl -H "Authorization: Bearer ghp_..."` exfiltrates one over the network. Neither touches `git commit`, so the pre-commit hook never sees them.

The sibling `a sibling repo` repo closes this gap with an always-on extension that intercepts `write`/`edit`/`bash` tool calls in-session (gap analysis, 2026-05-27; issue #183). The mechanism is a pi-runtime TypeScript extension, which does not exist on Claude Code or Copilot. The question is whether — and how — to port the in-session interception to this repo's two target platforms without a runtime extension API.

## Considered Options

* **Option A — `PreToolUse` hook on Bash + write-capable tools.** A new bash hook (`hooks/session-secrets-guard.sh`) registered as a `PreToolUse` hook in `settings.json` (Claude Code) and `.github/hooks/session-secrets-guard.json` (Copilot), modeled structurally on the existing `bash-destructive-guard.sh`. It scans `Bash`/`Write`/`Edit`/`MultiEdit`/`NotebookEdit` tool inputs and denies (exit 2) on a secret-surfacing action, reusing the layer-1 pattern set.
* **Option B — `PostToolUse` hook that scans after the write.** Fires after the tool runs; can warn but cannot prevent the write — the secret is already on disk by the time the hook sees it.
* **Option C — rely on the pre-commit hook alone.** No in-session layer; accept the on-disk/in-transcript exposure window.
* **Option D — port the pi extension's tool-registration model.** Not available: Claude Code and Copilot have no runtime extension API, and runtime-loaded tool servers are prohibited by `rules/no-mcp-servers.md`.

## Decision Outcome

Chosen option: **Option A.** `PreToolUse` is the only event that can *prevent* a write rather than react to it (ruling out B), and the exposure window the issue describes is real and cheap to close (ruling out C). Option D is foreclosed by platform capability and the no-MCP policy. A bash `PreToolUse` hook reuses the established cross-platform delivery pattern (`bash-destructive-guard.sh` + `.github/hooks/*.json`), works identically on Claude Code, VS Code Copilot, and Copilot CLI (whose one actionable output, `preToolUse` deny, is exactly what this hook needs), and requires no new runtime surface.

Key design decisions:

* **Coverage:** `Bash`/`execute`, `Write`/`create_file`, `Edit`/`replace_string_in_file`, `MultiEdit`, and `NotebookEdit`. The edit-family and notebook tools are included because each is an independent path to writing a secret to disk; omitting any of them leaves a bypass.
* **Only NEW content is scanned** (`content`, `new_string`, `new_source`, `edits[].new_string`) — never the replaced/old text — so an edit that *removes* a secret is never blocked.
* **Fail posture is split by threat model.** Write-capable tools fail **closed**: a parseable call to a known write tool whose target path cannot be extracted is denied, because a secrets guard must not be defeatable by a malformed payload. `Bash` with an empty command, unrecognized tools, and unparseable input fail **open** (exit 0), so the guard never bricks a session — this is the inverse of nothing-detected-means-allow used by `bash-destructive-guard.sh`, and the difference is deliberate.
* **Pattern set is duplicated, not shared.** `SECRET_PATTERNS` lives in `hooks/secrets-guard.sh`, `hooks/session-secrets-guard.sh`, and the upstream pi extension, coordinated by a "keep in lockstep" comment. A sourced `hooks/lib/secret-patterns.sh` was considered and rejected for now: sourcing a lib that mutates shell options clobbers the caller, the two consumers run in different execution contexts, and it adds a `hooks/` tree entry for a single shared string. Revisit if a third bash consumer appears (tracked by #192).
* **Overrides are shared with layer 1:** `SKIP_SECRETS_GUARD=1` (announced to stderr — never a silent bypass) and `.secrets-guard-allowlist`.

### Relationship to ADR-047

ADR-047 records layer 1 (pre-commit). This ADR adds layer 2 (in-session) as a complementary, earlier gate against the same material. The two share a pattern set and override mechanisms by design; they differ in trigger point (tool call vs commit) and in fail posture (the pre-commit hook scans staged files; the session hook gates individual tool calls and fails closed for unverifiable writes).

### Tradeoffs

* **Good:**
  * Closes the on-disk/in-transcript/exfiltration window that the commit-time gate cannot reach.
  * Reuses the proven cross-platform `PreToolUse` delivery path; no new runtime surface, no MCP, consistent with `rules/no-mcp-servers.md`.
  * Fires on every write-capable tool, not just `Bash`.
* **Bad:**
  * The pattern set now lives in three places; drift is a standing risk mitigated only by a lockstep comment until #192.
  * Per-call `jq`+`grep` cost on every Bash/Write/Edit/MultiEdit/NotebookEdit call (well under the 10 s hook timeout in practice).
  * Known accepted gaps: base64-encoded secrets, and secrets assembled at runtime via shell-variable expansion where the literal is absent from the command string. NUL bytes truncate the scanned sample.
  * The PEM regex uses the BSD-portable optional-group form `(...)?` rather than the empty-alternation form `(...|)`, which BSD grep rejects with "empty (sub)expression" (invalidating the whole pattern and failing the scan open on macOS); the two are semantically identical. Layer 1 (`hooks/secrets-guard.sh`) had the same latent fragility and was aligned to the portable form in the same change (#201), so both bash hooks now share the identical, portable pattern.

## More Information

* **Issue** — a tracking issue (#183) (Phase A of the sibling-repo port epic #181).
* **Prior art** — `a sibling repo` `agent/extensions/secrets-guard/` (the runtime-extension original this hook ports to a `PreToolUse` bash hook).
* **Cross-platform delivery** — `settings.json` (Claude Code) + `.github/hooks/session-secrets-guard.json` (Copilot); double-fire on VS Code is prevented by the `~/.claude/settings.json: false` opt-out in `.vscode/settings.json` (CONTRIBUTING.md § Dual-Format Workflow).
* **Output convention** — `rules/script-output-conventions.md` (`WARN` to stderr; exit 0/2).
* **Related** — ADR-047 (pre-commit layer), ADR-037 (cross-platform hook capability comparison), `rules/secrets-guard.md`, `rules/no-mcp-servers.md`. #192 may revisit factoring the shared pattern set.
