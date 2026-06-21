## Acceptance Verifier Report: m2-shared-economy-store Phase 4 Round 2

### Diff Scope
- Files changed: 1 (`entrypoint.sh`)
- Lines added/removed: +120 / -7
- Diff source: `git diff 29735d2 -- entrypoint.sh`

### Per-AC Audit (structured — coordinator parses this to write Evidence sub-bullets into plan file)

--- AC ENTRY ---
AC: "With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / "loaded" lines), no fatal load error"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC1 — live boot on dell (image sha `5a83628ac1df`), `ArkApi_<pid>_<date>.log` shows `[API][info] API was successfully loaded`, `[API][info] Loaded plugin Ark:SA ArkShop V1.4`, `[API][info] Loaded plugin Ark:SA Permissions V1.1`, `[API][info] Loaded all plugins`, no critical/fatal lines. Round-2 self-heal re-verification (`phase4-runtime-evidence.md` §Round-2 fix verification): pdb deleted → modded boot → `ensure_modded_pdb()` restored via steamcmd validate (1 attempt) → same `API was successfully loaded` + both plugins loaded — no manual intervention. `entrypoint.sh` diff: `ensure_modded_pdb()` function added (+52 lines), called in `main()` under `if [[ "${ENABLE_ASAAPI}" == "1" ]]` guard; install-time pdb-shed now conditional on `ENABLE_ASAAPI != "1"` (so a fresh modded install retains the pdb). Xvfb fail-fast socket check added (`[[ ! -S /tmp/.X11-unix/X0 ]] && exit 1`) closes the silent-nodrv_CreateWindow path that produced zero-plugin loads.
Reason: The evidence file contains verbatim ArkApi log lines from a real Proton/Wine boot on dell showing the framework banner + both plugins loaded, with no `[critical]` or `[fatal]` lines. The Round-2 self-heal proof specifically exercises the scenario that would have caused silent zero-plugin loads (absent pdb on a vanilla-shed volume), and shows `API was successfully loaded` after automated restoration — directly proving the AC's "no fatal load error" predicate survives the pdb-absence edge case. The diff's `ensure_modded_pdb()` is the code that produced that behavior. AC semantically matched.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "The server still reaches "has successfully started" / advertises for join (the M1 success signal) under the loader"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC2 — verbatim container log lines from `ENABLE_ASAAPI=1` boot on dell: `[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [AsaApiLoader — modded, Xvfb :0]`, `Server: "ARK-Test" has successfully started!`, `Server has completed startup and is now advertising for join. (10.29GB Mem)`. Round-2 self-heal boot (`phase4-runtime-evidence.md` §Round-2 fix verification) also shows `Server: "ARK-Test" has successfully started!` after the pdb restore, confirming the success signal survives the self-heal path. `entrypoint.sh` diff: `launch_exe="${LOADER_EXE}"` set in the `ENABLE_ASAAPI=1` branch; Xvfb started and socket-verified before `proton run`; `proton run "${launch_exe}" "${query}" ${flags}` carries the same `${query}`/`${flags}` as the vanilla path.
Reason: The evidence contains the verbatim ASA engine log line `Server has completed startup and is now advertising for join` from a real boot under `AsaApiLoader.exe` — the exact M1 success signal the AC names. The Round-2 self-heal path also produced the success signal, so the added `ensure_modded_pdb()` code does not regress server startup. AC semantically matched.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC3 — `ENABLE_ASAAPI=0 docker compose up -d` (same image `5a83628ac1df`, no rebuild): log shows `[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [vanilla]`, `Server: "ARK-Test" has successfully started!`, `Full Startup: 48.05 seconds`, `grep "API was successfully loaded" → 0`. `entrypoint.sh` diff: `else` branch sets `launch_exe="${SERVER_EXE}"` (i.e. `ArkAscendedServer.exe`), skips Xvfb entirely (`xvfb_pid` stays `""`), skips `ensure_modded_pdb()` call (guarded by `[[ "${ENABLE_ASAAPI}" == "1" ]]`), logs `[vanilla]`; `proton run "${launch_exe}"` with the same `${query}`/`${flags}`. Pdb-shed in `install_or_update()` is also conditional: `if [[ "${ENABLE_ASAAPI}" != "1" ]]` → vanilla fresh installs still shed the pdb as M1 did.
Reason: The evidence shows a live vanilla launch from the same image with no rebuild — zero AsaApi load confirmed by grep, server starts and advertises. The diff's `else` branch is clean: no Xvfb, no `ensure_modded_pdb()`, `SERVER_EXE` as the binary, identical query/flags. The `[vanilla]` log tag and the grep-0 result together prove the rollback path is byte-for-byte M1 behavior. AC semantically matched.
--- END AC ENTRY ---

### Overall Verdict

OVERALL VERDICT: PASS — all 3 AC are MET

### Required Fixes

None — all ACs MET.

### Bottom Line

Chief, round-2 delta is clean — the pdb self-heal is the only thing that matters here and it's got a live dell receipt with the full log trail. All 3 ACs MET, PASS carries.
