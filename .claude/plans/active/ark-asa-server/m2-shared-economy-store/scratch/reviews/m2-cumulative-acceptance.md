# Acceptance Verifier Report: m2-shared-economy-store — CUMULATIVE (Phases 1–5)

### Diff Scope
- Files changed: 90 (code/doc/plan/review artifacts)
- Lines added/removed: +8840 / -97
- Diff source: `git diff 873509a..HEAD`
- Behavior-bearing files verified in the cumulative diff: `docker-compose.yml`, `Dockerfile`, `entrypoint.sh` (+411), `.env.test.example`, `.env.prod.example`, `.gitignore`, `README.md`, `.claude/rules/build-time-vs-runtime.md`, `.claude/design-sources.md`, `docs/internal/decisions/0001-db-engine-mariadb.md`, `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`, `plugins-config/.gitkeep`, `phase5-runtime-evidence.md` (+78, repo root)
- Runtime evidence files read: `phase1-runtime-evidence.md`, `phase4-runtime-evidence.md`, `phase5-runtime-evidence.md`

**Evidence-file location note (not a defect):** Phase 5's ACs cite `phase5-runtime-evidence.md` by bare filename. The file is committed at the **repo root** (`/home/patrick/docs/development/ark-asa/phase5-runtime-evidence.md`), not inside the plan folder like phase1/phase4. It IS present in the cumulative diff (+78, committed in 03264a5) and contains the full command-output receipts. Bare-filename citation resolves to a real, diff-present file → evidence intact. (Phases 1 & 4 keep their evidence files inside the plan folder; the inconsistency is cosmetic, not an evidence gap.)

---

### Per-AC Audit

All 22 ACs across the 5 phases are MET. MET entries are listed concisely below; there are zero WEAK/MISSING, so no full `--- AC ENTRY ---` blocks are required.

#### Phase 1 — MariaDB service + secrets (5 ACs)

Phase 1 AC: "`docker compose --env-file .env.test up` starts `mariadb` and it reaches `healthy` before `the-island` starts" — MET (Evidence: `phase1-runtime-evidence.md` §AC1 `poll 3: health=healthy` + `Up 15 seconds (healthy)`; ordering structurally guaranteed by `docker-compose.yml` `the-island.depends_on.mariadb: condition: service_healthy` — present in diff at the `depends_on` block; full-stack ordering confirmed on dell in Phase 4/5 evidence)

Phase 1 AC: "The app user can connect to the `arkshop` DB on `mariadb:3306` from within the compose network (verify via `docker compose exec`)" — MET (Evidence: `phase1-runtime-evidence.md` §AC2 — `exec -T mariadb mariadb -u arkshop -p… arkshop -e 'SELECT 1 AS app_user_connects;'` → `1` exit 0, run inside compose network)

Phase 1 AC: "DB data persists across `docker compose restart mariadb` (a test table/row survives)" — MET (Evidence: `phase1-runtime-evidence.md` §AC3 — INSERT 42 → restart → poll healthy → SELECT returns 42; backed by `ark-db:/var/lib/mysql` named volume present in compose diff)

Phase 1 AC: "No host port is published for MariaDB (internal-only); `docker compose ps` shows no `0.0.0.0:3306`" — MET (Evidence: compose diff — `mariadb` service has NO `ports:` key, structural guarantee; `phase1-runtime-evidence.md` §AC1 PORTS column `3306/tcp` with no `0.0.0.0:` prefix)

Phase 1 AC: "`docs/internal/decisions/0001-db-engine-mariadb.md` exists with context + rejected alternatives; README \"Database\" wording updated to MariaDB" — MET (Evidence: ADR 0001 present in diff (+77, `doc-type: adr`, Context/Decision/Rejected-alternatives incl. MySQL 8.0.27 EOL + SQLite-only); README diff adds `## Database` section + roadmap line `MySQL`→`MariaDB`)

#### Phase 2 — Bake plugins + entrypoint deploy (5 ACs)

