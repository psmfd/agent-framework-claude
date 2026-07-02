---
description: 'Use SemVer release tags aligned with Conventional Commits version bumps'
---

# SemVer Tagging

**Enforcement:** CI release.yml (semantic-release on main pushes); self-report only (manual annotated-tag discipline)

All repositories in the ecosystem use Semantic Versioning for release tags, with version bumps derived from Conventional Commits types.

## Tag Format

All version tags use a `v` prefix: `v1.2.3`, not `1.2.3`.

**Manually-cut tags MUST be annotated** (`git tag -a`). **Automated release tags are lightweight by design**: `semantic-release` (via `@semantic-release/github`) creates the tag through the GitHub Releases API, which produces a lightweight tag. This is the expected, accepted behavior for the automated path — do not convert automation-created tags to annotated. The annotated-tag requirement governs the manual path only (e.g. a pre-automation or out-of-band tag). See [ADR-066](../adrs/066-tag-annotation-policy.md).

```bash
# Manual path only — annotated:
git tag -a v1.2.3 -m "v1.2.3"
git push origin v1.2.3
```

Tags are cut from `main` only, after `dev` has been promoted. Never tag `dev` directly.

Use `git push origin <tagname>` explicitly. Do not use `git push --tags` as it pushes all tags including any lightweight tags created by other tools.

## Version Bump Mapping

| Conventional Commits signal | Version bump | Example |
| --- | --- | --- |
| `BREAKING CHANGE:` footer or `!` after type | MAJOR (`X.0.0`) | `feat!: rename agent API` |
| `feat` type | MINOR (`x.Y.0`) | `feat(linter): add yaml support` |
| `fix`, `perf` types | PATCH (`x.y.Z`) | `fix(hooks): allow cat writes` |
| `docs`, `chore`, `style`, `refactor`, `test`, `ci` | No bump | No release unless bundled with a `fix` or `feat` |

## Pre-1.0 Versioning

Projects start at `v0.1.0`. While the major version is `0`:

- Breaking changes bump MINOR, not MAJOR (`v0.1.0` -> `v0.2.0`). This follows SemVer spec section 4.
- Features bump MINOR as usual.
- Fixes bump PATCH as usual.

Graduate to `v1.0.0` by deliberate decision when the public API is declared stable. This is not an automatic version bump. Document the graduation criteria in the project's ADR.

## Release Process

Release automation is handled by `semantic-release` running on pushes to `main` (see `.github/workflows/release.yml` and ADR-042).

1. Ensure `dev` is clean and all PRs for the release are merged.
2. Open a PR from `dev` to `main`. Use **Create a merge commit** — not squash merge. Merge commits preserve squash commit SHAs from `dev`, which `semantic-release` reads to derive the version bump.
3. After merge, `semantic-release` runs automatically: analyzes Conventional Commits since the last tag, determines the version bump, creates a lightweight `v`-prefixed tag (via the GitHub Releases API), and publishes a GitHub Release with generated changelog.
4. Do not merge `main` back to `dev`. `dev` is already ahead.

## Container Image Tagging

When a project produces container images:

- **Stable:** `vX.Y.Z` (immutable, exact version), `latest` (points to most recent stable tag on `main`)
- **Pre-release/dev:** `dev-<short-sha>` (e.g., `dev-bf04391`). Never tagged `latest`.
- Do not tag images with branch names directly (e.g., no `image:dev`). Branch-named tags are ambiguous about content.

## CI Validation

PR validation (`validate.sh`) and PR title linting (Conventional Commits enforcement) run as GitHub Actions on PRs targeting `dev`. See `.github/workflows/validate.yml` and `.github/workflows/lint-pr-title.yml`.
