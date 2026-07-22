# ADR-096: Create-Only Write-Back and Gated Lima Host-Gateway Allowance for the /expertise Skill

**Status:** Accepted
**Date:** 2026-07-22

## Context and Problem Statement

ADR-094 shipped the /expertise skill read-only with a hard loopback-only base
URL, and recorded that any write path requires its own ADR. Issue #81 asks for
create-only write-back so expertise learned in framework sessions can be
captured to the local agent-expertise-api, mirroring the Pi client's phase-1
contract (pi-expertise-client, ADR-0028/0103 there). Separately, the primary
development host is a Lima guest whose API instance runs on the macOS host —
reachable only via the Lima user-mode gateway (`host.lima.internal` →
`192.168.5.2`), which the loopback gate refuses. Both the read and write paths
must be able to reach that instance without opening the gate to arbitrary
hosts.

A three-agent research fan-out (shell-expert, security-review-expert advisory
mode, and a read-only sweep of the Pi reference client) informed this design;
the Pi client itself has no Lima carve-out (its only non-loopback path is a
separate HTTPS bearer profile), so the gateway allowance here is a deliberate,
documented deviation.

## Considered Options

* **Option A** — `create` subcommand inside `expertise-search.sh`.
* **Option B** — Sibling script `expertise-create.sh` duplicating the shared
  helpers, with its own `allowed-tools` grant in `SKILL.md`.
* **Option C** — Hardcode `{host.lima.internal, 192.168.5.2}` into the host
  allowlist unconditionally.
* **Option D** — Free-form extra-host config key
  (`EXPERTISE_SEARCH_EXTRA_HOST=<any value>`).
* **Option E** — Fixed two-entry Lima predicate enabled only by an explicit
  boolean config opt-in, default off.
* **Option F** — Full CRUD write path (update/delete/archive).

## Decision Outcome

Chosen options: **B** (sibling script) and **E** (opt-in fixed Lima
predicate), create-only (**F rejected**, matching Pi ADR-0028: update/delete
semantics need separate safety and audit treatment).

1. **Sibling script, not a subcommand.** `SKILL.md`'s `allowed-tools` globs
   match by script path, so a subcommand added to the read script would grant
   write capability with no visible frontmatter diff. A sibling
   `expertise-create.sh` forces an explicit, reviewable `allowed-tools` line
   and leaves the battle-tested read path untouched. The duplicated helpers
   follow the repo's standalone-script precedent (ADR-053); the `validate.sh`
   lockstep check is generalized to cover the new copies (`SECRET_PATTERNS`
   three-way across both secrets hooks and the create script; host predicates
   across the two expertise scripts).
2. **Gated Lima predicate (three config keys, all user-provisioned, env or
   mode-600 config file, default off):**
   * `EXPERTISE_ALLOW_LIMA_GATEWAY=1` — extends the allowed-host set of BOTH
     scripts from {loopback} to {loopback ∪ `host.lima.internal` ∪
     `192.168.5.2`}. The set is fixed in code — never user-extendable
     (Option D rejected: a free-form host key would let a mistyped or
     tampered config point the bearer token at an arbitrary host). Option C
     rejected: `192.168.5.2` is an ordinary RFC1918 address (collision-prone
     off-Lima) and Lima allocates different subnets per named instance, so an
     unconditional hardcode widens trust for every non-Lima install.
   * `EXPERTISE_ALLOW_WRITE=1` — required for any create (analog of Pi's
     `PI_EXPERTISE_ALLOW_LOCALDEV_WRITE`).
   * `EXPERTISE_ALLOW_WRITE_REMOTE=1` — additionally required when the host
     matched via the Lima predicate rather than true loopback, so the
     compounded trust widening (non-loopback transport AND write capability)
     is two conscious opt-ins, not a free side effect of the first two keys.
