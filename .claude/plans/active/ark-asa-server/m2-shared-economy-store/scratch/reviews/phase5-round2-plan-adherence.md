# Plan Adherence Review: m2-shared-economy-store Phase 5 Round 2

### Verdict: PASS

### Diff Scope
- Files changed: 10 (entrypoint.sh, docker-compose.yml, .env.test.example, .env.prod.example, README.md, Dockerfile, .gitignore, plugins-config/.gitkeep, notes.md, plan.md/state.md bookkeeping — last two excluded per coordinator instruction)
- Lines added/removed: +261 / -4 (total diff per `git diff 4f19274 --stat`); bookkeeping churn (plan.md 1 line, state.md 4 lines) excluded; Phase 5 content is approximately +256 / -0
- Diff source: `git diff 4f19274` (working tree vs Phase-4 commit 4f19274)

---

### Round 2 — Scope-Escape Resolution Check

**Primary BLOCK from Round 1**: `docker-compose.yml` `command: --default-authentication-plugin=mysql_native_password` on the `mariadb` service — undocumented content-level scope creep.

**Resolution**: The line has been **removed entirely** from the working tree. Confirmed by:
1. `git diff 4f19274 -- docker-compose.yml` — no `command:` key appears in the mariadb service block or anywhere near it in the diff.
2. `grep -n "command:" docker-compose.yml` — the sole match is line 13 (`command: sysctl -w vm.max_map_count=262144`), which is the pre-existing `sysctl` init service. The MariaDB service has zero `command:` entries.

Coordinator's stated reason for removal: empirically confirmed no-op on MariaDB 11.4 (MariaDB 11.4 already defaults `arkshop` user to `mysql_native_password`; the directive was added by a prior chat for DataGrip, not by Phase 5; verified by direct probe). Removal is the correct resolution — the line had no functional effect and was undocumented scope creep regardless of its correctness.

**Entrypoint refactors cited by coordinator** (extracted `_inject_mysql_block`, added port guard): these are in-scope Step 2 implementation sub-components, not new scope creep:
- `_inject_mysql_block()` at entrypoint.sh:294 is an extracted helper for the `inject_plugin_db_config()` function mandated by Step 2 — clean internal decomposition within a single step's scope.
- Port guard at entrypoint.sh:354-356 is the fail-fast validation for `ARKSHOP_DB_PORT` before passing it to `jq tonumber` — part of Step 2's "fail fast on empty creds" requirement and the Quality gate's "Handles missing/empty creds explicitly."
- No lines were removed from entrypoint.sh (pure additions phase); "dropped a dead env tier" per coordinator refers to the mariadb `command:` removal from docker-compose.yml, not an entrypoint deletion.

---

### Step-by-Step Audit

**Step 1**: Decide the plugin-config host home: a host-bound dir (reuse `./config` or add `./plugins-config`) symlinked into `…/ArkApi/Plugins/<name>/` per the entrypoint.sh:62-69 pattern. Seed the default `config.json` on first boot if absent; never overwrite an existing one.

