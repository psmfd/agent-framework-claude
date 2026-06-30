# ADR-059: Secrets Guard Scans the Staged Blob, Not the Working-Tree File

**Status:** Accepted
**Date:** 2026-05-29

## Context and Problem Statement

ADR-047 added `hooks/secrets-guard.sh` as a pre-commit hook to block secrets entering the git object store at commit time. Its stated scope is "staged files," but the implementation read the **working-tree file**: the vault-header check used `head -n 1 "$REPO_ROOT/$path"` and the content scan used `head -c 524288 "$REPO_ROOT/$path"`. The working-tree copy and the staged blob can differ — and it is the staged blob that gets committed.

This makes the guard bypassable (issue #176). An author can `git add` a file containing a secret, then edit the working-tree copy to remove the secret (or prepend a valid `$ANSIBLE_VAULT` header to a vault file), then `git commit`: the hook reads the now-clean working-tree copy, passes, and the staged blob — still carrying the secret — is committed. The same divergence arises from partial staging (`git add -p`) and from staging a file then deleting it from the working tree (the two `[[ ! -f ]]` working-tree-existence guards skipped such a file entirely). The bypass is not remotely exploitable — it needs local interactive access between `git add` and `git commit` — but the hook's entire purpose is to be a reliable last line of defence before secrets reach the object store, and the server-side gate noted in ADR-047 remains unshipped. The implementation's behaviour did not match the decision's intent, so the guarantee the hook offered was weaker than ADR-047 implied.

## Considered Options

* **Option A** — Scan the staged blob directly: `git show ":<path>"` for both the content scan and the vault-header check; replace the working-tree-existence guards with a staged-blob-existence check (`git cat-file -e ":<path>"`).
* **Option B** — Keep the working-tree read but add a pre-check that rejects the commit when the staged blob and the working-tree file differ for a scanned path.
* **Option C** — Accept the bypass as a documented known gap and rely on the (unshipped) server-side gate.

## Decision Outcome

Chosen option: **Option A.** Scanning `git show ":<path>"` reads exactly the bytes that will be written to the tree object on commit — there is no transformation between the index entry and the committed blob — so it closes the bypass for the content scan, the vault-header check, partial staging, and the staged-then-deleted case, with no added complexity. Option B is rejected: a compare-then-scan step introduces a TOCTOU window and extra code paths while still reading the wrong source of truth. Option C is rejected: the bypass is trivially reachable (`git add secret && rm secret && git commit`) and silently defeats the guard.

Because this changes the hook's observable guarantee — before the fix it silently passed the bypass; after the fix it blocks — rather than merely correcting documented detail, it supersedes ADR-047 (per `rules/adr-required.md`: supersession-not-editing when a prior decision's behaviour is revised). ADR-047's Status becomes `Superseded by [ADR-059]`; its body is frozen.

Specific changes to `hooks/secrets-guard.sh`:

* Content scan reads `git show ":<path>" | head -c 524288 | grep -qE -- "$SECRET_PATTERNS"`.
* Vault-header check reads `git show ":<path>" | head -n 1`.
* The two `[[ ! -f "$REPO_ROOT/$path" ]]` working-tree-existence guards become `git cat-file -e ":<path>"` (staged-blob existence), closing the staged-then-deleted bypass. The now-dead `full_path` assignment is removed; `REPO_ROOT` is retained (allowlist path).
* The file-list diff filter is widened `ACM` → `ACMR` so a file renamed into a vault/sensitive name with a secret-bearing body is scanned (git emits only the destination path for `R`; the scan logic is unchanged).
* `is_binary()` already used `git diff --cached --numstat` (staged-aware) and is unchanged. The `SECRET_PATTERNS` / `VAULT_HEADER_RE` / `is_sensitive_path()` definitions are unchanged, so the ADR-053 pattern lockstep with `hooks/session-secrets-guard.sh` is unaffected.

A regression test (`tests/secrets-guard/run-tests.sh`) builds throwaway repos and asserts the corrected hook blocks all four bypass vectors (stage-then-clean, stage-then-delete, vault-header swap, rename-into-vault) and passes a clean staged file. The same fixtures were confirmed to pass (exit 0) against the pre-fix hook, demonstrating the divergence.

### Tradeoffs

* Good: the hook now scans what is actually committed; the documented stage-then-clean, partial-staging, and staged-then-deleted bypasses are closed.
* Good: `ACMR` closes the rename-into-vault gap at the cost of one diff-filter character.
* Good: the in-session layer (`hooks/session-secrets-guard.sh`) is untouched — it scans tool-call content in memory and has no staged-vs-working-tree concept.
* Bad / residual (accepted, carried from ADR-047): secrets past the 512 KB scan cap are still missed; inline `!vault |` partial-encryption is not detected; base64-encoded secrets are not detected; a symlink staged under a vault name resolves to its target string, not the target's content; `git commit --no-verify` bypasses all hooks. These require a server-side scanning gate to fully close.

## More Information

* Supersedes [ADR-047](047-secrets-vault-precommit-guard.md). Pattern lockstep is governed by [ADR-053](053-session-secrets-interception.md) and is unaffected by this change.
* Issue: #176 (staged-blob scan). Raised from the v2.1.0 pre-promotion solution review (finding #2).
* Test: `tests/secrets-guard/run-tests.sh`.
