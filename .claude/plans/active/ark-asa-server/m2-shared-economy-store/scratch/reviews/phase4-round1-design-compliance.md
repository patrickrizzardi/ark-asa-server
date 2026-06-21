# Design Compliance Review: m2-shared-economy-store Phase 4 Round 1

### Verdict: PASS

### Diff Scope
- Files changed: 5 (Dockerfile, entrypoint.sh, docker-compose.yml, .env.test.example, .env.prod.example — diff command scoped to these files)
- Lines added/removed: +~70 / -~5 (estimated from reading current state; exact counts from `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example`)
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example` (base = Phase 3 commit 29735d2, HEAD = Phase 4 commit)

### Registry State
- Registry path: `.claude/design-sources.md`
- Registry status: present-and-valid
- Fallback globs used: no

Registry contents (3 entries, all `[locked]`):
1. `.claude/rules/build-time-vs-runtime.md` — hard rule governing Dockerfile vs entrypoint placement
2. `docs/internal/decisions/0001-db-engine-mariadb.md` — ADR: MariaDB engine constraint
3. `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — ADR: bake-in-image + deploy-at-runtime pattern

### Design Docs Loaded
- `.claude/rules/build-time-vs-runtime.md` [locked] — primary domain match: every phase of this plan is governed by this rule; locked-errs-toward-loading applies regardless
- `docs/internal/decisions/0001-db-engine-mariadb.md` [locked] — loaded because the diff touches `docker-compose.yml` which contains the `mariadb:11.4` image pin; must verify the constraint is still met
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` [locked] — loaded because Phase 4 changes touch both the Dockerfile (bake side) and entrypoint (deploy side); the ADR's split pattern must be honored

### Design Docs Skipped
None — all three registry docs were loaded.

### Stale Registry Entries
None — all three registry globs resolved to real files on disk:
- `.claude/rules/build-time-vs-runtime.md` ✓
- `docs/internal/decisions/0001-db-engine-mariadb.md` ✓
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` ✓

### Design Divergences Check
Plan path supplied: `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md`

`## Design Divergences` section read. One entry on record:

| Doc | What it says | What we did instead | Status |
|-----|-------------|---------------------|--------|
| `build-time-vs-runtime.md` §The Split (launch row) | Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`) | Through Phases 1–3 launch remained `ArkAscendedServer.exe` | **CLOSED by Phase 4** — the launcher flip is delivered in this diff |

The divergence was recorded with a real rationale (hard phase-dependency: VC++ must be installed before the loader can run; the registry was bootstrapped in Phase 3 one phase before the code reached the target launch state; named cost and reversal trigger both present). It is now moot: Phase 4 delivers `ENABLE_ASAAPI` toggle + `LOADER_EXE` path, closing the gap. No ongoing divergences remain.

Additionally read: `scratch/phase4-deviations.md` (three deviations captured at execution time — scope-change Dockerfile/unzip, approach-change Xvfb, approach-change pdb-retention). These are reviewed below.

---

## Reconciliation

### `build-time-vs-runtime.md` — locked

**The Rule** (reproduced for reference):
> Immutable + cacheable + version-pinned → Dockerfile.
> Mutable + volume-backed + must-be-fresh-each-boot → entrypoint.
> Any "yes" to the 3 questions → entrypoint. All "no" → Dockerfile.

The three questions:
1. Does it depend on runtime state (env vars, mounted volumes, network reachability)?
2. Does the thing it produces change often (game patches, config edits)?
3. Must it re-run on every container start to stay correct?

---

#### Change 1: `unzip` apt package → Dockerfile (Deviation #1, Dockerfile:13–19)

**What the diff does**: Adds `apt-get install -y --no-install-recommends unzip` as a `RUN` layer under `USER root`, before the AsaApi download `RUN` that needs it.

**3-question test**:
- Q1 (depends on runtime state / mounted volumes?): **No** — `apt-get install` runs at `docker build` time; no volume or env var dependency.
- Q2 (changes often?): **No** — `unzip` is a fixed OS tool; the package version is determined at build time and cached.
- Q3 (must re-run every boot?): **No** — it's a build layer, never runs at boot.

**All three "No" → Dockerfile.** Rule: "All no → Dockerfile." Placement is **correct**.

**The split table**: The table's row "OS packages, Proton/Wine, winetricks, libs, curl → **Dockerfile**" is the governing entry. `unzip` is an OS package / build dependency in exactly this category.

**Verdict**: No contradiction. The doc says OS packages → Dockerfile. The diff puts an OS package → Dockerfile. Aligned.

---

#### Change 2: Xvfb virtual framebuffer startup → entrypoint (Deviation #2, entrypoint.sh:238–249, 266)

**What the diff does**: In the loader launch branch (`ENABLE_ASAAPI=1`), starts Xvfb as a background process, exports `DISPLAY=:0`, waits for the X socket, and kills Xvfb at shutdown. The vanilla branch (`ENABLE_ASAAPI=0`) is untouched.

**3-question test**:
- Q1 (depends on runtime state?): **Yes** — the branch is gated on the `ENABLE_ASAAPI` env var; it starts a background process and sets `DISPLAY=:0` at runtime; it cannot run at image-build time (no display, no process management during `docker build`).
- Q2 (changes often?): No — Xvfb is available in the base image.
- Q3 (must re-run every boot?): **Yes** — Xvfb is a process that must be running at boot time before `proton run`; it is killed when the server stops.

**Any "yes" → entrypoint.** Q1 alone is sufficient. Placement is **correct**.

**The split table**: The table has "Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`) → **entrypoint** (runtime, params from env)." Xvfb is launch infrastructure for the loader — it is part of the runtime launch sequence. The underlying reasoning (runtime, depends on env/state) is identical.

