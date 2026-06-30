---
description: 'Use Conventional Commits format for all commit messages'
---

# Conventional Commits

All commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) format.

## Format

```text
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | Use when |
| --- | --- |
| `feat` | Adding a new feature (skill, agent, rule, script) |
| `fix` | Fixing a bug or incorrect behavior |
| `perf` | Performance improvement with no functional behavior change |
| `docs` | Documentation-only changes (README, CONTRIBUTING, agent body content) |
| `chore` | Maintenance tasks (dependency updates, CI config, validate.sh tweaks) |
| `refactor` | Restructuring without changing behavior |
| `test` | Adding or updating tests or validation checks |
| `ci` | CI/CD pipeline changes |
| `style` | Formatting, whitespace, or linting fixes with no logic change |

## Constraints

- **Type is required.** Every commit message must start with a valid type.
- **Scope is optional** but recommended. Use the skill name, rule name, or affected area (e.g., `feat(linter):`, `fix(validate):`).
- **Description is imperative, lowercase, no period.** Write "add shell-expert agent" not "Added shell-expert agent."
- **No authorship attributions** in commit messages — no "Co-authored-by" or "authored by AI" trailers.
- **Body** is optional. Use it for context on non-obvious changes.
- **Breaking changes** use `!` after the type/scope: `feat(validate)!: require disable-model-invocation in agents`.

## Reserving `feat` (keeps MINOR bumps meaningful)

The type drives the SemVer bump (`feat` → MINOR, `fix`/`perf` → PATCH; see `semver-tagging.md`), so type discipline controls version inflation:

- **`feat`** is for genuinely new capability — a new skill, agent, rule, hook, script, or a new behavior a user can observe for the first time.
- A change that adjusts, corrects, or enriches the **output or wording of an existing feature** is a **`fix`** (it was inadequate) or a **`refactor`**/`chore` — not a `feat`. Example: a release workflow already publishes a GitHub Release and you enrich its notes — that is `fix`, not `feat`.
- When unsure between `feat` and `fix` for a tweak to existing behavior, prefer `fix`. Reserve the MINOR bump for additions that genuinely expand what the project does.
