# Plan Adherence Review: m2-shared-economy-store — CUMULATIVE (Phases 1–5)

### Verdict: PASS

Cumulative end-of-plan audit across all 5 phases. Diff: `git diff 873509a..HEAD`, ignoring
`.claude/plans/**/scratch/**` + `.claude/state.md` per instruction.

### Diff Scope
- Files changed (excluding ignored scratch/state): ~18 source + doc files.
- Production/contract surface: `Dockerfile` (+46), `entrypoint.sh` (+411/-? net +~400),
  `docker-compose.yml` (+48), `.env.test.example` (+18), `.env.prod.example` (+18),
  `README.md` (+54), `.gitignore` (+8), `plugins-config/.gitkeep` (new empty),
  `.claude/design-sources.md` (new +8), `.claude/rules/build-time-vs-runtime.md` (+9/-1),
  `docs/internal/decisions/0001-db-engine-mariadb.md` (new +77),
  `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` (new +128).
- Diff source: `git diff 873509a..HEAD` (all 5 phases committed: 21fe5a8, 1f9f1b7, 29735d2, 4f19274, 03264a5).

### Step-by-Step Audit

#### Phase 1 — MariaDB service + secrets (7 steps)
1. Add `mariadb` service (`mariadb:11.4`, MARIADB_* env from `.env`, `ark-db:/var/lib/mysql`, no host port, `restart: unless-stopped`): **MET** — `docker-compose.yml:18-40`. All env vars present; `MARIADB_ROOT_PASSWORD`/`MARIADB_PASSWORD` use `:?` required-guard, DB/USER use `:-arkshop` default. No `ports:` key (internal-only). `restart: unless-stopped` present.
2. Healthcheck (`healthcheck.sh --connect --innodb_initialized`): **MET** — `docker-compose.yml:28-33`, interval 10s/timeout 5s/retries 5/start_period 30s.
3. Extend `the-island.depends_on` with `mariadb: service_healthy` keeping `sysctl: service_completed_successfully`: **MET** — `docker-compose.yml:48-53`. Both conditions present.
4. Add `ark-db` to `volumes:`: **MET** — `docker-compose.yml:95-96` (`ark-db: name: ark-db`).
5. Four `MARIADB_*` in both `.env.*.example` with placeholders + comment: **MET** — both files carry the four vars + "Real values live in .env… gitignored" comment.
6. README "Database" wording → MariaDB: **MET** — `README.md` `## Database` section + roadmap line `MySQL`→`MariaDB`.
7. ADR `0001-db-engine-mariadb.md` (MySQL ≥8.0.28 rejection, rejected alternatives): **MET** — file exists (+77), per AC1.5 evidence.

#### Phase 2 — Bake plugins + entrypoint deploy (4 steps)
1. Resolve distribution channel first (record pinned versions): **MET** — `Dockerfile:32-34` pins `ASAAPI_VERSION=1.21`/`ARKSHOP_VERSION=1.4`/`PERMISSIONS_VERSION=1.1`; versioned `?version=${ARG}` URLs (ark-server-api.com), recorded in notes §distribution-channel.
2. Dockerfile `ARG` pins + download/unzip into `/opt/asaapi/` (DLL==folder), `chown container`: **MET** — `Dockerfile:35-53`. `cp -r ArkApi` carries Permissions; explicit root-file cp for loader + DLLs; `find … -name '*.pdb' -delete`; `chown -R container:container`.
3. `deploy_plugins()` after install, before launch, clean-replace, don't touch game files or configs: **MET** — `entrypoint.sh:73-148`. Stash configs → `rm -rf` AsaApi-owned paths → `cp -r` fresh → restore configs → seed framework config if absent. Negative-scope rm list (no game files).
4. Keep launch as `ArkAscendedServer.exe` this phase: **MET** — launch flip deferred to Phase 4; Phase 2 commit (1f9f1b7) left launch line unchanged.

