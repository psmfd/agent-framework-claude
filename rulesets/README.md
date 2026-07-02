# rulesets/

Committed desired state for the repository's GitHub branch-protection
rulesets (ADR-086). Each `<name>.json` is the normalized form of the live
ruleset named `<name>` — and doubles as the exact PUT body `scripts/rulesets.sh
--apply` sends.

## Normalization contract

Files are produced by `scripts/rulesets.sh --pull <name>`, never hand-authored
from scratch: `jq -S` key order, an explicit key allowlist (`name`, `target`,
`enforcement`, `conditions`, `bypass_actors`, `rules` — server-generated
fields are stripped), `rules` sorted by `type`, and `required_status_checks`
contexts sorted alphabetically. Hand edits are fine (that is the point —
reviewable diffs) but must preserve the normalized shape; when in doubt,
round-trip the file through the filter via `--pull` after applying.

## Workflow

```bash
scripts/rulesets.sh --check                 # live vs committed (skips offline)
scripts/rulesets.sh --apply protect-dev     # push committed state live (confirm-gated)
scripts/rulesets.sh --pull protect-dev      # adopt live state into the repo
```

`validate.sh check_ruleset_job_drift` independently cross-checks every
committed `required_status_checks` context against the workflow jobs'
effective check names — offline, on every pre-push and CI run.
