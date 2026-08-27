# ADR-100: Semantic Codebase Search as a Skill over the cocoindex-code CLI

**Status:** Accepted
**Date:** 2026-08-27

## Context and Problem Statement

This repository's retrievable substance is majority prose: 82 ADRs, 22 rules,
and 31 monolithic agent files carrying their expertise inline, against 44 shell
scripts. Grep and Glob answer literal-string questions well and conceptual ones
badly — "which ADR decided the duplication-over-sourcing convention" requires
knowing the phrase the ADR used. The Pi ecosystem solved the same problem with
a `search_codebase` tool over the `cocoindex-code` (`ccc`) engine (pi_config
ADR-0033), and `ccc` is already installed on this host with an index built for
this repo. The open question is the vehicle, because `cocoindex-code` also
ships an MCP server (`ccc mcp`) that this repo's standing policy prohibits
(ADR-002, `rules/no-mcp-servers.md`).

## Considered Options

* **Option A** — Skill (`skills/codesearch/SKILL.md` + bundled
  `scripts/code-search.sh`) shelling out to the `ccc` CLI.
* **Option B** — Native tool via the engine's own MCP server (`ccc mcp`).
* **Option C** — Custom agent (`agents/*.md` with `tools: Bash`) wrapping the
  CLI, invoked through the Agent tool.
* **Option D** — Port the Pi `indexing` extension to Claude Code.
* **Option E** — Status quo: rely on Grep, Glob, and the Explore agent.

## Decision Outcome

Chosen option: **Option A**, because it is the only shape that delivers
semantic retrieval inside the policy boundary, and the boundary here is not
negotiable at the vehicle level:

1. **Option B is rejected, not deferred.** A native tool — a callable entry
   with a JSON input schema in the model's tool list — has exactly one
   registration path in Claude Code: an MCP server. Plugin components are
   skills, agents, hooks, MCP servers, LSP servers, and monitors; none of the
   others registers a tool. So "wrap it as a tool" is identical to "run an MCP
   server", which ADR-002 and `rules/no-mcp-servers.md` prohibit and
   `validate.sh check_no_mcp_manifests` blocks mechanically. This option is
   recorded explicitly because the engine ships the server one subcommand away,
   which makes it a standing temptation rather than a hypothetical.
2. **Option A is the precedented shape.** ADR-094 established skill + bundled
   script as this repo's tool-call-style retrieval vehicle: the agent invokes
   the script as an explicit, visible Bash call and the response enters context
   as untrusted tool output — the carve-out `rules/no-mcp-servers.md` blesses.
   The `skills/` surface is already wired into `setup.sh`, `validate.sh`
   (symlink pair, shellcheck), and `scripts/check-bash32.sh`, all of which
   glob `skills/*/scripts/*.sh` and pick the new script up unchanged.
3. **Option C is rejected on provenance, not cost.** An agent is the closest
   thing to a callable unit with a schema, but a subagent that reads
   injection-bearing indexed content and returns a synthesized summary is
   precisely the laundering `rules/expertise-consumption.md` forbids —
   restating retrieved text in the agent's own voice strips the marker that
   distinguishes data from instruction. Raw hits reaching the caller inside a
   hygiene envelope is the safer shape. It would also cost a subagent turn per
   query and require an ADR-069 `Bash` allowlist amendment.
4. **Option D is rejected as inapplicable.** Pi's extension registers a tool
   through `pi.registerTool` and refreshes on an `agent_end` event with
   `ctx.isIdle()` gating. Claude Code has no equivalent of either API. What
   transfers is the security design, not the code: this script ports Pi's
   `assertCliInvocation` (basename and subcommand allowlist, `mcp` refused),
   its path and language containment rules, its `--` end-of-options sentinel,
   its scrubbed subprocess environment, and its classify-on-output-content rule
   for an Alpha CLI whose exit codes are unreliable.
5. **Option E is rejected as a real gap**, but narrowly: this skill complements
   Grep rather than replacing it, and the skill file says so.

