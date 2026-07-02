---
description: 'Fail-closed guard against pushing or mutating GitHub from the wrong account on multi-account hosts'
---

# GitHub Identity Guard

**Enforcement:** PreToolUse hook session-gh-identity-guard.sh; pre-push hook gh-identity-guard.sh; validate.sh check_gh_identity (warn-only preflight)

On a host authenticated to more than one GitHub account, `gh` acts as the globally-active account and never auto-selects one from a repository's remote. When the active account is wrong for the target repo, a `git push` or mutating `gh` call is attributed to — or fails against — the wrong account. This is a real, recurring incident class on multi-account developer hosts, where the active account can silently drift between (or within) sessions to an account that is not the repo's owner.

Two fail-closed layers share one signal model and one set of overrides. They complement the warn-only `validate.sh` preflight from ADR-052 (which stays as an early-development signal) by *blocking* the operation.

* **Layer 1 — in-session (`hooks/session-gh-identity-guard.sh`):** a `PreToolUse` hook that denies an agent `Bash`/`execute` call performing a mutating `gh`/`git push` op while the identity is wrong. A cheap string pre-check runs first, so only mutating ops incur the identity probe.
* **Layer 2 — git pre-push (`hooks/gh-identity-guard.sh`):** a git-native pre-push hook that closes the raw-shell vector (plain terminal, IDE git client, scripts) the in-session hook cannot see. Installed by `setup.sh` into `.git/hooks/pre-push` ahead of `validate.sh`.

See ADR-054 (this guard) and ADR-052 (the preflight it extends).

## Signal model (hybrid)

1. **Pinned login** — if `<repo>/.gh-expected-identity` exists, the active login (`gh api user --jq .login`) must be one of its entries (one login per line; `#` comments and blanks ignored). This catches a wrong-but-also-authorized account, which an accessibility check alone would miss.
2. **Accessibility fallback** — when no pin file exists, the active account must be able to reach the target repo (`gh api repos/OWNER/REPO`). Consistent with ADR-052; requires no per-repo config.

`.gh-expected-identity` is **local-only per-developer config** — it is gitignored, never committed, so no account name lands in this shared framework. Copy `.gh-expected-identity.example` to `.gh-expected-identity` and add your login to activate the strict layer; without it, the guard uses the accessibility fallback (ADR-060).

## What it blocks

* **`git push`** to a github.com remote (any form, including `--force` and `git -C dir push`).
* **Mutating `gh <noun> <verb>`** — `issue`/`pr`/`release`/`repo`/`label`/`secret`/`variable`/`workflow`/`run`/`cache`/`gist`/`ruleset` create/edit/delete/merge/rerun/cancel/etc.
* **`gh api`** with a mutating method (`-X`/`--method POST|PATCH|PUT|DELETE`), or an implicit-POST body flag (`--input`/`-f`/`--raw-field`/`-F`/`--field`) supplied with no explicit method — `gh api` defaults to POST when a body field is present.

Read-only `gh`/`git` (e.g. `gh pr list`, `git status`, `gh api` GET) are never gated.

## Fail posture

Fail **closed**: an indeterminate identity (gh missing, `jq` missing, probe error, network failure, inaccessible remote) blocks the operation. A false block costs one `gh auth switch` or an override; a false allow is a wrong-account push, which is hard to reverse. The in-session hook only probes on a detected mutating op, so ordinary tool calls are never affected. The in-session hook parses the tool call with `jq`, so an absent `jq` is denied rather than silently disabling the guard; the `SKIP_GH_IDENTITY_GUARD` bypass still works without `jq` (#212, ADR-057).

## Scope

github.com remotes only (exact host match). Pushes/mutations against Azure DevOps, GitLab, Bitbucket, and self-hosted hosts pass through silently. Under `GH_TOKEN`/`GITHUB_TOKEN` (CI/bot), the guard verifies repo access under the token rather than comparing logins.

## Override mechanisms

Use the lowest-blast-radius override that fits. Every override announces itself (never silent).

| Override | Scope | Visibility |
| --- | --- | --- |
| `GH_IDENTITY_OVERRIDE=<login>` | One operation | Env var only — the in-session layer deliberately does not honor a command-string prefix (an agent-controlled string could self-certify a login; ADR-070). Names the expected login explicitly; validated against the gh username regex |
| `.gh-identity-allowlist` (repo root) | Persistent, per command-substring | Local-only (gitignored); per-developer (in-session layer) |
| `SKIP_GH_IDENTITY_GUARD=1` | One-shot, this guard only | Visible in shell history |
| `git push --no-verify` | One-shot, all pre-push hooks | Sledgehammer; document in the PR |

## When this rule applies

* The framework repo, where `setup.sh` installs the pre-push hook and `settings.json` wires the in-session hook.
* Any repo that opts in by installing the hooks and (optionally) committing `.gh-expected-identity`.

## When this rule does not apply

* Single-account hosts (the guard still runs but rarely fires).
* Non-github.com remotes.
* CI under a scoped token, where access is verified instead of login identity.

## Accepted gaps

Shell aliases, env-var-constructed command strings, and `curl` calls carrying a `gh auth token` are not detected by the in-session string classifier. An agent with `Write`/`Edit` tool access can pre-write a `.gh-identity-allowlist` entry to bypass the in-session layer — the guard gates `Bash`/`execute` only; the write is a visible artifact in the activity stream and does not affect the pre-push layer. The pre-push hook is the backstop for all `git push` vectors regardless of how they are invoked.

## Related

* ADR-054 — design record for the two-layer fail-closed guard (supersedes ADR-052)
* ADR-052 — the original warn-only preflight (superseded)
* `docs/multi-account-git-identity.md` — the three-layer identity model
* `rules/script-output-conventions.md` — output format the hooks follow
* `hooks/session-gh-identity-guard.sh`, `hooks/gh-identity-guard.sh` — the implementations