**The rule's Anti-Pattern #1** ("everything in the entrypoint") is not triggered here: Xvfb is not a build dependency being lazily deferred to runtime — it is genuinely a runtime-only process that provides a display environment that does not and cannot exist at build time. This is the correct placement.

**Verdict**: No contradiction. The doc says runtime, env-dependent steps → entrypoint. Xvfb startup is runtime + env-dependent. Aligned.

---

#### Change 3: pdb-retention conditional → entrypoint, first-install block (Deviation #3, entrypoint.sh:42–52)

**What the diff does**: The unconditional `rm -rf ArkAscendedServer.pdb` (M1 disk-saving step) is now wrapped in `if [[ "${ENABLE_ASAAPI}" != "1" ]]`. When `ENABLE_ASAAPI=1`, the pdb is retained. When `ENABLE_ASAAPI=0`, it is still shed as before.

**3-question test**:
- Q1 (depends on runtime state?): **Yes** — reads the `ENABLE_ASAAPI` env var; also operates on game files on the `ark-game` volume (the pdb is part of the game install, lives on the volume).
- Q2 (changes often?): The pdb is installed fresh on first boot via steamcmd; it lives on the volume.
- Q3 (must re-run every boot?): No — it's gated inside the `if [[ ! -f "$INSTALL_MARKER" ]]` first-boot block; it runs once per fresh install.

**Any "yes" → entrypoint.** Q1 is satisfied by both the env-var dependency and the volume target. Placement is **correct**.

**The split table**: The table row "**ARK game files** (`steamcmd +app_update 2430930`) → **entrypoint** (~30GB, patches constantly, lives on a volume)" governs. The pdb is part of the game install on the volume; operating on it conditionally at runtime is exactly the entrypoint's job.

**Verdict**: No contradiction. The doc says runtime, volume-backed operations → entrypoint. The pdb conditional reads an env var and acts on volume contents. Aligned.

---

#### Launch flip — divergence closure

**What the diff does**: `entrypoint.sh:238–253` — when `ENABLE_ASAAPI=1`, `launch_exe` is set to `LOADER_EXE` (`AsaApiLoader.exe`); when `ENABLE_ASAAPI=0`, it falls back to `SERVER_EXE` (`ArkAscendedServer.exe`).

**The locked doc's table row**: "Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`) → **entrypoint** (runtime, params from env)"

**Assessment**: This is the exact thing the doc says to do. The Phase 3→4 recorded divergence is now CLOSED. The code meets the table row. No contradiction; the documented deviation is no longer applicable.

---

### `docs/internal/decisions/0001-db-engine-mariadb.md` — locked

The Phase 4 diff does not change `docker-compose.yml`'s `mariadb:11.4` image pin. The ADR's hard constraint (MariaDB, not MySQL ≥8.0.28) is undisturbed.

**Verdict**: No contradiction.

### `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — locked

The ADR specifies:
1. Bake immutable artifacts into the image at `/opt/` paths.
2. Deploy/install them from `/opt/` onto the volume at entrypoint runtime, idempotently.

Phase 4 changes are consistent with this pattern:
- `unzip` is a build dependency added to the Dockerfile (enables the Phase 2 bake, already committed; this is a build-fix, not a new artifact in the pattern).
- Xvfb is runtime launch infrastructure (not an artifact in the bake-deploy pattern — it's a process).
- pdb-retention conditional operates on volume game files at runtime (consistent with "game files → entrypoint" principle the ADR extends).
- The loader flip (`LOADER_EXE`) is the runtime deployment of the AsaApiLoader.exe that was baked to `/opt/asaapi/AsaApiLoader.exe` in Phase 2 and synced to `Win64/` by `deploy_plugins()`.

**Verdict**: No contradiction. The bake-deploy split is honored.

---

### Required Fixes (BLOCK only — empty if PASS)

None — no design-doc contradictions found.

### Concerns (aspirational contradictions — non-blocking)

None.

### Project-vs-Global Overrides

N/A — single project registry, no scope conflict.

### Bottom Line

Three changes, three placements, three clean passes of the 3-question test. The Phase 3→4 recorded divergence is now CLOSED by the launcher flip — not a scar, a resolved todo. The rule doc is consistent with the code, the ADRs are consistent with the code, and nobody tried to sneak a game-file download into the Dockerfile.

OVERALL VERDICT: PASS
