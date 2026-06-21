## Acceptance Verifier Report: m2-shared-economy-store Phase 4 Round 3

### Diff Scope
- Files changed: 8 (cumulative Phase 4 diff against base `29735d2`) — `entrypoint.sh`, `docker-compose.yml`, `.env.test.example`, `.env.prod.example`, `Dockerfile`, `plan.md`, `notes.md`, `.claude/state.md`
- Lines added/removed: +111 / -6 (entrypoint.sh, the only AC-relevant file)
- Diff source: `git diff 29735d2 -- entrypoint.sh` (and `docker-compose.yml`, `.env.*.example` for compose plumbing)
- Round-3 delta (vs round 2): pdb size-floor guard (`pdb_ok()` function replacing bare `-f` test) + Xvfb dual-condition liveness check (`kill -0 "${xvfb_pid}"` + `xvfb_dead` flag). Both are defensive hardening on the happy-path already proven on dell; neither changes behavior on a clean, healthy boot.

### Per-AC Audit (structured — coordinator parses this to write Evidence sub-bullets into plan file)

--- AC ENTRY ---
AC: "With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / "loaded" lines), no fatal load error"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC1 — live boot on dell (image sha `5a83628ac1df`), `ArkApi_<pid>_<date>.log` shows `[API][info] API was successfully loaded`, `[API][info] Loaded plugin Ark:SA ArkShop V1.4 (Shop, Currency & Kits)`, `[API][info] Loaded plugin Ark:SA Permissions V1.1 (Manage permissions groups)`, `[API][info] Loaded all plugins`, no `[critical]`/`[fatal]` lines. `phase4-runtime-evidence.md` §Round-2 fix verification: pdb manually deleted → modded boot → `ensure_modded_pdb()` detected absence, restored via steamcmd validate (1 attempt) → same `API was successfully loaded` + both plugins loaded — no manual intervention. Round-3 delta: `pdb_ok()` size-floor (`stat -c%s > 1048576`) replaces bare `-f` test — hardens silent-truncation edge case; Xvfb dual-condition liveness check (`kill -0 + xvfb_dead`) hardens stale-socket edge case. Neither changes the happy path. `entrypoint.sh` diff: `ensure_modded_pdb()` function (+52 lines), called in `main()` under `[[ "${ENABLE_ASAAPI}" == "1" ]]` guard; install-time pdb-shed conditional on `ENABLE_ASAAPI != "1"`; Xvfb started and socket+process-verified before `proton run`.
Reason: The evidence file contains verbatim ArkApi log lines from a real Proton/Wine boot on dell showing the framework banner and both plugins loaded with no critical/fatal error — the exact predicate the AC names. The round-2 self-heal receipt proves the pdb-absent edge case (a vanilla-shed volume later flipped to modded) results in `API was successfully loaded` via automated restoration, covering the only silent-failure path. The round-3 hardening (size-floor + Xvfb liveness) tightens the existing guards without touching the proven load path. AC semantically matched.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "The server still reaches \"has successfully started\" / advertises for join (the M1 success signal) under the loader"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC2 — verbatim container log lines from `ENABLE_ASAAPI=1` boot on dell: `[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [AsaApiLoader — modded, Xvfb :0]`, `Server: "ARK-Test" has successfully started!`, `Server has completed startup and is now advertising for join. (10.29GB Mem)`. `phase4-runtime-evidence.md` §Round-2 fix verification also shows `Server: "ARK-Test" has successfully started!` after the pdb self-heal path, confirming the success signal survives `ensure_modded_pdb()`. `entrypoint.sh` diff: `launch_exe="${LOADER_EXE}"` set in the `ENABLE_ASAAPI=1` branch; Xvfb started and dual-condition-verified (socket + `kill -0`) before `proton run "${launch_exe}" "${query}" ${flags}`; identical `${query}`/`${flags}` as the vanilla path.
Reason: The evidence contains the verbatim ASA engine line `Server has completed startup and is now advertising for join` from a real boot under `AsaApiLoader.exe` — the exact M1 success signal the AC names. The round-2 self-heal receipt also produces the success signal, confirming the added `ensure_modded_pdb()` does not regress startup. The round-3 Xvfb liveness hardening adds a `kill -0` process-alive check and `xvfb_dead` flag to the existing socket check; the happy path (Xvfb up, socket present, process alive) continues to the `proton run` launch and is proven by the dell receipt. AC semantically matched.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild"
Verdict: MET
Evidence: `phase4-runtime-evidence.md` §AC3 — `ENABLE_ASAAPI=0 docker compose up -d` (same image `5a83628ac1df`, no rebuild): `[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [vanilla]`, `Server: "ARK-Test" has successfully started!`, `Full Startup: 48.05 seconds`, `grep "API was successfully loaded" → 0`. `entrypoint.sh` diff `else` branch: `launch_exe="${SERVER_EXE}"` (`ArkAscendedServer.exe`), skips Xvfb entirely (`xvfb_pid` stays `""`), skips `ensure_modded_pdb()` call (guarded by `[[ "${ENABLE_ASAAPI}" == "1" ]]`), logs `[vanilla]`; `proton run "${launch_exe}"` with identical `${query}`/`${flags}`. Pdb-shed in `install_or_update()` conditional: `if [[ "${ENABLE_ASAAPI}" != "1" ]]` → vanilla fresh installs still shed the pdb as M1 did. `docker-compose.yml` diff: `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` plumbed to `the-island.environment`. `.env.test.example` / `.env.prod.example` diffs: `ENABLE_ASAAPI=1` with kill-switch comment documented. Round-3 delta: Xvfb/pdb hardening is `ENABLE_ASAAPI=1`-branch-only; the `else` (vanilla) branch is structurally untouched — round-3 changes cannot regress AC3.
Reason: The evidence shows a live vanilla launch from the same image with no rebuild — zero AsaApi load confirmed by grep, server starts and advertises. The diff's `else` branch is clean: no Xvfb, no `ensure_modded_pdb()`, `SERVER_EXE` as the binary, identical query/flags. The `[vanilla]` log tag and grep-0 result together prove rollback is byte-for-byte M1 behavior. The round-3 changes are guarded inside the `ENABLE_ASAAPI=1` block and cannot affect the `else` path. AC semantically matched.
--- END AC ENTRY ---

### Overall Verdict

OVERALL VERDICT: PASS — all 3 AC are MET

### Required Fixes

None — all ACs MET.

### Bottom Line

Chief, round-3 is pure armor plating on the doors that round-2 already proved open. Size-floor on the pdb, liveness check on Xvfb — neither one touches the happy path the dell receipts documented. All 3 ACs MET, PASS carries to commit.
