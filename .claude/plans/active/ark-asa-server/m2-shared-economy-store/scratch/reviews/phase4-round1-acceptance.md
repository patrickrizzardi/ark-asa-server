## Acceptance Verifier Report: m2-shared-economy-store Phase 4 Round 1

### Diff Scope
- Files changed: 3 (`Dockerfile`, `docker-compose.yml`, `entrypoint.sh`)
- Lines added/removed: +71 / -7
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile`
- Primary evidence source: `phase4-runtime-evidence.md` (surviving evidence dump from ephemeral dell containers; captured 2026-06-21T02:44Z on bare-metal Ubuntu 22.04.5 / Docker 24.0.7 / compose v2.21.0)

---

### Per-AC Audit (structured — coordinator parses this to write Evidence sub-bullets into plan file)

--- AC ENTRY ---
AC: "With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / "loaded" lines), no fatal load error"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC1 — AsaApi framework log output captured on dell:
  `[API][info] API was successfully loaded`
  `[API][info] Loaded plugin Ark:SA ArkShop V1.4 (Shop, Currency & Kits)`
  `[API][info] Loaded plugin Ark:SA Permissions V1.1 (Manage permissions groups)`
  `[API][info] Loaded all plugins`
  Filename note: v1.21 writes `ArkApi_<pid>_<date>.log` not a fixed `ArkApi.log` — coordinator pre-corrected, same log path/dir (`Win64/logs/`). Diff: `entrypoint.sh` +`LOADER_EXE` definition + `ENABLE_ASAAPI=1` branch launches `AsaApiLoader.exe` via Xvfb (`entrypoint.sh` lines ~253–265 in diff hunk).
Reason: Framework banner ("Cache files downloaded and processed successfully", "Reading cached offsets", "Initialized hooks"), "successfully loaded" line, and both plugin-loaded lines are all present — these are the "framework banner / loaded lines" the AC requires. No `[critical]` or `[fatal]` entry appears. The only warning (`[OPTIONAL MOD MISSING] 'AsaApiUtils'`) is the Phase-5-deferred mod, explicitly carved out by Phase 4's Scope Boundary. Evidence is from a live boot on dell under the `feat/m2-4-asaapi-loader` branch, files verified byte-identical between local tree and dell at capture time (evidence file §preamble). Evidence is from this diff, not pre-existing.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "The server still reaches \"has successfully started\" / advertises for join (the M1 success signal) under the loader"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC2 — captured on dell under `ENABLE_ASAAPI=1`:
  `[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [AsaApiLoader — modded, Xvfb :0]`
  `[2026.06.21-02.39...] Server: "ARK-Test" has successfully started!`
  `[2026.06.21-02.39...] Server has completed startup and is now advertising for join. (10.29GB Mem)`
  Container status: `Up` (not restarting). Full startup time: 47.73 seconds (prior modded boot log also in evidence).
Reason: Both M1 success-signal lines are present verbatim ("has successfully started" + "advertising for join"). The launch-banner line immediately preceding confirms this is the AsaApiLoader branch, not a vanilla boot. Container was in `Up` state, not restart-looping. The evidence is from the same branch/boot that produced AC1's AsaApi log output, so the loader is provably what delivered the "started" signal. Semantic match is exact: the AC says "still reaches" under the loader, and the log proves it did.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC3 — captured on dell, same image (`ark-asa:latest` sha `5a83628ac1df`), no rebuild:
  `[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [vanilla]`
  `[2026.06.21-02.42.16:666][ 5]Server: "ARK-Test" has successfully started!`
  `[2026.06.21-02.42.20:195][ 5]Full Startup: 48.05 seconds`
  `[2026.06.21-02.42.33:280][210]Server has completed startup and is now advertising for join. (10.35GB Mem)`
  `grep "API was successfully loaded" → count=0` — AsaApi entirely absent this boot.
  Diff: `entrypoint.sh` `else` branch sets `launch_exe="${SERVER_EXE}"` (the original `ArkAscendedServer.exe` variable, unchanged from M1 at entrypoint.sh:22); skips Xvfb entirely; reuses identical `${query}`/`${flags}` (`docker-compose.yml` adds `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` — single new env line).
Reason: Three legs of the AC are all satisfied. (1) Binary: `launch_exe="${SERVER_EXE}"` resolves to `ArkAscendedServer.exe` — the M1 binary, confirmed by the `[vanilla]` launch banner. (2) No AsaApi: grep count=0 proves AsaApi did not load. (3) No rebuild: evidence file explicitly states "same image, no rebuild" and the image SHA is identical across both boots. "Byte-for-byte M1 vanilla path" is structurally enforced by the diff: the `else` branch adds nothing to the launch command (no Xvfb, no loader, no extra flags) — it is literally the prior single-branch launch line now behind a conditional. Rollback is a pure env-edit — no image rebuild required.
--- END AC ENTRY ---

---

### Overall Verdict

OVERALL VERDICT: PASS — all 3 AC are MET

### Required Fixes

None — all ACs MET.

### Bottom Line

Chief, all three gates closed clean. AsaApi 1.21 initializes under GE-Proton (the core unknown this phase was built to answer), the server reaches join-advertising under the loader, and the vanilla kill switch works on a pure env flip with no rebuild — exactly the contract Phase 4 was written to prove.