**Scope: read-only, manual refresh.** The script's subcommand allowlist admits
only `search` and `status`. The agent never runs `ccc init`, `ccc index`,
`ccc reset`, or any daemon subcommand; index freshness is an operator action.
A background re-index — the Claude Code analogue of Pi's `agent_end` hook —
would be a `Stop` hook and is deferred to #116 pending evidence that staleness
bites. Runtime verification of the toolchain pin is deferred to #115; the pin
(engine 0.2.35, model revision, weights SHA-256, transformers CVE floor) is
recorded in the script header as documentation only. A consumption rule making
invocation deterministic, on the `rules/expertise-consumption.md` model, is
deferred to #117 pending usage evidence.

**Invocation posture: model-invocable.** The skill deliberately omits
`disable-model-invocation`, so Claude may invoke it unprompted. Retrieval is
side-effect-free and read-only, which is the property that justifies it; the
`/expertise` skill has the same posture. The skill body carries no
`$ARGUMENTS` interpolation, so re-invocation within a session renders
identically and is deduplicated rather than re-appending the body per call.

**Output hygiene.** Unlike the expertise API, which supplies its own hygiene
envelope, nothing upstream frames `ccc` output — so the script generates the
envelope: a per-call random nonce delimiter, a content-class tag, and a
data-not-instructions note, with caps of 2 KB per result and 24 KB per call and
explicit inline truncation markers. The caps match the per-entry and per-block
bounds `rules/expertise-consumption.md` already sets for woven advisory
content, so a retrieved hit and a woven expertise entry are bounded alike.

### Tradeoffs

* Good: semantic retrieval over the ADR/rule/agent corpus with no new policy
  carve-out, no new distribution surface (the `skills/` directory already
  exists), and no upstream-extension maintenance dependency; the security
  design is inherited from a reviewed precedent rather than invented.
* Bad: a real external runtime dependency acquired out-of-band (Python >= 3.11,
  a ~500 MB-1 GB pipx venv, a ~90 MB one-time model download) — `setup.sh` does
  not install it and the skill degrades to an exit-5 diagnostic without it; the
  `ccc` text output is an undocumented Alpha contract parsed by a
  version-pinned tolerant parser; a third retrieval surface for the agent to
  choose among, alongside Grep and the Explore agent.
* Accepted residual risks: (1) `ccc search` auto-starts a daemon that inherits
  the environment of whatever started it and persists across sessions — the
  script invokes `ccc` under a scrubbed allowlist environment, but cannot clean
  a daemon already started from a broader one, so the skill documents a
  one-time `ccc daemon stop`; (2) indexed content is attacker-influencable via
  any file that reaches the repo, and enters context on retrieval — mitigated
  by the envelope, the caps, and the untrusted-output constraints, not
  eliminated; (3) the pin is documentation until #115 lands, so a `ccc` upgrade
  can silently change the parsed format or the embedding model beneath the
  index; (4) the default exclude pattern `**/.*` omits `.github/` from the
  index, so workflow and ruleset questions still need Grep; (5) the index lives
  in a gitignored `.cocoindex_code/` directory holding a copy of repository
  content — local only, never committed, but present on disk outside git's
  view.

## More Information

* #115 (runtime pin verification), #116 (Stop-hook re-index), #117 (consumption
  rule) — the three deferrals recorded above
* ADR-094 (skill + bundled script as the retrieval vehicle; the packaging
  analysis this reuses), ADR-002 / `rules/no-mcp-servers.md` (the prohibition
  Option B falls under), ADR-046 (expertise injection removal — why retrieval
  is a visible tool call and never a hook), ADR-092 (observability-only hook
  precedent, relevant to #116), ADR-069 (`Bash` allowlist, relevant to
  Option C)
* Pi reference: pi_config ADR-0033 and `agent/extensions/indexing/` — the
  security design ported here; `agent/extensions/indexing/pin.ts` is the source
  of the pin constants recorded in the script header