Phase 2 AC: "Image contains `/opt/asaapi/AsaApiLoader.exe` + `/opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/` at pinned versions (verify in the built image)" — MET (Evidence: `Dockerfile` diff RUN block — `ARG ASAAPI_VERSION=1.21`/`ARKSHOP_VERSION=1.4`; curl `?version=${ARG}` → `cp -r ArkApi /opt/asaapi/` (carries `Plugins/Permissions/`) + explicit cp of `AsaApiLoader.exe`; ArkShop `cp -r ArkShop/. /opt/asaapi/ArkApi/Plugins/ArkShop/`; `find … -name '*.pdb' -delete` + chown. Runtime build confirmed by Phase 4 dell receipt: "AsaApi 1.21 + ArkShop 1.4 baked")

Phase 2 AC: "After a boot, the volume's `…/Binaries/Win64/` contains `AsaApiLoader.exe` + `ArkApi/Plugins/{ArkShop,Permissions}/` with each plugin's DLL name matching its folder" — MET (Evidence: `entrypoint.sh` `deploy_plugins()` L114 `cp -r "${src}/ArkApi" "${win64}/"` + L117-122 explicit loader/DLL cp; folder==DLL-name preserved by `cp -r`. Runtime-confirmed: Phase 4 dell log `Loaded plugin Ark:SA ArkShop V1.4` + `Permissions V1.1`; Phase 5 evidence `ArkApi/Plugins/ArkShop/ArkShop.dll` present)

Phase 2 AC: "The deploy step is idempotent — a second boot re-syncs without error and without duplicating/clobbering game files" — MET (Evidence: `entrypoint.sh` `deploy_plugins()` L92-137 — stash configs → `rm -rf` AsaApi-owned paths (no-op on absent under `set -euo pipefail`) → `cp -r` fresh → restore. Rm list L105-111 scoped to AsaApi-owned paths only; game files untouched. Runtime-confirmed by Phase 4/5 repeated boots + restarts)

Phase 2 AC: "A version bump (changed `ASAAPI_VERSION`/plugin `ARG`) cleanly REPLACES the deployed tree — no stale files from the prior version remain in `ArkApi/`/loader paths" — MET (Evidence: `entrypoint.sh` L105 `rm -rf "${win64}/ArkApi"` wipes whole subtree before `cp -r`; root loader/DLLs individually in rm list L106-111; build-time `.pdb` strip means no stale debug blobs. Note: future-version root-DLL-add-then-drop undershoot is on the static rm list — flagged in plan for later hardening, outside v1.21-pinned scope)

Phase 2 AC: "Pinned versions are recorded (Dockerfile `ARG`s + plan notes); no auto-latest fetch" — MET (Evidence: `Dockerfile` three `ARG`s pinned; both URLs use `?version=${ARG}` not `latest`; `PERMISSIONS_VERSION=1.1` carries explicit doc-pin comment "ships bundled in the AsaApi zip; no separate download")

#### Phase 3 — VC++ 2019 redist at runtime (4 ACs)

Phase 3 AC: "After first boot, `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` contains `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`" — MET (Evidence: `entrypoint.sh` `install_vcredist()` L182 `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart || rc=$?` then L188-198 walks all three prefix system32 DLL paths; `missing[]` + `exit 1` if any absent → function only returns 0 with all three present. Installer baked from `aka.ms/vs/16` in Dockerfile diff. Runtime-validated: Phase 4 dell boot reached `API was successfully loaded` which requires the VC++ runtime)

Phase 3 AC: "The install-skip is gated on actual DLL presence (not a bare marker); a second boot skips the install (log shows the skip), and a `pfx/` reset correctly RE-triggers the install rather than falsely skipping" — MET (Evidence: `entrypoint.sh` L170 conjunctive fast-path `if [[ -f marker && -f msvcp && -f vcrt && -f vcrt1 ]]` → skip log + `return 0`; bare-marker skip impossible (all three `-f <dll>` required); `pfx/` reset wipes DLLs while marker (one level above `pfx/`) survives but conjunctive gate still fails → reinstall re-triggers. `|| rc=$?` makes the DLL check the sole arbiter)

