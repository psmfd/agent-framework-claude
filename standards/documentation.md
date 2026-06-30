# Documentation Standards

Conventions for Markdown documents in this repository. These standards apply to all `.md` files unless noted otherwise.

## General Markdown Formatting

### Heading Depth

- Maximum depth is `###` (H3) for most documents.
- `####` (H4) is permitted sparingly — only when a subsection genuinely needs a fourth level.
- `#####` (H5) and deeper are never used.

### Code Fences

Fenced code blocks must include a language tag:

````markdown
```bash
echo "tagged"
```
````

Never use bare fences without a language identifier. Use `text` for plain output with no syntax highlighting.

### Tables

- Use `|---|` separators (no alignment colons unless the column needs right-alignment).
- Prefer tables over bullet lists for structured data with consistent fields.

### Prohibited Content

- No badges or shields
- No table of contents in most documents (documents should be short enough not to need one). Exception: `README.md` must include a manually maintained TOC covering all H2 sections (see ADR-026)
- No diagrams or images in most documents (describe architecture in prose or tables). Exception: `README.md` may use Mermaid diagrams for workflow and architecture visualization (see ADR-025)
- No emojis
- No admonition/callout blocks (`> [!NOTE]`, `> [!WARNING]`, etc.)

### Tone

- Terse, declarative prose. State facts, not opinions.
- Imperative voice for instructions ("Run the script", not "You should run the script").
- Plain-English noun phrases for section headings ("Architecture", not "How the Architecture Works").

### Links

- Use relative paths for intra-repo links: `[CONTRIBUTING](../CONTRIBUTING.md)`.
- No absolute URLs for files within the repo.
- All relative links must resolve to real files (enforced by `validate.sh`).

## README Conventions

### When to Include a README

Every repository root must have a `README.md`. Subdirectory READMEs are not required — the root README should cover the repository structure.

### Required Sections

| Section | Content |
| --- | --- |
| H1 title | Repository or project name — one-line description immediately follows |
| Quick Start | Minimum steps to get running |

### Recommended Sections

Include these when applicable, in this order after Quick Start:

| Section | When to include |
| --- | --- |
| Purpose | When the repo's purpose is not obvious from the title and description |
| Prerequisites | When setup requires specific tools, versions, or access |
| Architecture | When the repo has non-trivial structure worth explaining |
| Configuration | When the project has configurable settings |
| Usage | When usage patterns go beyond Quick Start |
| Installation | When installation is more involved than Quick Start covers |
| Maintenance | When ongoing tasks (upgrades, backups, rotation) exist |
| Constraints | When important limitations or non-obvious boundaries exist |

### What to Omit

- **Contributing section** — use `CONTRIBUTING.md` instead.
- **License section** — use `LICENSE` file instead.
- **Authors/credits** — git history is authoritative.
- **Changelog** — use git tags or `CHANGELOG.md` instead.

## CLAUDE.md Conventions

### When to Include a CLAUDE.md

Include `CLAUDE.md` at the project root when project-specific AI assistant configuration exists that cannot be expressed in `AGENTS.md` or standard rule files. Not every project needs one.

### Structure

When present, `CLAUDE.md` should follow this structure:

| Section | Purpose |
| --- | --- |
| H1 title | `# Claude Code — Project Configuration` (or project-specific variant) |
| Project overview | What the project is and what it does — brief, not a repeat of README |
| Architecture | Key architectural decisions that affect how Claude should work with the code |
| Key commands | Build, test, lint, deploy commands Claude should know |
| Technology stack | Languages, frameworks, and versions (or reference to `standards/tooling.md`) |
| Constraints | Project-specific rules, boundaries, and things to avoid |

### Principles

- **Minimal by design.** CLAUDE.md supplements, not duplicates. If guidance belongs in a rule file, put it there. If it belongs in AGENTS.md, put it there.
- **Reference, don't repeat.** Point to AGENTS.md for behavioral conventions rather than restating them.
- **Session-start context.** CLAUDE.md is auto-loaded at session start. AGENTS.md is not. If Claude must know something at session start, CLAUDE.md is the right place — but keep it to pointers and configuration, not full convention text.
