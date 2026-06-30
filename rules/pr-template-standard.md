---
description: 'Require standardized PR template sections across all ecosystem repositories'
---

# PR Template Standard

Every repository in the ecosystem must have a `.github/PULL_REQUEST_TEMPLATE.md` with a consistent section structure. Individual repositories customize the checklist items, but the section layout is standardized.

## Required Sections

Every PR template must include these four sections.

### Summary

Free-text description of what the PR does and why. The "why" is mandatory; the "what" is covered by the diff. Target 2-4 sentences.

### Type of Change

A checklist matching Conventional Commits types. Exactly one should be checked:

```markdown
- [ ] `feat` — new feature
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `chore` — maintenance
- [ ] `refactor` — restructuring without behavior change
- [ ] `test` — adding or updating tests
- [ ] `ci` — CI/CD changes
- [ ] `style` — formatting or linting fixes
- [ ] Breaking change (add `!` to PR title)
```

### Test Plan

What the author did to verify the change works. This section must not be deleted even for trivial changes. Valid entries include:

- Specific tests run and their results
- `validate.sh` output (for this repo)
- Endpoint tests with curl examples (for API projects)
- "No testable behavior changed" (for documentation or config changes)

### Checklist

Repo-specific items covering security, credentials, cross-platform parity, and other project concerns. Each repository defines its own checklist items appropriate to its domain.

## Optional Sections

Include when applicable. Delete when not.

- **API Changes** — for projects exposing HTTP or library APIs. Include endpoint or signature changes, backward compatibility statement, and migration notes.
- **Database / Schema Changes** — migration script reference, rollback procedure, data impact statement.
- **Screenshots / Recordings** — required for any change that alters visual output or interactive behavior.
- **Dependencies** — for changes that add, remove, or upgrade dependencies. Include package name, version change, reason, and license check for new additions.

## PR Title

The PR title must be a valid Conventional Commits message: `<type>(<scope>): <description>`. In a squash-merge workflow, the PR title becomes the only commit message on the integration branch.

## PR Lifecycle

- PRs are optional for solo developers with no CI/CD gates.
- PRs are required once CI/CD status checks or team members are added.
- Draft PRs are permitted for work-in-progress. Do not request review until the PR is ready.

## When This Rule Does Not Apply

- Repositories outside the ecosystem that have their own PR conventions.
- Trivial single-commit changes where the PR description field is sufficient (no template needed for the PR itself, but the template must still exist in the repo).