#### Phase 3 — VC++ redist at runtime + ADRs + registry (6 steps)
1. Dockerfile download `VC_redist.x64.exe` to `/opt/vcredist/`, `chown container`: **MET** — `Dockerfile:65-71` (`aka.ms/vs/16/release/vc_redist.x64.exe`).
2. `install_vcredist()` gating skip on actual DLLs (not bare marker), `proton run … /quiet /norestart`, after install before launch: **MET** — `entrypoint.sh:150-216`. Conjunctive fast-path `[[ -f marker && -f msvcp && -f vcrt && -f vcrt1 ]]`; survives pfx reset.
3. Verify three runtime DLLs landed, fail fast: **MET** — `entrypoint.sh` `missing[]` array + `exit 1` with named DLLs; `|| rc=$?` captures benign 3010/1638.
4. Amend `build-time-vs-runtime.md` VC++ row → entrypoint + rationale note: **MET** — rule diff: row changed `Dockerfile`→`entrypoint` (volume-backed prefix) + "Note on VC++ redist placement" paragraph citing the 3-question test + ADR 0002.
5. Write ADR `0002`: **MET** — file exists (+128), 3-question test applied to VC++ AND plugins.
6. Bootstrap `.claude/design-sources.md` registering rule + ADR 0001/0002 `[locked]`: **MET** — `.claude/design-sources.md` (new +8), all three `[locked]`, all globs resolve to real files (verified: both ADRs present in `docs/internal/decisions/`).

#### Phase 4 — Flip launch to AsaApiLoader (4 steps)
1. `ENABLE_ASAAPI` default `:= 1` + `LOADER_EXE`: **MET** — `entrypoint.sh:27` (`: "${ENABLE_ASAAPI:=1}"`), `entrypoint.sh:36` (`LOADER_EXE=…/AsaApiLoader.exe`).
2. At launch: if `ENABLE_ASAAPI==1` → loader, else vanilla; same query/flags: **MET** — `entrypoint.sh:448-495` single-sources `launch_exe`; `proton run "${launch_exe}" "${query}" ${flags}`. Identical args both branches.
3. compose `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` + both `.env.*.example`: **MET** — `docker-compose.yml:64`; both env examples carry `ENABLE_ASAAPI=1` + kill-switch comment.
4. Boot on dell with `ENABLE_ASAAPI=1`, confirm AsaApi init: **MET** — `phase4-runtime-evidence.md` §AC1 dell receipt: `API was successfully loaded` + ArkShop V1.4 + Permissions V1.1 loaded.

