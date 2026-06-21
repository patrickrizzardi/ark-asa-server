# m2-shared-economy-store Phase 4 Deviations — captured 2026-06-21T02:44Z

D_count: 3

> Provenance note: the plan-executor implemented Steps 1–3 (the launch flip) with ZERO deviations
> (its report: "None — stayed within declared scope" / "None — implementation matched plan's named
> approaches"). The three deviations below were made by the coordinator while driving Step 4 (the
> dell runtime boot), because the boot surfaced three real defects that blocked AsaApi from loading.
> They are documented here as deviations so the deviation-judge adjudicates each adversarially.

## Scope Deviations (verbatim)

**Deviation #1 (scope)** — Touched `Dockerfile`, which is OUTSIDE Phase 4's declared
`Files (expected scope)` (entrypoint.sh, docker-compose.yml, .env.test.example, .env.prod.example).
Added an `apt-get install -y --no-install-recommends unzip` layer after `USER root`.
Rationale: the first real `docker build` of the modded image (Phase 2's plugin-download RUN) failed
with `unzip: not found` (exit 127) — the `parkervcp/steamcmd:proton` base ships curl/tar but not
unzip, and Phase 2 was never actually built (static-evidence ceiling). The build is a hard
prerequisite for every Phase 4 AC (no build → no boot → cannot prove AsaApi loads), so the Phase 2
defect had to be fixed here. unzip is an immutable, version-independent build dependency → Dockerfile
is the correct home per build-time-vs-runtime.md.

## Approach Deviations (verbatim)

**Deviation #2 (approach)** — Added an Xvfb virtual framebuffer to the loader launch branch
(beyond the plan's Steps 1–3, which only described branching the launch target). When
ENABLE_ASAAPI=1: start `Xvfb :0 -screen 0 1024x768x24 -nolisten tcp`, export `DISPLAY=:0`, wait for
the X socket, then `proton run`; kill Xvfb at shutdown. Vanilla branch unchanged.
Diff hunks: entrypoint.sh:228-249, entrypoint.sh:266
Rationale: with the build fixed, the container restart-looped. `WINEDEBUG=+err,+seh` showed
`AsaApiLoader.exe` aborting on `nodrv_CreateWindow` ("explorer process failed to start") — the loader
creates a real Win32 window during init (Wine x11 driver), unlike the vanilla server which runs
headless via SDL_VIDEODRIVER=dummy. No X display → Wine aborts. Xvfb provides the display. Gated to
the loader branch so ENABLE_ASAAPI=0 stays byte-for-byte M1 (AC3). Both Xvfb/xvfb-run already in base.

**Deviation #3 (approach)** — Stopped shedding `ArkAscendedServer.pdb` at install when
ENABLE_ASAAPI=1 (entrypoint.sh first-install block). Was an unconditional `rm -rf ...pdb` (M1
disk-saving); now wrapped in `if [[ "${ENABLE_ASAAPI}" != "1" ]]`. Movies/ still always shed.
Diff hunks: entrypoint.sh:42-50
Rationale: with Xvfb the server started, but AsaApi loaded ZERO plugins — its log showed
`[critical] Failed to read pdb`. AsaApi SHA-256's the pdb to derive its offset-cache key, then
loads the cached server symbol offsets needed to hook the server; no pdb → no key → no cache →
critical → no plugins. The M1 pdb-shed optimization is incompatible with the modded loader. Keeping
the pdb when modded fixed it: log then showed `API was successfully loaded` + both plugins loaded.
(One-time: the pdb, already deleted on dell's M1 volume, was restored via steamcmd validate (~2.0 GB)
— a data migration, not a code change.)

## Resolved spawn list (orchestrator's parsed view)

### Deviation #1
- **type**: scope
- **rationale**: Touched Dockerfile (outside Phase 4 scope) to add an unzip apt layer — Phase 2's plugin-download RUN failed with `unzip: not found` at the first real image build; the build is a hard prerequisite for all Phase 4 ACs. Immutable build dep → Dockerfile per build-time-vs-runtime.md.
- **diff hunks**: Dockerfile:13-19

### Deviation #2
- **type**: approach
- **rationale**: Added Xvfb + DISPLAY=:0 to the loader launch branch (beyond Steps 1–3). AsaApiLoader creates a Win32 window during init and aborts (nodrv_CreateWindow) under Proton without an X display; vanilla runs headless via SDL dummy. Gated to the loader branch so ENABLE_ASAAPI=0 stays byte-for-byte M1.
- **diff hunks**: entrypoint.sh:228-249, entrypoint.sh:266

### Deviation #3
- **type**: approach
- **rationale**: Stopped shedding ArkAscendedServer.pdb when ENABLE_ASAAPI=1. AsaApi requires the pdb to derive its offset-cache key; without it, zero plugins load (`[critical] Failed to read pdb`). M1's unconditional pdb-shed is incompatible with the modded loader.
- **diff hunks**: entrypoint.sh:42-50
