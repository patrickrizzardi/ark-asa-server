## Deviation Judge: m2-shared-economy-store Phase 2 Deviation #2 (Round 3)

### Verdict: PASS

### Deviation summary (one line)
Dockerfile:34 comment reworded to reference `(ASAAPI_VERSION)` symbolically instead of hardcoding "AsaApi 1.21," eliminating the specific stale-version-string-in-comment residual that round-2 flagged as informational.

### Adversarial input(s) constructed

1. **ASAAPI_VERSION bumped to 1.22 (bundles Permissions 1.2) but PERMISSIONS_VERSION default left at 1.1** — the symbolic `(ASAAPI_VERSION)` pointer is now accurate as written ("records what the pinned AsaApi carries") but the ARG default value `=1.1` is stale. Does the round-3 reword leave a reader worse off than before?

2. **`docker build --build-arg PERMISSIONS_VERSION=1.2 .`** — operator passes a non-default Permissions version via CLI expecting a different Permissions bundle to be fetched. Comment now reads "no URL interpolation" — does the symbolic reference add any ambiguity about whether interpolation might be deferred to a later layer?

3. **Developer reads ONLY Dockerfile:34 in isolation** (e.g., via a GitHub blame view stopping at that line) — does the reworded comment convey non-enforcement unambiguously without needing to scroll to see the RUN block?

### Trace

**Input 1 (strongest attempt):**
- Dockerfile:32 is bumped: `ARG ASAAPI_VERSION=1.22`
- Dockerfile:34 remains: `ARG PERMISSIONS_VERSION=1.1  # doc-pin only — … Records which Permissions version the pinned AsaApi (ASAAPI_VERSION) carries.`
- The comment's symbolic `(ASAAPI_VERSION)` is now a pointer to line 32's value (1.22). The comment is syntactically accurate — it does record which Permissions version the pinned AsaApi carries. But if AsaApi 1.22 bundles Permissions 1.2, the *value* `=1.1` is stale.
- This is identical in risk profile to the round-2 state: a developer who bumps ASAAPI_VERSION must also bump PERMISSIONS_VERSION if the bundled Permissions version changed. The round-3 reword removes the extra staleness signal ("1.21" appearing in the comment when ASAAPI_VERSION says 1.22) — but the underlying doc-maintenance obligation is unchanged.
- Critically: the round-3 reword does not make this WORSE. It eliminates one stale vector (comment literal vs ARG literal), keeps the pre-existing one (ARG default vs upstream changelog). The round-2 judge PASSed with the latter already in scope as a cosmetic concern; round-3 does not introduce new exposure.
- Build correctness: zero impact. PERMISSIONS_VERSION is never interpolated into any shell command (Dockerfile:35-54, grep confirms zero occurrences of `${PERMISSIONS_VERSION}`). A stale doc-pin default misleads documentation readers; it does not affect what ships.

**Input 2:**
- `docker build --build-arg PERMISSIONS_VERSION=1.2 .` reaches Dockerfile:34.
- BuildKit overrides the ARG to 1.2.
- The RUN block at Dockerfile:35-54 is scanned: zero `${PERMISSIONS_VERSION}` occurrences. The override is discarded.
- Comment says "no URL interpolation" — the symbolic reword adds no ambiguity here. The behavior is the same as round-2, and the comment is now MORE explicit about why (`no URL interpolation` + `ships bundled in the AsaApi zip`). No break.

**Input 3:**
- Reader sees `ARG PERMISSIONS_VERSION=1.1  # doc-pin only — Permissions ships bundled in the AsaApi zip; no separate download, no URL interpolation. Records which Permissions version the pinned AsaApi (ASAAPI_VERSION) carries.`
- Without seeing the RUN block: the phrase "no URL interpolation" is self-contained and unambiguous. The symbolic `(ASAAPI_VERSION)` names the ARG being cross-referenced without implying interpolation. No break.

### Strategies attempted

- **Mixed inputs**: Tested "ASAAPI_VERSION bumped to 1.22 but PERMISSIONS_VERSION left at 1.1" — the symbolic reference is accurate-as-written (correctly points to the ARG that determines which AsaApi version is used), but the ARG default value can still go stale independent of the comment text. This pre-existing documentation maintenance obligation is unchanged by the reword and was already accepted in round-2 as a cosmetic concern. Did not break the fix.

- **Boundary inputs**: Tested `--build-arg PERMISSIONS_VERSION=1.2` (operator overrides the doc-pin ARG at CLI). Silently no-ops; the inline comment explicitly says "no URL interpolation." The symbolic reword adds no new surface for a caller to misread. Did not break the fix.

- **Existing-primitive check**: Grepped the full repo for any other file referencing `PERMISSIONS_VERSION`. Zero occurrences outside the Dockerfile line itself and plan/notes/review files. No second interpolation site that the comment might mislead. Did not break the fix.

- **Trace-through**: Walked Dockerfile:35-54 (the full RUN block) for `${PERMISSIONS_VERSION}` expansion points. Zero occurrences confirmed, same as round-2. The two real pins (`${ASAAPI_VERSION}` at Dockerfile:36, `${ARKSHOP_VERSION}` at Dockerfile:48) are mechanically intact. The reword touches only the comment at Dockerfile:34; no RUN-block lines changed.

### Bottom Line

The only change is the comment trailing clause: "AsaApi 1.21" → "the pinned AsaApi (ASAAPI_VERSION)." Every adversarial input that broke round-1 or was residual-flagged in round-2 either no longer applies (hardcoded version string) or was already PASS-accepted. Nothing new to shoot at. PASS.