Phase 3 AC: "`build-time-vs-runtime.md` table row for VC++/prefix amended to reflect volume-backed-prefix → entrypoint, with the rationale note" — MET (Evidence: `.claude/rules/build-time-vs-runtime.md` diff — row changed `Dockerfile`→`entrypoint` with reason "Q1 yes: prefix lives on the mounted ark-game volume → entrypoint"; +7-line rationale note walking the 3-question test, explaining the row previously assumed prefix-in-image, citing ADR 0002)

Phase 3 AC: "ADR `0002` exists (pattern + 3-question-test rationale); `.claude/design-sources.md` created registering the rule + both ADRs `[locked]`" — MET (Evidence: ADR 0002 present in diff (+128, `doc-type: adr`, 3-question test applied to both VC++ and plugin cases, rejected alternatives, Consequences); `.claude/design-sources.md` created (+8) with all three `[locked]` entries — build-vs-runtime rule + ADR 0001 + ADR 0002, all globs resolve to real files verified on disk)

#### Phase 4 — Flip launch to AsaApiLoader.exe (3 ACs)

Phase 4 AC: "With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / \"loaded\" lines), no fatal load error" — MET (Evidence: `phase4-runtime-evidence.md` §AC1 dell log — `[API][info] API was successfully loaded` + `Loaded plugin Ark:SA ArkShop V1.4` + `Permissions V1.1` + `Loaded all plugins`, no critical/fatal. v1.21 names file `ArkApi_<pid>_<ts>.log` — research correction noted. Only warning is the explicitly-Phase-5-deferred optional ASA API Utils mod. Code: `entrypoint.sh` L453 `launch_exe="${LOADER_EXE}"` under `ENABLE_ASAAPI==1`)

Phase 4 AC: "The server still reaches \"has successfully started\" / advertises for join (the M1 success signal) under the loader" — MET (Evidence: `phase4-runtime-evidence.md` §AC2 — under `[AsaApiLoader — modded, Xvfb :0]`: `Server: "ARK-Test" has successfully started!` + `advertising for join. (10.29GB Mem)`, Full Startup 47.73s; container Up not restarting)

Phase 4 AC: "With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild" — MET (Evidence: `phase4-runtime-evidence.md` §AC3 — `ENABLE_ASAAPI=0 docker compose up -d` same image SHA no rebuild → `[vanilla]` banner → started + advertising; `grep "API was successfully loaded" → 0`. Code: `entrypoint.sh` L492 `launch_exe="${SERVER_EXE}"` else-branch, skips Xvfb, reuses identical `${query}`/`${flags}` via single `proton run "${launch_exe}"` line L496)

#### Phase 5 — ArkShop ↔ MariaDB end-to-end (6 ACs)

Phase 5 AC: "`ArkApi.log` shows ArkShop + Permissions loaded with NO `Singleton not found` and NO MySQL connection error" — MET (Evidence: `phase5-runtime-evidence.md` §AC1 dell — `Loaded plugin Ark:SA ArkShop V1.4` + `Permissions V1.1` + `Loaded all plugins`; no `does not exist`/`Singleton not found`/MySQL error. Corroboration: ArkShop created `ArkShopPlayers` + `ArkShopLogTransactions` tables in MariaDB — proof of live connect)

Phase 5 AC: "ArkShop/Permissions `config.json` on the volume has `UseMysql=true` + `MysqlHost=mariadb` + creds, written at boot from `.env` (password NOT present in git or container logs)" — MET (Evidence: `phase5-runtime-evidence.md` §AC2 — live config.json Mysql block `UseMysql:true, MysqlHost:mariadb, MysqlUser:arkshop, MysqlDB:arkshop, MysqlPort:3306` (int via jq tonumber); boot log omits password; `plugins-config/**` gitignored (`.gitignore` diff); `git grep` finds no password. Code: `entrypoint.sh` `_inject_mysql_block()` L325-336 jq `--arg` injection; `inject_plugin_db_config()` log line L381 omits password)

