# Multi-Account GitHub Identity

Guidance for hosts that authenticate to more than one GitHub account. Three independent identity layers must agree for a given repository; no single layer is sufficient on its own, and they can diverge silently. `gh` authenticates as the globally-active account and never auto-selects an account from a repository's remote owner — so a mismatch surfaces as `Could not resolve to a Repository` and other access errors rather than an obvious "wrong account" message.

This is workstation configuration performed once per machine. `setup.sh` does not configure any identity layer — it only links framework agents, rules, and hooks into `~/.claude/` and installs the git hooks. Identity must be configured separately, before cloning repositories owned by a non-default account.

## Layers

### Commit identity

`user.name` and `user.email` are written into every commit object and cannot be corrected after a push without rewriting history. Route them per repository with conditional includes in `~/.gitconfig` rather than a single global value.

```ini
# ~/.gitconfig
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work

[includeIf "hasconfig:remote.*.url:https://github.com/work-org/**"]
    path = ~/.gitconfig-work
```

```ini
# ~/.gitconfig-work
[user]
    name = Your Name
    email = you@work.example
```

The trailing slash on a `gitdir:` path matters — `gitdir:~/work/` matches the directory and everything beneath it. Prefer `hasconfig:remote.*.url:` when repositories are not segregated by directory tree; it requires git 2.36 or later.

### Transport credential

The credential that authenticates a push or fetch is separate from the commit identity. Which mechanism applies depends on the remote URL scheme.

For HTTPS remotes, this repository's `~/.gitconfig` delegates the credential to `gh auth git-credential`, which couples the push credential to the currently active `gh` account. Only one account is active at a time, so HTTPS pushes follow `gh auth switch`.

For SSH remotes, host aliases in `~/.ssh/config` select the key deterministically per remote URL, independent of the active `gh` account.

```text
# ~/.ssh/config
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
```

The matching remote URL uses the alias in place of the hostname: `git@github-work:work-org/repo.git`. `IdentitiesOnly yes` stops the SSH agent from offering other loaded keys, which would otherwise authenticate as the first account that matches any key.

### gh CLI active account

`gh` stores one token per host and marks one account active. Switch it explicitly:

```text
gh auth switch --user <account>
```

There is no native per-repository binding — `gh` does not read the git remote owner to choose an account. On multi-account hosts you switch manually, or script the switch on directory change.

## Per-repo verification

| Layer | Mechanism | Verify from inside the repo |
| --- | --- | --- |
| Commit identity | `~/.gitconfig` `includeIf` | `git config user.email` |
| Transport (HTTPS) | active `gh` account | `gh auth status` |
| Transport (SSH) | `~/.ssh/config` host alias + remote URL | `git remote -v`; `ssh -T git@github-work` |
| gh CLI account | `gh auth switch` | `gh api user --jq .login` |

## Tooling guard

Three guard surfaces, in increasing order of enforcement:

- **Layer 0 — early warning (ADR-052).** The work-item suite (`scripts/wim/apply-manifest.sh`) preflights repository accessibility before any writes and fails fast with an actionable `ERROR [gh-identity]` naming the `gh auth switch` command to run. `validate.sh` performs the same accessibility check as a non-fatal `WARN [gh-identity]` for the `origin` remote (skipped when `GH_TOKEN`/`GITHUB_TOKEN` is set, so CI stays quiet).
- **Layer 1 — in-session, fail-closed (ADR-054).** `hooks/session-gh-identity-guard.sh` is a `PreToolUse` hook that *denies* an agent `Bash` call performing a mutating `gh`/`git push` op while the active identity is wrong. A cheap string pre-check fires the probe only on a mutating op, so read-only `gh`/`git` is never gated.
- **Layer 2 — git pre-push, fail-closed (ADR-054).** `hooks/gh-identity-guard.sh` is a git-native pre-push hook (installed by `setup.sh` ahead of `validate.sh`) that blocks any `git push` to a github.com remote from the wrong account — covering plain terminals, IDE git clients, and scripts the in-session hook cannot see.

Layers 1–2 use a hybrid signal: a local-only (gitignored) `<repo>/.gh-expected-identity` pin (strict login match against `gh api user --jq .login`) when present — each developer creates their own from `.gh-expected-identity.example` — else repo accessibility. They are github.com-only and fail closed on an indeterminate identity. Overrides (all announced): `GH_IDENTITY_OVERRIDE=<login>` (one op; env var only — the in-session layer does not honor a command-string prefix, ADR-070), `.gh-identity-allowlist` (per command-substring), `SKIP_GH_IDENTITY_GUARD=1` (session-wide), `git push --no-verify` (all pre-push hooks). See `rules/gh-identity-guard.md`, ADR-052 (superseded), ADR-054, and ADR-070.
