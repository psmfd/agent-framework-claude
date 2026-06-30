# ADR-069: Execution-tool allowlist for agent wrappers

**Status:** Accepted
**Date:** 2026-06-12

## Context and Problem Statement

The Minimal Tool Lists policy (AGENTS.md, CONTRIBUTING.md, PR template, web distillate) stated that read-only expert agents should not have `Bash` (Claude) / `execute` (Copilot), while [ADR-021](021-agent-tiering-taxonomy.md) — authored the same day — recorded the Domain Specialist tool boundary as including `Bash` and called it intentional. The two surfaces were never reconciled: 16 of 17 Claude expert wrappers carried `Bash`, while the Copilot side granted `execute` to only two experts. A security review confirmed the risk is real: a read-only expert with `Bash` that reviews untrusted content has an open prompt-injection path to data exfiltration (e.g. `curl` with runtime shell expansion), which the in-session guard hooks explicitly cannot detect, and `Bash` is all-or-nothing per agent — there is no per-agent command allowlist mechanism in either platform's wrapper format.

## Considered Options

* **Option A** — Strip by default; keep `Bash`/`execute` only where a documented execution workflow exists; enforce via static allowlist arrays in `validate.sh`.
* **Option B** — Keep `Bash` but require a structured `bash-justification:` frontmatter field per wrapper, validated by `validate.sh`.
* **Option C** — Status quo plus documentation (update policy text to match ADR-021).

## Decision Outcome

Chosen option: **Option A**, because it aligns tool grants with demonstrated need, closes the exfiltration surface for the agents most exposed to untrusted content, and is mechanically enforceable. Option B fails cross-platform: Copilot wrapper frontmatter supports only defined fields, so a justification field cannot be mirrored, and self-certified in-file justifications are weaker than a framework-controlled list that requires a deliberate, reviewable `validate.sh` edit. Option C leaves the highest-risk agents (those routinely fed untrusted content to review) holding an unneeded execution capability.

`Bash` was removed from 11 Claude wrappers (`ai-crossplatform-expert`, `ansible-expert`, `azure-devops-expert`, `azure-infra-expert`, `code-review-expert`, `docker-expert`, `docs-expert`, `dotnet-expert`, `helm-expert`, `tauri-expert`, `vcluster-expert`); none documents an execution workflow — the grant was a tier-level default from ADR-021. The `dotnet-expert` wrapper's verify step dropped its `dotnet --help` channel (official docs and web search remain).

### Permitted agents and justifications

| Agent | Platform grant | Documented execution workflow |
| --- | --- | --- |
| `gh-cli-expert` | Bash + execute | SKILL.md mandates running `gh <command> <subcommand> --help` before composing non-trivial flags; `gh auth status` preflight |
| `work-item-management-expert` | Bash + execute | SKILL.md documents live taxonomy discovery (`gh label list`, `gh issue list`, `gh project field-list`, `az boards query`); invokes the frozen `scripts/wim/` suite |
| `gitflow-expert` | Bash only | Wrapper workflow mandates reading live git state (`git log`, `git branch -a`, `git remote -v`, `git tag -l`) before recommending |
| `checkmarx-expert` | Bash only | Wrapper workflow mandates a `command -v cx` preflight before CLI guidance |
| `shell-expert` | Bash only | SKILL.md CLI Exploration Strategy prescribes running `tool --help` as a research step |
| `kitty-agent` | Bash + execute | Execution Provider tier — validates configuration by running kitty |
| `linter` | Bash + execute | Execution Provider tier — runs shellcheck, markdownlint, yamllint |

The Claude-only grants for `gitflow-expert`, `checkmarx-expert`, and `shell-expert` are an accepted platform asymmetry: Claude Code subagents run headless and must inspect live state themselves, while Copilot operates with IDE context, its wrappers never carried `execute`, and Copilot CLI restricts subagent networking (ADR-037). `execute` is added to a Copilot wrapper only when a concrete workflow gap is demonstrated.

### Enforcement

`validate.sh` defines `CLAUDE_BASH_ALLOWED` and `COPILOT_EXECUTE_ALLOWED` arrays alongside its other policy constants and errors when a wrapper carries `Bash`/`execute` without an entry. Adding an agent that meets the existing criteria is a routine addition: one PR that edits the allowlist, cites the documented workflow in its description, and references this ADR — no new ADR needed. Changing the qualifying criteria themselves (what counts as a documented execution workflow) requires a superseding ADR.

### Tradeoffs

* Good: the prompt-injection-to-exfiltration path is closed for the 11 agents most likely to review untrusted content; tool grants now match documented behavior; violations fail CI and the pre-push hook.
* Bad: the five retained `Bash` grants keep the documented residual risk for those agents (accepted: their inputs are predominantly CLI meta-output or local state, not arbitrary reviewed content); stripped agents that later need live verification must come back through a PR and allowlist edit.

## More Information

Supersedes the Domain Specialist tool-boundary clause of [ADR-021](021-agent-tiering-taxonomy.md) (`Bash` is no longer a tier-level default; ADR-021's tiering taxonomy otherwise stands). Related: predecessor ADR-037 (Copilot capability limits — not carried into this Claude-only fork), [ADR-053](053-session-secrets-interception.md) (the in-session guard whose documented shell-expansion gap motivates stripping rather than guarding). Follows the partial-supersession pattern of ADR-068: the prior ADR's body is not edited.
