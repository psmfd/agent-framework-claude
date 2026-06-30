# ADR-050: Frozen Work-Item Scripts with SHA-Pin Enforcement

**Status:** Accepted
**Date:** 2026-05-06

## Context and Problem Statement

The `work-item-management-expert` skill is read-only by default — it outputs `gh` / `az` / REST commands for the user to run rather than executing them. This posture protects against drift (friendly names instead of reference names, wrong link-type `rel` values, missing `AcceptanceCriteria` on stories, process-template-incorrect effort fields), but only if it is actually load-bearing. As long as the skill emits ad-hoc CLI commands per task, an agent can rationalize "I'll just run this one" or emit subtly wrong commands the user pastes without scrutiny.

A frozen-script convention collapses the write surface: all work-item creation routes through a small set of pre-vetted, parameterized scripts under `scripts/wim/`, and the agent's role is reduced to authoring a `manifest.json` and invoking the driver. The scripts are reviewed once at authoring time and never edited afterward — that's what turns the read-only posture into a structural guarantee instead of a policy promise.

## Considered Options

* **Option A — Frozen scripts under `scripts/wim/` + SHA-pin in `validate.sh`** — codify the contract as five frozen Bash files (`_lib.sh`, three `create-*.sh`, `apply-manifest.sh`) plus a manifest schema. SHA-256 hashes pinned in `scripts/wim/.frozen-shas`. `validate.sh check_frozen_scripts` fails on drift.
* **Option B — Skill-level guidance only** — keep the skill output-commands behavior; add SKILL.md and wrapper text saying "use the project's wim scripts if present." No structural enforcement.
* **Option C — Pre-commit hook on `scripts/wim/`** — block edits to the directory at commit time. Bypassable with `--no-verify`; depends on hook installation per developer.

## Decision Outcome

Chosen option: **Option A**, because it is the only one of the three that survives an instruction-following agent. Option B leaves the agent free to emit ad-hoc commands or generate replacement scripts, defeating the rationale for frozen scripts. Option C catches edits at commit time but is per-developer and bypassable; SHA-pin enforcement in `validate.sh` runs on every push (pre-push hook installed by `setup.sh`) and in CI on every PR, so drift is caught at the integration boundary regardless of local hook state.

The behavioral half lives in `skills/work-item-management-expert/SKILL.md` and both wrappers (`agents/work-item-management-expert.md`, `copilot/agents/work-item-management-expert.agent.md`): a `## Frozen Work-Item Scripts` section enumerates the prohibited actions (edit, regenerate, replace, extend, delete) with no emergency or urgency exception, the only escape hatch being "stop and surface the gap to the orchestrator." The constraint text was reviewed by `code-review-expert` for loophole-free phrasing per the agent-behavioral-fix composition rule (`rules/research-parallelism.md`).

### Tradeoffs

* **Good:**
  * Read-only posture is structurally enforced — the agent literally has no path to mutate the live tracker except via the frozen driver.
  * Five files reviewed once and pinned. A drift attempt fails `validate.sh` and is visible in the diff.
  * Manifest schema is the contract surface — humans curate it; agents read and edit it. Schema drift is caught by `manifest.schema.json` validation at the driver level.
  * Both backends (Azure DevOps Boards, GitHub Issues + Projects v2) share the same manifest schema; backend selection is one field. Cross-platform parity is built in.
  * Idempotency is built into each create script (search-by-title before create), so partial-failure recovery is automatic.

* **Bad:**
  * Adding new fields requires re-authoring the affected create script. This is the cost the convention pays for the guarantee — and a forcing function against scope creep at the script surface.
  * Process-template branching (Agile = StoryPoints, Scrum = Effort, CMMI = Size) lives in the lib's `ado_effort_field` helper. If a fourth process appears, the lib changes. This is the right place for the branching, but it is a forcing function for a re-authoring cycle.
  * `gh issue create` does not yet emit `--json` output, so the GitHub branch makes a follow-up `gh issue view` call to capture the issue node ID for sub-issue and project mutations. One extra round-trip per item.
  * The constraint applies only when `scripts/wim/` exists at the project root. Projects without the suite fall back to the existing read-only-by-default behavior — there is no global enforcement.

## More Information

* **Behavioral half** — `skills/work-item-management-expert/SKILL.md` `## Frozen Work-Item Scripts`, `## Script Workflow` sections; mirrored in `agents/work-item-management-expert.md` and `copilot/agents/work-item-management-expert.agent.md`.
* **Constraint text review** — drafted and tightened with `code-review-expert` per `rules/research-parallelism.md` agent-behavioral-fix composition. Loopholes closed: no "normality" qualifier, no agent-evaluated gap condition, no purpose-qualified prohibition framing, path is fixed at `scripts/wim/`.
* **Output convention** — scripts follow `rules/script-output-conventions.md` (OK/SKIP/WARN/INFO/ERROR labels, exit codes 0/1/2, summary block). ADR-034 records the originating convention.
* **Adjacent enforcement** — `validate.sh check_frozen_scripts` mirrors the SHA-pin pattern used by other tooling and runs alongside the existing pre-push gate (ADR-015).
* **Tests** — `tests/wim/run-tests.sh` exercises both backends end-to-end with `az` / `gh` shims. 22 assertions cover the golden path, idempotent re-run, parent linking, `AcceptanceCriteria` HTML conversion (ADO), process-template effort-field branching, sub-issue linking (GitHub), full-tree `apply-manifest.sh`, and usage / manifest error paths.
* **Tracking issue** — a tracking issue (#256).
