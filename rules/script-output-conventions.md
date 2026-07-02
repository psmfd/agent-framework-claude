---
description: 'Standardize output format, exit codes, and summary blocks for all scripts produced by the agent framework'
---

# Script Output Conventions

**Enforcement:** validate.sh check_lib_selftests (scripts/lib conformance only); self-report only (per-script adoption)

All shell scripts produced, suggested, or designed by the agent framework must follow these output conventions. This is the default standard — target project conventions take precedence when they exist.

## Output Labels

Scripts that report check results, test outcomes, or operational status must use these fixed-width labels. The label column is 6 characters wide, left-aligned, followed by a space.

| Label | Format | Use |
|---|---|---|
| `OK` | `OK    [name] message` | Check or test passed |
| `SKIP` | `SKIP  [name] message` | Precondition not met, gracefully skipped |
| `WARN` | `WARN  [name] message` | Non-fatal issue, does not affect exit code |
| `INFO` | `INFO  message` | Informational output, no bracket label |
| `ERROR` | `ERROR [name] message` | Fatal issue, increments error counter |

### Label Rules

- **Bracket labels** (`[name]`) identify the specific check or test. Use them with `OK`, `SKIP`, `WARN`, and `ERROR`. Omit them for `INFO`.
- **Names** are short, lowercase, hyphenated identifiers (e.g., `[api-dedup]`, `[frontmatter]`).
- `WARN` and `ERROR` output goes to stderr (diagnostic stream). `OK`, `SKIP`, `INFO`, and `detail` output go to stdout. This aligns with POSIX.1-2017 §12.2 and the convention used by `git`, `gh`, `docker`, and other reference tools, and keeps stdout safe to capture as a return channel via command substitution. See [ADR-051](../adrs/051-diagnostic-output-to-stderr.md).
- Verbose or debug detail uses an indented format: 6 spaces followed by the detail text. Only print when verbose mode is active (`VERBOSE=1`, or a script-specific `--verbose` flag).

## Output Helpers

Framework-internal scripts source the shared helpers from [`scripts/lib/log.sh`](../scripts/lib/log.sh) (ADR-061) rather than redefining them:

```bash
# resolve scripts/lib/ relative to the script's own location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"   # adjust the relative depth per caller
```

`log.sh` provides `ok`, `skip`, `warn`, `info`, `err`, `detail`, plus `fatal` (err then exit) and `print_summary`. It owns `LOG_ERROR_COUNT`/`LOG_WARN_COUNT` (incremented by `warn`/`err`), is bash-3.2 safe, and never sets shell options (the caller owns them). `scripts/lib/git.sh` provides `git_repo_root`. Each module exposes a `--self-test` mode that `validate.sh` runs as a gate.

Scripts that cannot source the lib — those installed standalone outside the repo tree (e.g. git hooks in `.git/hooks/`, per ADR-053/ADR-054) or frozen and SHA-pinned (`scripts/wim/*.sh`, ADR-050) — define the helpers inline, with a comment citing the constraint:

```bash
ok()    { printf 'OK    [%s] %s\n' "$1" "$2"; }
skip()  { printf 'SKIP  [%s] %s\n' "$1" "$2"; }
warn()  { printf 'WARN  [%s] %s\n' "$1" "$2" >&2; }
info()  { printf 'INFO  %s\n' "$*"; }
err()   { printf 'ERROR [%s] %s\n' "$1" "$2" >&2; }
detail(){ [ "${VERBOSE:-0}" = "1" ] && printf '      %s\n' "$*"; }
```

Counter increments in inline definitions use the `((counter++)) || true` pattern to prevent `set -e` abort when incrementing from zero.

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | All checks passed (warnings are informational only) |
| `1` | One or more errors found |
| `2` | Environment or precondition failure (missing env vars, missing dependencies) |

## Summary Block

Scripts that run multiple checks or tests must end with a summary block:

```text
==================================
PASS — 0 errors, 2 warnings
```

or

```text
==================================
FAIL — 3 errors, 1 warning
```

The summary line uses `PASS` when `error_count` is zero and `FAIL` otherwise. Include both error and warning counts. Exit with code 1 on `FAIL`, code 0 on `PASS`.

## Script Header

All scripts must include:

```bash
set -euo pipefail
```

And a comment block documenting usage and exit codes, following the pattern established by `validate.sh` and `hooks/secrets-guard.sh`.

## When This Rule Applies

- Any shell script created, suggested, or designed by agents in the framework
- Test scripts, validation scripts, operational scripts, and utility scripts
- Scripts generated for other repositories (as the default when no project convention exists)

## When This Rule Does Not Apply

- Scripts in target projects that have their own established output conventions
- One-liner or trivial scripts where structured output adds no value
- Scripts that produce machine-readable output only (JSON, CSV) with no human-facing status