#### Phase 5 — ArkShop ↔ MariaDB config injection + mod 955333 (6 steps)
1. Plugin-config host home, seed-if-absent, never overwrite: **MET** — `setup_plugin_configs()` `entrypoint.sh:266-310`. Symlinks ONLY `config.json` (preserves DLL); seed-if-absent guard. Chose `./plugins-config` (approach deviation #5, documented).
2. Inject DB secrets into ArkShop + Permissions config.json, never echo password: **MET** — `_inject_mysql_block()` + `inject_plugin_db_config()` `entrypoint.sh:312-410`. jq `--arg` (approach deviation #6, documented), `UseMysql=true`/`MysqlHost`/`MysqlUser`/`MysqlPass`/`MysqlDB`/`MysqlPort=tonumber`, fail-fast on empty creds, password omitted from logs.
3. Look up + add ASA API Utils mod ID to `MODS`, record it: **MET** — mod `955333` auto-appended in `ENABLE_ASAAPI=1` branch with de-dup (approach deviation #7, documented); recorded in notes/README/entrypoint.
4. compose/env plugin-config bind + `ARKSHOP_DB_*` vars: **MET** — `docker-compose.yml:83` (`./plugins-config` bind) + `ARKSHOP_DB_*` env block; both `.env.*.example` carry commented `ARKSHOP_DB_*` overrides.
5. Boot on dell, no `Singleton not found`/no DB error, points persist: **MET** — `phase5-runtime-evidence.md` §AC1/AC3 dell receipts: ArkShop+Permissions loaded, tables created, RCON `SetPoints` → DB row 0→250.
6. README "Shared store" section: **MET** — `README.md` `## Shared store` (edit loop + DB creds + data location + required mod 955333).

**Cumulative step tally: 27/27 MET. Zero MISSING, zero PARTIAL, zero DEVIATED-SILENT.**

### Scope Audit

Expected-scope across all phases (union of per-phase Files blocks): `Dockerfile`, `entrypoint.sh`,
`docker-compose.yml`, `.env.test.example`, `.env.prod.example`, `config/**` / `plugins-config/`,
`README.md`, `.claude/rules/build-time-vs-runtime.md`, `docs/**`, `.claude/design-sources.md`.

File-by-file:
- `Dockerfile`: IN SCOPE (Phase 2/3 expected). Note: `jq` added in the apt layer is a Phase 5 need — DEVIATION (DOCUMENTED), phase5-deviations Scope #1.
- `entrypoint.sh`: IN SCOPE (Phases 2/3/4/5).
- `docker-compose.yml`: IN SCOPE (Phases 1/4/5).
- `.env.test.example` / `.env.prod.example`: IN SCOPE (Phases 1/4/5).
- `README.md`: IN SCOPE (Phases 1/5).
- `.claude/rules/build-time-vs-runtime.md`: IN SCOPE (Phase 3).
- `.claude/design-sources.md`: IN SCOPE (Phase 3).
- `docs/internal/decisions/0001-db-engine-mariadb.md`: IN SCOPE (Phase 1).
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`: IN SCOPE (Phase 3).
- `plugins-config/.gitkeep`: DEVIATION (DOCUMENTED) — phase5-deviations Scope #3 (host bind-mount dir anchor; prevents root-create). Falls under Phase 5's `config/** (or a new plugins-config/ bind)` Files entry — arguably IN SCOPE.
- `.gitignore` (plugins-config rule, lines 6-10): DEVIATION (DOCUMENTED) — phase5-deviations Scope #2 (prevents committing injected DB password). Reasonable, tied to a Phase 5 quality gate.
- `.gitignore` (`.claude/plans/**/status.json` rule, lines 11-12): **DEVIATION (UNDOCUMENTED)** — landed in the Phase 1 commit (21fe5a8) but is entirely unrelated to Phase 1 (MariaDB) or to any M2 phase. It is a Tessa-kanban heartbeat-overlay ignore (`/execute-plan` tooling glue). No phase's Files block lists it; no deviation scratch or notes entry justifies it. Not a code/behavior risk — it is `.claude/` tooling glue, not part of the server stack — so it is flagged as a CONCERN, not a hard BLOCK (see Bottom Line). The honest cumulative finding: it is silent scope-creep that slipped past Phase 1's individual gate.

Files in expected scope NOT touched:
- `config/**`: not modified — intentional. Phase 5 chose a separate `./plugins-config` host bind (approach deviation #5, documented) rather than reusing `./config`. The plan Step 1 explicitly offered "reuse `./config` or add `./plugins-config`" — both were sanctioned. Not an anomaly.

### Approach Audit

- **"DB engine must be MariaDB" (`mariadb:11.4`)** → MATCHED — `docker-compose.yml:19` `image: mariadb:11.4`.
- **"MariaDB internal to the compose network (no host port)"** → MATCHED — no `ports:` key on the mariadb service.
- **"bake plugin binaries to `/opt` + entrypoint syncs onto Win64 (mirror steamclient.so pattern)"** → MATCHED — `/opt/asaapi` bake + `deploy_plugins()` runtime sync; precedent honored.
- **"clean-replace (stash configs → rm AsaApi-owned → cp fresh → restore), NOT rsync --delete"** (Decision Ledger #12) → MATCHED — `deploy_plugins()` implements exactly stash/rm/cp/restore; no rsync.
- **"gate VC++ skip on actual DLLs, not a bare marker"** → MATCHED — conjunctive `[[ -f marker && -f <3 dlls> ]]`.
- **"VC++ install → entrypoint (volume-backed prefix, 3-question test)"** → MATCHED — installer baked `/opt/vcredist`, `install_vcredist()` acts on the volume prefix; rule doc amended to match (no rule/code contradiction).
- **"same query/flags for loader and vanilla (no drift)"** → MATCHED — single `launch_exe` var, identical `proton run "${launch_exe}" "${query}" ${flags}`.
- **"ENABLE_ASAAPI=0 = byte-for-byte M1 vanilla path"** → MATCHED — vanilla branch sets `launch_exe="${SERVER_EXE}"`, skips Xvfb; dell AC3 receipt confirms AsaApi absent.
- **"jq for JSON injection (plan offered placeholder-substitution OR jq)"** → MATCHED — jq `--arg` chosen; plan explicitly permitted jq (approach deviation #6 documents the choice-of-two).
- **"seed-if-absent plugin config, never overwrite operator edits"** → MATCHED — `setup_plugin_configs()` + `deploy_plugins()` both guard seed-if-absent.

No silent approach deviations. All deviations from named hints are documented in phase scratch + plan Decision Ledger.

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)
Every AC across all 5 phases has visible diff content AND (Phases 1/4/5) live runtime receipts:
- Phase 1 ACs (5): Yes — compose mariadb service + `phase1-runtime-evidence.md`.
- Phase 2 ACs (5): Yes — Dockerfile bake + `deploy_plugins()` (static-evidence ceiling, runtime confirmed Phase 4 dell boot).
- Phase 3 ACs (4): Yes — `install_vcredist()` + ADR 0002 + registry (runtime confirmed Phase 4 dell).
- Phase 4 ACs (3): Yes — launch flip + `phase4-runtime-evidence.md` dell receipts.
- Phase 5 ACs (6): Yes — injection functions + `phase5-runtime-evidence.md` dell receipts (RCON SetPoints → DB row).
All ACs MET per plan checkboxes; acceptance-verifier owns evidence-depth — no gaps visible at the diff level.

### Out-of-Scope Content Creep
- `.gitignore` `.claude/plans/**/status.json` rule: Silent (undocumented) — see Scope Audit. The only content-level creep found in the cumulative diff. Classified CONCERN (tooling glue, no server-stack risk), not BLOCK.
- Everything else: in-scope or documented. The `build-time-vs-runtime.md` table amendment and `## Design Divergences` launch-row entry are plan-sanctioned (Phase 3 AC + plan Design Divergences table). No "while I'm here" refactors of unrelated functions found in any in-scope file.

### Deviation Rationale Phrase Check
Mechanical grep of all documented deviation rationales (phase1–5 deviations scratch + plan Decision Ledger + Design Divergences) against `no-duct-tape.md` "Phrases That Trigger Review":
- All Phase 5 rationales (scope #1-4, approach #5-7): No banned phrases detected.
- Plan Design Divergences (Phase 3→4 launch-row): contains "**Named cost:**" + "Hard phase-dependency, not duct tape" — explicitly names the cost and reversal trigger; no banned framing.
- Decision Ledger #12 (clean-replace): No banned phrases.
- Phase 2 AC4 note "flagged for a later hardening, outside Phase-2 v1.21-pinned scope": borderline — "outside … scope" describes a real version-pinned boundary, not an "acceptable for now" defer; the root-DLL-add-then-drop case is genuinely impossible under the v1.21 pin. NOT a banned phrase (no "acceptable"/"for now"/"revisit when"). Noted for sibling awareness only.

All rationales clean — no banned phrases detected.

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)
`Scope-escape: CLEAR — no cross-milestone escapes detected; all diff work falls within the declared Scope Boundaries of Phases 1–5, and every Scope Boundary capability string maps to an m2-shared-economy-store-owned ledger row.`

(The one undocumented file-creep — `.gitignore` status.json line — is NOT a cross-milestone over-reach: it owns no ledger capability and is `/execute-plan` tooling glue, not server-stack work. It is surfaced as an undocumented-scope-creep CONCERN under Scope Audit / Out-of-Scope Content Creep, per Section 7's note that the only Sections-2/5 overlap case is the unused-helper / undocumented-creep one. No ledger ownership to adjudicate.)

### Required Fixes (BLOCK summary)
None — all 27 plan steps MET and scope respected (one undocumented `.gitignore` tooling-glue line flagged as CONCERN, not BLOCK).

### Bottom Line
27 of 27 steps across all five phases landed clean, chief — MariaDB, baked plugins, runtime VC++, the launcher flip, and the ArkShop↔MariaDB wiring all match the plan, all deviations documented, all docs deliverables (ADR 0001/0002, design-sources registry, README) present and the registry globs resolve. The one wart: a `.claude/plans/**/status.json` gitignore line snuck in on the Phase 1 commit with zero attribution — it's harmless Tessa-kanban glue, not server-stack code, so it's a CONCERN not a BLOCK, but it's silent creep and you should know it rode in unannounced.
