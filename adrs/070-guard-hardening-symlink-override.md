# ADR-070: Worktree symlink containment and env-only identity override

**Status:** Accepted
**Date:** 2026-06-12

## Context and Problem Statement

A security review of the released guard hooks confirmed two gaps. First, `hooks/worktree-create.sh` filtered `..` segments and absolute paths in `.worktreeinclude` entries but followed symlinks: a repo-controlled symlink entry (or symlinked intermediate path component) caused `cp -r` to copy content from outside the repository into the worktree. Second, `hooks/session-gh-identity-guard.sh` parsed `GH_IDENTITY_OVERRIDE=<login>` from the command string itself — an agent-controlled value — so a prompt-injected command could self-certify the currently-active login and defeat the `.gh-expected-identity` pin, the strict layer of ADR-054's signal model.

## Considered Options

* **Option A** — Worktree: reject symlink entries and entries whose parent resolves (physically) outside the repo root; copy nested symlinks as links (`cp -R`). Identity: remove the command-string prefix form entirely; honor the environment variable only.
* **Option B** — Identity: keep the prefix form but accept only logins present in `.gh-expected-identity`.
* **Option C** — Status quo with documentation of both gaps.

## Decision Outcome

Chosen option: **Option A**. For the identity override, Option B provides no security improvement: an injected command could still self-certify as the *pinned* login, which is structurally the same bypass — defeating the pin is exactly what the pin exists to prevent. The environment variable is read from the hook's process environment, which only the user controls at session launch; the command-string prefix never reaches the hook's environment, so honoring it served only the attack path. For the worktree, physical resolution (`pwd -P`) of each entry's parent catches symlinked intermediate components, a top-level `-L` check catches symlink entries, and `cp -R` (verified identical on BSD/macOS and GNU coreutils) copies any nested symlink as an inert link instead of following it. The containment comparison uses parameter-expansion prefix-stripping with an explicit `/`-boundary test rather than a `case` glob, which would misbehave on repo paths containing pattern metacharacters.

The in-session deny message now directs override decisions to the user explicitly ("ask the user to…") rather than instructing the blocked agent to add an allowlist entry or set variables itself — wording that an instruction-following agent could previously have read as authorization to clear its own block.

### Accepted residuals

* A nested symlink inside a copied directory lands in the worktree as an inert pointer (no content is copied at copy time); a narrow TOCTOU race exists between the entry checks and the copy (requires concurrent write access to the repo). Both are documented in the hook header.
* `.gh-identity-allowlist` is agent-writable via `Write`/`Edit` tools, which this guard does not gate. The write is a visible artifact in the activity stream and does not affect the pre-push layer. Named in `rules/gh-identity-guard.md` Accepted gaps.
* The pre-push hook (`hooks/gh-identity-guard.sh`) is unchanged: there the env-var form (`GH_IDENTITY_OVERRIDE=<login> git push`) genuinely propagates from the user's shell to the hook process and remains the supported one-shot override for raw-shell pushes.

### Tradeoffs

* Good: the worktree copy-out path and the in-session pin-defeat path are closed; the override model is reduced to user-controlled channels; `tests/worktree-guard/run-tests.sh` pins the bypass cases as regressions.
* Bad: there is no agent-side one-shot identity override anymore — a blocked in-session mutation requires `gh auth switch`, a user-added allowlist entry, or a session restarted with the env var set.

## More Information

Supersedes the `.worktreeinclude` handling clause of [ADR-038](038-worktree-custom-path.md) (traversal filtering is now containment: symlink rejection + physical-root resolution) and the in-session override clause of [ADR-054](054-gh-identity-enforcement-layers.md) (`GH_IDENTITY_OVERRIDE` is env-only in the in-session layer); both ADRs otherwise stand and their bodies are unedited, following the partial-supersession pattern of ADR-068/ADR-069.
