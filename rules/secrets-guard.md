---
description: 'Mandate a pre-commit guard against unencrypted Ansible vault files and common secret patterns'
---

# Secrets Guard

Secrets are guarded in two layers that share one pattern set and one set of overrides. **Layer 1 (pre-commit):** `setup.sh` installs `hooks/secrets-guard.sh` as the framework repo's `pre-commit` hook, blocking commits containing unencrypted Ansible vault files, PEM private keys, AWS access key IDs, GitHub personal access tokens, and SSH private key file paths. **Layer 2 (in-session):** `hooks/session-secrets-guard.sh` is a `PreToolUse` hook that denies the same material the moment an agent tries to surface it — before it ever reaches disk. Pre-commit prevention is significantly cheaper than post-push detection (once a secret reaches a remote, rotation is the only remediation); in-session prevention is cheaper still, since it stops a secret from being written or echoed at all.

## What the hook blocks

The hook iterates `git diff --cached --name-only --diff-filter=ACMR` (renames included so a file renamed into a sensitive name is scanned), skips binary files (detected via `git diff --numstat`), and caps each content scan at 512 KB. All content reads — both the vault-header check and the secret-pattern scan — read the **staged blob** via `git show ":<path>"`, never the working-tree file, so editing or removing a file after `git add` cannot hide a secret already in the index (ADR-059, supersedes ADR-047). It then applies these checks:

* **Vault-naming pattern + missing header** — files matching `**/vault*.yml`, `**/vault*.yaml`, `**/host_vars/*/vault*`, `**/group_vars/*/vault*` whose first line does not match `^\$ANSIBLE_VAULT;[0-9]+\.[0-9]+;[A-Z0-9]+` (covers vault format 1.1 and 1.2 with vault IDs)
* **PEM private-key headers** — `-----BEGIN (RSA |EC |OPENSSH |DSA |PGP |ENCRYPTED )?PRIVATE KEY` (optional-group form; BSD grep rejects the empty-alternation variant — see ADR-053 and #201). The `ENCRYPTED ` alternative covers PKCS#8 encrypted keys (the `ENCRYPTED PRIVATE KEY` header form, RFC 5958) emitted by `openssl pkcs8 -topk8` and modern tooling.
* **AWS access key IDs** — `AKIA|ASIA|ABIA|ACCA` followed by 16 uppercase alphanumerics
* **GitHub tokens** — `gh[oprsu]_[A-Za-z0-9]{36,}` (covers all five documented prefixes: `ghp_` classic PAT, `gho_` OAuth, `ghu_` user-to-server, `ghs_` server-to-server / Actions `GITHUB_TOKEN`, `ghr_` refresh) and `github_pat_[A-Za-z0-9_]{82,}` (fine-grained PAT). The body bound is open-ended because GitHub treats tokens as opaque and is rolling out a longer `ghs_` format (~520 chars) — a fixed length would silently miss new tokens (#211, ADR-057)
* **Sensitive file paths** — file basenames `id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519` (plus explicit `.pem` variants) and `id_ecdsa_sk`, `id_ed25519_sk` (FIDO2 hardware-backed keys, OpenSSH 8.2+; their `.pem` forms are caught by the `*.pem` glob below); also any `*.pem` or `*.key` file

The hook does NOT detect inline `!vault |` scalars in partially-encrypted YAML files — that gap requires semantic YAML parsing and is out of scope for this hook.

## In-session interception (PreToolUse layer)

`hooks/session-secrets-guard.sh` fires as a `PreToolUse` hook wired via `settings.json` (matcher `^(Bash|Write|Edit|MultiEdit|NotebookEdit)$`). It denies, before execution:

* **Bash / execute** — an inline secret literal in the command (same pattern set as layer 1), or a read of a sensitive credential file (`~/.aws/credentials`, `~/.aws/config`, `~/.ssh/id_*`, `~/.kube/config`, `~/.netrc`, `~/.pgpass`, `~/.docker/config.json`).
* **Write / create_file** — a write to a sensitive path (`id_rsa`, `*.pem`, `*.key`), a vault-named file whose content lacks the `$ANSIBLE_VAULT` header, or content matching a secret pattern.
* **Edit / MultiEdit / NotebookEdit** — NEW content (`new_string` / `new_source`) matching a secret pattern. Replaced/old text is never scanned, so an edit that REMOVES a secret is never blocked.

It honors the same skip patterns and `.secrets-guard-allowlist` as layer 1 (plus `fixtures/`). Write-capable tools fail **closed** when the target path cannot be extracted from a parseable call (a secrets guard must not be defeatable by a malformed payload); `Bash` with an empty command and unrecognized tools fail **open**. The hook also fails **closed on a missing `jq`** — it parses tool input with `jq`, so an absent `jq` is treated as an indeterminate state and denied (exit 2) rather than silently disabling the layer; the `SKIP_SECRETS_GUARD` bypass still works without `jq` (#212, ADR-057). The pattern set is duplicated across the two bash hooks (and the upstream pi extension) with a lockstep comment rather than a shared source — see ADR-053. Known accepted gaps: base64-encoded secrets, and secrets assembled at runtime via shell-variable expansion where the literal is absent from the command string.

## Override mechanisms

Use the lowest-blast-radius override that fits the situation:

| Override | Scope | Visibility |
| --- | --- | --- |
| `SKIP_SECRETS_GUARD=1 git commit ...` | One-shot | Visible in shell history; auditable |
| `.secrets-guard-allowlist` at repo root | Persistent (per-path glob) | Version-controlled; visible in PR review |
| `git commit --no-verify` | One-shot, all hooks | Should be reserved for emergencies and documented in the commit body |

The allowlist file accepts one path glob per line. Lines starting with `#` and blank lines are ignored. Use it for known false positives such as `tests/fixtures/fake_key.pem` — never to suppress a real finding.

## Skip patterns (the hook does not scan)

* Files matching `*.example`, `*.sample`, `*.template`, `*.j2`
* Paths under `molecule/`, `tests/`, `spec/`
* Binary files (detected via `git diff --numstat`)
* Files staged for deletion (excluded by `--diff-filter=ACM`)

## When this rule applies

* The framework repo itself, where `setup.sh` installs the hook on the local `.git/hooks/pre-commit`
* Any repo that opts in by symlinking or copying `hooks/secrets-guard.sh` into its `.git/hooks/pre-commit`

## When this rule does not apply

* Repos that have not opted in
* Trivial single-line fixes that do not touch potentially-secret files
* Server-side gates that complement (rather than replace) this hook — those are tracked separately

## Related

* ADR-059 — staged-blob scanning (supersedes ADR-047); `tests/secrets-guard/run-tests.sh` is its regression suite
* ADR-047 — original design record for the pre-commit hook (superseded by ADR-059)
* ADR-053 — design record for the in-session `PreToolUse` layer
* `rules/script-output-conventions.md` — output format the hooks follow
* `hooks/secrets-guard.sh` — the pre-commit (layer 1) implementation
* `hooks/session-secrets-guard.sh` — the in-session (layer 2) implementation