**MET** — `./plugins-config/` chosen as host home (plan-sanctioned Option B; documented as approach deviation #5). `setup_plugin_configs()` at `entrypoint.sh:254-289` implements the pattern: `mkdir -p "${host_root}"` + per-plugin `mkdir -p "${host_dir}"` → seed-if-absent guard `if [[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` → `cp "${plugin_dir}/config.json" "${host_dir}/config.json"` → `rm -rf "${plugin_dir}"` → `ln -sfn "${host_dir}" "${plugin_dir}"`. The seed-if-absent is explicit; never-overwrite is enforced by the `-f` guard. Host bind at `docker-compose.yml:83`: `./plugins-config:/home/container/plugins-config`. `plugins-config/.gitkeep` anchors the host dir (scope deviation #3). All sub-actions of Step 1 are complete.

**Step 2**: entrypoint: inject DB secrets into ArkShop + Permissions `config.json` at boot from the `MARIADB_*`/dedicated `ARKSHOP_DB_*` env (set `UseMysql=true`, `MysqlHost=mariadb`, `MysqlUser`, `MysqlPass`, `MysqlDB`, `MysqlPort=3306`). Use a placeholder-substitution or `jq` approach; never echo the password.

**MET** — `_inject_mysql_block()` (extracted helper, `entrypoint.sh:294-330`) + `inject_plugin_db_config()` (`entrypoint.sh:332-378`) together deliver Step 2. Uses `jq --arg` for all six Mysql fields (`UseMysql=true`, `MysqlHost`, `MysqlUser`, `MysqlPass`, `MysqlDB`, `MysqlPort` via `tonumber`). Fail-fast on missing/empty `ARKSHOP_DB_HOST/USER/PASS/NAME` at `entrypoint.sh:342-350`; port numeric guard at `entrypoint.sh:352-355`. Password never echoed — log line at `entrypoint.sh:368` explicitly omits it. Permissions plugin injected conditionally on `jq -e 'has("Mysql")'` check at `entrypoint.sh:371-375`. ARKSHOP_DB_* fallback chain from MARIADB_* env at `entrypoint.sh:19-23`. `jq` added to Dockerfile apt layer (scope deviation #1). All sub-actions complete.

**Step 3**: Look up + add the **ASA API Utils** CurseForge mod ID to `MODS` (entrypoint already passes `-mods`). Record the ID in plan notes.

**MET** — Mod ID 955333 auto-appended inside `if [[ "${ENABLE_ASAAPI}" == "1" ]]` at `entrypoint.sh:407-413` with de-duplication: empty-MODS sets `MODS="955333"`; non-empty checks `",${MODS},"` for the ID before appending. ID recorded in `notes.md` Phase 5 section. Both `.env.*.example` carry the comment "ASA API Utils (955333) is added automatically when ENABLE_ASAAPI=1." (approach deviation #7 — gating inside ENABLE_ASAAPI=1 is stricter than baking into MODS default; documented).

**Step 4**: compose/env: add the plugin-config bind + any `ARKSHOP_DB_*` vars to `.env.*.example`.

**MET** — `docker-compose.yml:83` adds `./plugins-config:/home/container/plugins-config` bind. `docker-compose.yml:65-80` wires `MARIADB_DATABASE/USER/PASSWORD` and `ARKSHOP_DB_*` into the `the-island.environment` block. Both `.env.test.example` and `.env.prod.example` gain `# --- ArkShop DB connection (M2+) ---` block with commented-out `ARKSHOP_DB_HOST/PORT/NAME/USER/PASS` overrides + explanatory comment. Both example files also get `# ASA API Utils (955333) is added automatically when ENABLE_ASAAPI=1` comment alongside the MODS line. All sub-actions complete.

**Step 5**: Boot on dell; verify `ArkApi.log` has no `Singleton not found` and no DB connection error; run a points/shop action (RCON or in-game) and confirm a row appears in MariaDB.

**PARTIAL (coordinator-acknowledged pending action, not a skipped executor step)** — All code that would satisfy this step at runtime is complete. `phase5-runtime-evidence.md` shows ACs AC1/AC3/AC4/AC5 as "(pending dell boot)" with exact verification commands scaffolded. Per coordinator instruction: the dell boot is a coordinator-driven runtime verification step, not an executor omission. Classifying PARTIAL rather than MISSING because the code deliverable is done and the runtime receipt is explicitly pending a coordinator action. This PARTIAL is acknowledged and non-blocking per coordinator pre-authorization.

**Step 6**: README: add a "Shared store" section — plugin-config edit loop, how points/shop work, where the data lives.

**MET** — `README.md` gains `## Shared store (ArkShop + points economy)` section covering all three sub-topics: plugin config edit loop (directory listing with `./plugins-config/ArkShop/config.json` and `Permissions/config.json`, edit-restart cycle), DB credentials injection explanation, "where economy data lives" with `docker compose exec mariadb` query command, and Required mod section (mod ID 955333, auto-append behavior). All plan-specified sub-topics present.

---

### Scope Audit

**Files (expected scope) per plan Phase 5**: `entrypoint.sh`, `docker-compose.yml`, `config/**` (or a new `plugins-config/` bind), `.env.test.example`, `.env.prod.example`, `README.md`

Files touched by diff (excluding prior-phase bookkeeping plan.md + state.md):

- `entrypoint.sh`: **IN SCOPE** — primary Phase 5 file; `setup_plugin_configs()` + `_inject_mysql_block()` + `inject_plugin_db_config()` + MODS auto-append + ARKSHOP_DB_* env defaults.
- `docker-compose.yml`: **IN SCOPE** — Phase 5 expected scope; adds plugins-config bind + ARKSHOP_DB_*/MARIADB_* env vars to the-island environment block. The Round 1 BLOCK item (`command: --default-authentication-plugin`) is **gone** — confirmed absent.
- `.env.test.example`: **IN SCOPE** — Phase 5 expected scope; ARKSHOP_DB_* override block + mod ID comment added.
- `.env.prod.example`: **IN SCOPE** — Phase 5 expected scope; same ARKSHOP_DB_* override block + mod ID comment added.
- `README.md`: **IN SCOPE** — Phase 5 expected scope; "Shared store" section added.
- `Dockerfile`: **DEVIATION (DOCUMENTED)** — scope deviation #1 in phase5-deviations.md: `jq` added to apt layer because `inject_plugin_db_config()` requires jq (not in base image). Rationale sound.
- `.gitignore`: **DEVIATION (DOCUMENTED)** — scope deviation #2 in phase5-deviations.md: `plugins-config/**` + `!plugins-config/.gitkeep` added to prevent committing runtime-injected DB password. Rationale sound; required by Quality gate.
- `plugins-config/.gitkeep`: **DEVIATION (DOCUMENTED)** — scope deviation #3 in phase5-deviations.md: empty anchor so bind-mount dir exists pre-`up`, preventing root-owned dir creation blocking the non-root container user.
- `notes.md`: **DEVIATION (DOCUMENTED)** — scope deviation #4 in phase5-deviations.md: Phase 5 churn entries; standard established plan practice.

**Files in expected scope NOT touched**: `config/**` — intentional; plan offered `./config` OR `./plugins-config/` as plugin-config home; executor chose `./plugins-config/` (documented approach deviation #5), making `config/**` a by-design non-touch.

**Round 1 BLOCK status**: RESOLVED — the `command: --default-authentication-plugin=mysql_native_password` entry on the mariadb service that caused the Round 1 BLOCK is **not present** in the working-tree diff. Scope-escape from Round 1 is closed.

---

### Approach Audit

**Approach hint 1**: "reuse `./config` or add `./plugins-config`" (Step 1) → **MATCHED (DOCUMENTED deviation #5)** — executor chose `./plugins-config/`. Plan explicitly offered this as Option B; documented in phase5-deviations.md with separation-of-concerns rationale. Non-blocking.

**Approach hint 2**: "Use a placeholder-substitution or `jq` approach" (Step 2) → **MATCHED (DOCUMENTED deviation #6)** — jq with `--arg`. Plan explicitly sanctioned both options; jq chosen for safety with arbitrary password characters (special chars, backslashes). `tonumber` coercion keeps MysqlPort integer-typed. Documented in phase5-deviations.md. Non-blocking.

**Approach hint 3**: "never echo the password" (Step 2) → **MATCHED** — `inject_plugin_db_config()` log line at the end of the ArkShop injection block explicitly reads "Password intentionally omitted from the log line above." Password passed only via `jq --arg pass "${ARKSHOP_DB_PASS}"` (transiently in cmdline, not logged).

**Approach hint 4**: "per the entrypoint.sh:62-69 pattern" (Step 1) → **MATCHED** — `setup_plugin_configs()` mirrors the pattern: `mkdir -p`, seed-if-absent, `rm -rf` existing dir, `ln -sfn`. Identical structure to the existing config-on-host symlink block.

**Approach hint 5**: mod ID in MODS (Step 3) — gating inside ENABLE_ASAAPI=1 → **MATCHED (DOCUMENTED deviation #7)** — auto-append inside `if [[ "${ENABLE_ASAAPI}" == "1" ]]` with de-duplication. Stricter than baking into MODS default (avoids contaminating vanilla boots). Documented. Non-blocking.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

- **"ArkApi.log shows ArkShop + Permissions loaded with NO `Singleton not found` and NO MySQL connection error"**: Unclear / Pending — code delivers mod 955333 auto-append (required for no Singleton not found) and DB config injection (required for no MySQL error). `phase5-runtime-evidence.md` §AC1 shows "(pending dell boot)." Cross-flag: acceptance-verifier must verify on dell boot receipt. Code path complete.

- **"ArkShop/Permissions config.json on the volume has `UseMysql=true` + `MysqlHost=mariadb` + creds, written at boot from `.env` (password NOT in git or container logs)"**: Yes (code-complete, statically verifiable) — `inject_plugin_db_config()` sets all six Mysql fields via jq; fail-fast on empty creds; password omitted from logs. `.gitignore` excludes `plugins-config/**`. `phase5-runtime-evidence.md` §AC2 has runtime verification commands; result pending dell boot.

- **"A points/shop action persists a row to MariaDB — verified by querying the DB"**: No visible diff content proves end-to-end persistence — requires live server + RCON command + DB query. `phase5-runtime-evidence.md` §AC3 pending. Cross-flag: acceptance-verifier must verify on dell boot receipt.

- **"Plugin config.json is edit-on-host and NOT clobbered by the boot sync"**: Yes (code-complete, statically verifiable) — `setup_plugin_configs()` seed-if-absent guard (`! -f "${host_dir}/config.json"`) + symlink means host file is never overwritten; warm-boot: `deploy_plugins()` removes symlink (not host target), `setup_plugin_configs()` re-symlinks to same host file. `phase5-runtime-evidence.md` §AC4 pending.

- **"ASA API Utils mod ID recorded + the mod downloaded under the game's mods dir"**: Partial — mod ID 955333 recorded in notes.md + .env.*.example comments + entrypoint.sh comment; download verification requires dell boot. `phase5-runtime-evidence.md` §AC5 pending. Cross-flag.

- **"README 'Shared store' section added (config loop + data location)"**: Yes — `README.md` gains `## Shared store (ArkShop + points economy)` with config edit loop, DB credentials section, "where economy data lives" with query command, Required mod section. MET statically.

---

### Out-of-Scope Content Creep

**Round 1 finding** (`docker-compose.yml` `command: --default-authentication-plugin=mysql_native_password`): **RESOLVED** — the line has been removed entirely. No trace in working-tree diff. The only `command:` in docker-compose.yml is the pre-existing `sysctl` init service at line 13.

**`_inject_mysql_block()` extracted helper**: Coordinator cited this as a refactor. It is NOT scope creep — it is internal decomposition of Step 2's `inject_plugin_db_config()` logic into a sub-function called twice (for ArkShop config and Permissions config). The helper is called exclusively from `inject_plugin_db_config()` which is the Step 2 deliverable. No independent production exposure, no functionality beyond what Step 2 mandates.

**Port guard at entrypoint.sh:352-355**: Coordinator cited this as a new addition. It is NOT scope creep — it is the "Handles missing/empty creds explicitly (fail fast, clear message)" requirement from the Phase 5 Quality gate, and a natural consequence of passing `ARKSHOP_DB_PORT` to `jq tonumber` (which errors on non-numeric input). Mechanical pre-validation of a jq argument is part of Step 2's implementation.

**None observed** beyond the already-resolved Round 1 finding.

---

### Deviation Rationale Phrase Check

Checking all 7 documented deviations from phase5-deviations.md against the `no-duct-tape.md` `## Phrases That Trigger Review` list (mechanical substring match, case-insensitive):

Banned phrases scanned: "acceptable for now", "works in the current state", "fine until we add X", "executor will figure it out at code time", "we can revisit when Y happens", "current code only has one consumer", "we'll make it configurable later", "this case can't happen yet", "the existing X is close enough", "intentional approximation", "minor — acceptable to leave", "good enough for the MVP", "build the simple version now, do it right later", "rebuild this when X lands", "tear this out and redo it once X exists", "before requirement X exists there'll be an issue", "let's just scope this milestone to X", "narrow this to just X".

- **Deviation #1** (Dockerfile jq): "jq required for safe JSON mutation; not in base image; added to Dockerfile apt layer (only place to bake it)." — No banned phrases detected.
- **Deviation #2** (.gitignore plugins-config): "plugins-config/** gitignored (except .gitkeep) so the runtime-injected DB password in ArkShop/config.json can't be accidentally committed." — No banned phrases detected.
- **Deviation #3** (plugins-config/.gitkeep): "plugins-config/.gitkeep created so the host bind-mount dir exists pre-`up`, preventing root-owned dir creation that would block the non-root container user." — No banned phrases detected.
- **Deviation #4** (notes.md): "notes.md updated with Phase 5 execution decisions (established churn-log pattern for this plan)." — No banned phrases detected.
- **Deviation #5** (./plugins-config/ approach): "separate concerns (engine INI vs plugin config.json), distinct target paths, cleaner operator model." — No banned phrases detected.
- **Deviation #6** (jq --arg approach): "safe for special chars in passwords; tonumber coercion keeps MysqlPort integer-typed." — No banned phrases detected.
- **Deviation #7** (auto-append 955333 MODS): "avoids adding the mod to vanilla boots; prevents doubled entry if operator already lists it." — No banned phrases detected.

All rationales clean — no banned phrases detected.

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

`Scope-escape: CLEAR — no escapes detected; all diff work falls within the declared Scope Boundary`

The Round 1 scope escape (`command: --default-authentication-plugin=mysql_native_password`) has been removed. No new scope escapes introduced. All content in the current diff is either:
- In-scope per Phase 5's declared `Files (expected scope)` and `Scope Boundary`, or
- Documented in phase5-deviations.md as a scope or approach deviation with a stated rationale.

The coordinator's cited entrypoint changes (`_inject_mysql_block` extraction, port guard) are sub-components of Step 2's declared implementation scope, not independent capabilities.

---

### Required Fixes (BLOCK summary — empty if PASS)

None — all plan steps MET (Step 5 PARTIAL is coordinator-acknowledged pending runtime action, not a missing executor step) and scope respected.

---

### Bottom Line

Round 1's sole BLOCK — the undocumented `--default-authentication-plugin` directive — is gone, confirmed absent by diff and live grep. All seven documented deviations carry clean rationales, the extracted `_inject_mysql_block` helper and port guard are firmly inside Step 2's scope, and the runtime evidence scaffold correctly defers the dell boot to the coordinator. PASS, chief.
