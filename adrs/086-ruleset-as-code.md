# ADR-086: Ruleset-as-code with an offline required-check drift gate

**Status:** Accepted
**Date:** 2026-07-02

## Context and Problem Statement

The two branch-protection rulesets (`protect-dev`, `protect-main`, ADR-079)
existed only as live GitHub state plus ADR prose — UI edits had no PR, no
diff, no review trail. The drift this invites had already happened: at the
time of this decision the live `protect-dev` required 8 status checks while
ADR-079's text documented 4. Worse, required checks match workflow jobs by
display-name string, so renaming a job's `name:` field silently creates a
never-reporting required context that blocks every merge to the branch until
someone edits the ruleset out-of-band — the highest-impact stuck-pipeline
risk found in the batch-1 CI review (#15). Separately, GitHub's permission
model splits the problem: ruleset reads need only the implicit
`Metadata: read` (CI-feasible), but writes need `Administration: write`,
which is categorically outside `GITHUB_TOKEN`'s grantable permission set.

## Considered Options

* **Option A** — committed normalized JSON + a bespoke `gh api` script
  (local apply, graceful-skip live check) + a fully offline job-name
  cross-check in `validate.sh`
* **Option B** — Terraform/OpenTofu `github_repository_ruleset`
* **Option C** — an existing `gh` extension (katiem0/gh-migrate-rulesets et al.)
* **Option D** — status quo (ADR prose + live state)

## Decision Outcome

Chosen option: **Option A**.

* `rulesets/<name>.json` is the committed desired state, produced by a single
  jq normalization (explicit five-key allowlist — unknown server fields are
  excluded fail-closed; `rules` sorted by type; `required_status_checks`
  contexts sorted alphabetically; `jq -S` key order). The normalized shape is
  byte-identical to the PUT body — one format for diffing and applying.
* `scripts/rulesets.sh` (bash 3.2-safe): `--check` diffs live vs committed
  and SKIPs cleanly without gh/network/auth (it is a convenience, never a
  gate); `--apply` PUTs/POSTs with a default-deny confirm prompt and
  `--dry-run`, and is local-maintainer-only by architecture (writes are
  impossible for `GITHUB_TOKEN`); `--pull` seeds/resyncs from live.
* `validate.sh check_ruleset_job_drift` is the load-bearing gate: fully
  offline and jq-free, it cross-checks committed contexts against the
  effective status-check names of workflow jobs (the `name:` field, falling
  back to the job id — the matching key was verified against the live
  codeql job, whose id `analyze` differs from its required context `codeql`).
  A context matching no job is an ERROR caught at pre-push/CI time — before
  the rename ever reaches live state. Intentionally-unrequired jobs
  (`release`, `check-merge-method`) are allowlisted so the inverse WARN only
  fires on new unrequired jobs.
* Option B was rejected as a state-management footprint mismatch for a
  bash-only repo with two rulesets; Option C's candidates target
  migration/reporting, not idempotent apply+drift, and trend
  maintenance-only. A future optional CI job invoking
  `scripts/rulesets.sh --check` on a schedule is feasible (reads are
  Metadata-level) and deliberately deferred.

### Tradeoffs

* Good: ruleset changes become PR-reviewable diffs; the job-rename
  merge-bricking failure is caught offline before it exists; the observed
  ADR-079-vs-live drift class ends structurally.
* Bad: an intentional UI edit now requires a follow-up `--pull` commit (or
  it surfaces as `--check` drift); the explicit key allowlist must be
  extended by hand if GitHub adds a PUT-accepted field; the awk job-name
  extractor assumes this repo's consistent two-space workflow indentation.

## More Information

Issue #15; ADR-079 (the protected state itself — its check list is now
superseded by `rulesets/*.json` as the current-state record), ADR-083
(mechanical-gate pattern this extends), ADR-084 (Enforcement-line
convention); #28 (catalog-gate coverage, sibling extractor hardening).
