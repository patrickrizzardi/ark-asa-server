## Deviation Judge: ark-asa-server / m2-shared-economy-store Phase 2 Deviation #2 (Round 2)

### Verdict: PASS

### Deviation summary (one line)
Executor added versioned `?version=${ARG}` URL parameters for ASAAPI and ARKSHOP downloads, and kept PERMISSIONS_VERSION as a non-interpolated doc-pin ARG with an explicit inline comment explaining it drives no download.

### Adversarial input(s) constructed
1. Future developer runs `docker build --build-arg PERMISSIONS_VERSION=1.2 .` expecting a newer Permissions bundle — the build silently succeeds, produces the same image, because the ARG is never interpolated.
2. Developer bumps `ARG ASAAPI_VERSION=1.22` (legitimate version bump) without updating the comment's hardcoded "AsaApi 1.21" string — the comment now lies about which AsaApi version the Permissions annotation tracks.
3. Developer reads the block header "Bake pinned AsaApi + ArkShop + Permissions" and searches the RUN block for a Permissions download step, expecting the pattern AsaApi-download / ArkShop-download / Permissions-download — finds only two downloads, might add a third.

### Trace
**Input 1 — silent no-op on ARG bump (strongest):**
- `docker build --build-arg PERMISSIONS_VERSION=1.2 .` reaches Dockerfile:34.
- `ARG PERMISSIONS_VERSION=1.1` is overridden to `1.2` in BuildKit's ARG scope.
- The RUN block at Dockerfile:35-54 is scanned for `${PERMISSIONS_VERSION}` expansion: zero occurrences.
- BuildKit proceeds; no cache invalidation occurs related to Permissions; the RUN layer may or may not rebuild (depending on other ARG changes), but either way the Permissions content is identical.
- The developer's intended action (pin Permissions 1.2) had zero effect.
- **Resolved by**: inline comment at Dockerfile:34 explicitly states "no URL interpolation." A developer editing that exact line cannot miss the comment. The silent-no-op risk is disclosed at the point of action.

**Input 2 — stale "AsaApi 1.21" in comment after ASAAPI_VERSION bump:**
- Developer bumps Dockerfile:32 `ARG ASAAPI_VERSION=1.22`.
- Dockerfile:34 comment now reads "Records which Permissions version AsaApi **1.21** carries" — stale.
- Does NOT cause incorrect behavior: Permissions is still fetched correctly via the AsaApi 1.22 zip. The comment is wrong but the build is correct.
- Risk: future reader misreads which AsaApi version's Permissions bundle is intended. Severity: low — the actual ASAAPI_VERSION ARG on the preceding line is the authoritative value; the comment's embedded version is redundant.
- Not the same finding as round 1. Round 1: silent dead pin, no warning. Here: the warning exists; a stale string inside the warning is a minor maintenance hazard, not a false-enforcement signal.

**Input 3 — block header creates download expectation (mixed-signal probe):**
- Dockerfile:26-31: block header names "Bake pinned AsaApi + ArkShop + Permissions."
- Dockerfile:36: AsaApi curl download. Dockerfile:48: ArkShop curl download. No Permissions curl.
- Dockerfile:40: `rm -rf ".../Permissions/ONLY FOR DEVELOPERS"` — proves Permissions IS inside the AsaApi zip at `ArkApi/Plugins/Permissions/`, so the header claim is factually correct (Permissions IS baked, via the AsaApi zip).
- The RUN block line that touches Permissions (line 40) confirms the bundle is present; a developer tracing the block sees the Permissions directory is processed.
- No missing-download false signal: the absence of a third curl is explained by the fact that Permissions is nested inside the AsaApi zip, visible at line 40.
- PASS.

### Where the fix overshoots (BLOCK only)
N/A — verdict is PASS.

### Strategies attempted
- **Mixed inputs**: Tested "ASAAPI_VERSION bumped but PERMISSIONS_VERSION comment not updated" — stale comment sub-issue found but does not affect build correctness; materially weaker than round-1 finding. Did not break the fix.
- **Boundary inputs**: Tested `--build-arg PERMISSIONS_VERSION=1.2` (bumping the doc-pin ARG via CLI). Silently no-ops, but the inline comment explicitly warns "no URL interpolation." The warning is collocated with the ARG — cannot be missed at edit time. Fix holds.
- **Existing-primitive check**: No sibling primitive exists in the Dockerfile that would provide a narrower doc-pin approach. The executor's inline comment IS the narrower fix named in round 1 as acceptable.
- **Second-caller check**: N/A — this is a Dockerfile ARG; there is no second caller. The "second caller" analog is a second developer reading the ARG, covered under Mixed/Boundary above.
- **Trace-through**: Walked the full RUN block (Dockerfile:35-54) for any `${PERMISSIONS_VERSION}` expansion point. Zero occurrences confirmed. The two real pins (`${ASAAPI_VERSION}` at line 36, `${ARKSHOP_VERSION}` at line 48) are interpolated correctly.
- **Round-trip / serialization**: Not applicable (no data serialization in this context).

### Residual (not BLOCK, informational)
The comment at Dockerfile:34 hardcodes "AsaApi 1.21." When `ASAAPI_VERSION` is bumped in a future image build, this string becomes stale. Not a false-enforcement signal — just a comment maintenance burden. The doc-pin ARG and its comment should both be updated when ASAAPI_VERSION changes. This is a cosmetic issue, not a functional one.

### Bottom Line
The round-1 BLOCK was a silent dead pin with no warning. The fix adds an explicit inline comment — "no separate download, no URL interpolation" — directly on the offending ARG line. A developer can't edit that line without reading the warning. The two real pins interpolate correctly into their URLs. PASS.