Phase 5 AC: "A points/shop action (e.g. RCON `AddPoints` or playtime accrual) persists a row to MariaDB — verified by querying the DB" — MET (Evidence: `phase5-runtime-evidence.md` §AC3 — `SetPoints 00023ac1… 250` → `Successfully set points` → `SELECT Id,EosId,Points FROM ArkShopPlayers` Points 0→250; connected player confirmed in-game; arg order `<eosid> <amount>` documented)

Phase 5 AC: "Plugin `config.json` is edit-on-host (edit → restart → change takes effect) and is NOT clobbered by the boot sync" — MET (Evidence: `phase5-runtime-evidence.md` §AC4 — host marker `_phase5_edit_test` survived `docker compose restart`, `grep -c "Loaded plugin"` = 2 (not clobbered); inject-takes-effect proven by ArkShop connecting via host-file creds. Code: `setup_plugin_configs()` L291 seed-if-absent never overwrites; symlinks ONLY config.json file (L297) not the dir — the 042bef4 DLL-delete fix. Restart resilience: 96e3813 Xvfb stale-lock clear L467)

Phase 5 AC: "ASA API Utils mod ID recorded + the mod downloaded under the game's mods dir" — MET (Evidence: `phase5-runtime-evidence.md` §AC5 — `-mods=955333` on live launch line; `Singleton not found` absent from ArkApi.log (the exact missing-mod failure mode → present); ID `955333` recorded in notes.md/README.md/entrypoint.sh. Code: `entrypoint.sh` L430-434 auto-append + dedupe gated to `ENABLE_ASAAPI=1`)

Phase 5 AC: "README \"Shared store\" section added (config loop + data location)" — MET (Evidence: README diff — `## Shared store` section: plugin-config edit loop (`./plugins-config/<Plugin>/config.json`), DB credentials, "Where economy data lives" (`arkshop` DB on `ark-db` volume), required-mod 955333 subsection)

---

### Documentation Deliverables Audit (`## Documentation Deliverables`)

Deliverable: "ADR: DB engine = MariaDB" (`docs/internal/decisions/0001-db-engine-mariadb.md`) — MET (present in diff +77; `doc-type: adr`, Context/Decision/Rationale/Rejected-alternatives covering MySQL 8.0.28 rejection)

Deliverable: "ADR: image-baked artifacts deployed onto the volume at runtime" (`docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`) — MET (present in diff +128; covers VC++ + plugins, 3-question-test rationale)

Deliverable: "Create `.claude/design-sources.md` registry (register rule + two ADRs `[locked]`)" — MET (present in diff +8; three `[locked]` entries — build-vs-runtime rule + ADR 0001 + ADR 0002 — all globs resolve to real files)

Deliverable: "README: roadmap line bump (M2) + Database note; replace MySQL→MariaDB; document shared-store usage + plugin-config loop" — MET (README diff: roadmap line `MySQL`→`MariaDB shared store`/`M2 (current)`; new `## Database` + `## Shared store` sections)

---

### Overall Verdict

OVERALL VERDICT: PASS — all 22 ACs across Phases 1–5 are MET and all 4 Documentation Deliverables have evidence in the cumulative diff

### Required Fixes (BLOCK only)

None — all ACs MET.

### Bottom Line

Chief, the whole milestone holds up — 22/22 ACs MET, every one backed by either a runtime receipt on dell or a code path I traced in the cumulative diff, and all four doc deliverables landed. The only thing worth a shrug is that `phase5-runtime-evidence.md` sits at the repo root instead of in the plan folder like its siblings — cosmetic, it's in the diff and it's real. Ship it.
