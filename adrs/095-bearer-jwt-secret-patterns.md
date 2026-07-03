# ADR-095: Add JWT and Authorization-Bearer Detectors to the Secrets-Guard Pattern Set

**Status:** Accepted
**Date:** 2026-07-03

## Context and Problem Statement

The shared secrets-guard pattern set (pre-commit and in-session layers,
ADR-053/ADR-059) detects PEM headers, AWS access key IDs, and GitHub token
prefixes, but no OIDC/JWT or generic bearer-token shape. The gap became
concrete with the `/expertise` skill (ADR-094): its API key is an opaque
bearer token that would pass both guard layers if hardcoded (#64, surfaced by
the #47 security analysis). Any detector must balance coverage against false
positives on documentation, format strings, and the pattern text itself, and
must stay portable across BSD and GNU grep (ADR-053, #201).

## Considered Options

* **Option A** — Two targeted alternatives: a signed-JWT shape
  (`eyJ…​.eyJ…​.sig`, all segments length-bounded) and an
  `Authorization: Bearer <20+ token chars>` literal heuristic.
* **Option B** — JWT pattern only; skip the bearer heuristic (fewer false
  positives, but misses exactly the opaque-key class #64 names).
* **Option C** — Generic entropy scanning (any high-entropy string) — the
  approach gitleaks uses with tuned rules; too noisy for a grep-based hook.
* **Option D** — Status quo: rely on CI gitleaks only (post-push detection is
  the expensive layer; the guards exist to catch secrets pre-commit and
  in-session).

## Decision Outcome

Chosen option: **Option A**, because it covers both halves of the #64 gap at
near-zero false-positive cost:

1. **JWT** — `eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}`
   matches signed tokens (header.payload.signature; `eyJ` is base64url `{"`).
   Unsigned/`alg:none` tokens are deliberately out of scope — a bare
   two-segment match would flag base64 blobs and truncated examples.
2. **Bearer literal** — `Authorization: Bearer [A-Za-z0-9._~+/=-]{20,}`
   requires 20+ contiguous token characters after the header name, so
   `Bearer %s`, `Bearer <key>`, `Bearer $TOKEN`, and prose like "Bearer
   literals" never match, while a pasted opaque key does. Verified: neither
   alternative matches its own pattern text, so committing the hooks or the
   rule documentation does not self-trip the guard.
3. Both alternatives verified on BSD (`/usr/bin/grep`) and PATH grep;
   existing skip surfaces (`*.example`, `tests/`, fixtures,
   `.secrets-guard-allowlist`, `SKIP_SECRETS_GUARD=1`) apply unchanged for
   deliberate fixtures.

The pattern set remains duplicated in lockstep across the two hooks
(`validate.sh` enforces byte-identity, ADR-083); the Pi `expertise-client`
extension keeps its own copy (`lib/secret-scan.ts`) and needs a matching
update in that repo.

### Tradeoffs

* Good: a hardcoded expertise-API key (or any pasted JWT/bearer credential)
  is now caught pre-commit and in-session, closing the residual risk ADR-094
  accepted; no new dependencies; portable ERE.
* Bad: opaque tokens *without* the `Authorization: Bearer` context and
  unsigned JWTs still pass — entropy-class detection stays delegated to CI
  gitleaks (ADR-078). Test fixtures containing assembled tokens must keep
  literals split (concatenation) to avoid tripping CI gitleaks' own JWT rule.

## More Information

* #64 (this gap), #47 (the analysis that surfaced it), ADR-094 (`/expertise`
  token posture this backstops)
* ADR-053 (in-session layer + lockstep-by-duplication), ADR-057 (pattern
  evolution precedent), ADR-059 (staged-blob scanning), ADR-083 (lockstep
  gate), ADR-078 (CI gitleaks)
* `rules/secrets-guard.md` (pattern-set documentation updated with this ADR)