3. **Create contract** (verified against the Pi reference client and
   agent-expertise-api v1.1.0+): `POST /expertise` with required
   `domain`/`title`/`body`/`entryType` (`IssueFix|Caveat|Requirement|Pattern`)
   /`severity` (`Info|Warning|Critical`)/`source` (default `claude-session`),
   optional `tags`; `entryType`/`severity` always sent explicitly (the server
   silently mis-defaults omissions); the server's `tenant` field is
   deliberately never sent — `tenant: "shared"` bypasses the draft/review
   queue, and every framework-originated create must land in that queue. A
   fresh, randomly generated `Idempotency-Key` (UUIDv4 ladder: `uuidgen` →
   `/proc/sys/kernel/random/uuid` → `od`+`/dev/urandom` with RFC 4122 bit
   fixup → hard fail) is sent per request; the key is never content-derived
   and never caller-supplied, so the dedup cache cannot be used as a content
   oracle. `X-Actor-Class: agent` is sent as on the read path's server
   contract (API ADR-008).
4. **Fail-closed body secret scan before any network call.** The ADR-095
   `SECRET_PATTERNS` set (byte-identical copy, lockstep-checked) runs over a
   single concatenated buffer of every string field (closing the
   same-call-field-splitting gap), plus a literal substring check for the
   script's own live API key (a bare opaque token matches no ADR-095
   pattern). Bodies over 64 KB are refused outright — never truncated then
   scanned. Refusals name the pattern category only and never echo matched
   text (boolean `grep -q` re-probes; the match never enters a variable).
5. **409 near-duplicate suppression.** Unlike the Pi client (which surfaces
   the existing entry bounded and redacted), the 409 response body is not
   echoed at all — only a summary directing the caller to /expertise search.
   agent-expertise-api#209 tracks cross-principal 409 disclosure server-side;
   until it lands, a 409 body is uniquely likely to contain another
   principal's stored content. #97 tracks relaxing this once #209 is fixed.
6. **Token and temp-file hygiene** carried over and extended: `umask 077`
   set once (covers the new payload temp file uniformly, rather than
   per-file `chmod`), token via `-H @file` only, xtrace suppressed around
   every key-touching line including the literal-key scan, `--proto
   '=http,https'`, no redirect following, no `-G` on the write call.

### Tradeoffs

* Good: write-back parity with Pi inside the existing policy boundary
  (visible tool-call write, user-gated — `rules/no-mcp-servers.md`
  unchanged); the read path binary is untouched; every trust widening is an
  explicit user-provisioned opt-in.
* Bad: a third copy of `SECRET_PATTERNS` and a second copy of the
  config/URL/curl scaffolding to keep in lockstep (mitigated: the
  `validate.sh` lockstep check now covers them mechanically); three config
  keys is more provisioning friction than one.
* Accepted residual risks: (1) plaintext HTTP over the guest's `eth0`/Lima
  user-mode NAT when the gateway allowance is active — accepted only for
  Lima's default (non-shared) user-mode network, where the segment is not
  reachable from the physical LAN; a shared/bridged Lima network voids this
  assumption and is on the operator; (2) `/etc/hosts` poisoning of
  `host.lima.internal` requires guest-root, which already defeats the
  mode-600 config file — same trust class as the existing `localhost` name
  trust; (3) adversarial secret-scan evasion (encoding, cross-call
  splitting) — backstopped by the write opt-ins, the server-side draft/review
  queue, and CI gitleaks (ADR-078), not by the client regex; (4) the client
  gates are session-safety rails, not a security boundary — the boundary is
  the server-side scope split: deployments should mint write keys scoped to
  `expertise.write.draft` only; (5) the 64 KB cap and enum lists are client
  copies of server behavior and can drift — re-verify on API upgrades.

## More Information

* #81 (this feature), #97 (409 suppression relaxation follow-up), #69
  (Unix-domain-socket transport candidate), agent-expertise-api#209
  (cross-principal 409 disclosure)
* ADR-094 (read-only phase 1 — superseded in part: its loopback-only and
  read-only postures are amended by this ADR; its packaging decision stands),
  ADR-095 (secret pattern set), ADR-083 (lockstep check), ADR-053
  (duplication-over-sourcing precedent)
* Pi reference: pi-expertise-client `lib/create.ts`, ADR-0028/0103
  (pi-config) — create-only scope, write opt-in, category-only secret scan
