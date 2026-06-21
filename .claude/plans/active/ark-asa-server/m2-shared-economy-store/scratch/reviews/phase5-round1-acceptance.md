# Acceptance Verifier Report: m2-shared-economy-store Phase 5 Round 1

## Diff Scope
- Files changed: 10
- Lines added/removed: +240 / -4
- Diff source: `git diff 4f19274` (working tree vs Phase-4 BASE commit 4f19274; includes uncommitted Phase 5 work)

---

## Per-AC Audit (structured — coordinator parses this to write Evidence sub-bullets into plan file)

--- AC ENTRY ---
AC: "`ArkApi.log` shows ArkShop + Permissions loaded with NO `Singleton not found` and NO MySQL connection error"
Verdict: MISSING
Evidence: —
Reason: This AC requires a live dell boot with `ENABLE_ASAAPI=1` and mod 955333 loaded. No `ArkApi.log` output is present in the diff, the scratch directory, or any commit artifact for Phase 5. The `phase5-runtime-evidence.md` file does not exist in the diff at all (only `phase5-deviations.md` is present in scratch). The static diff supplies the wiring that SHOULD produce a clean log (inject_plugin_db_config() at entrypoint.sh:293-368 writes DB creds; 955333 is appended to MODS at entrypoint.sh:409-412 before the -mods= flag at entrypoint.sh:426), but wiring alone cannot prove "no Singleton not found, no MySQL error" — that requires the runtime to have actually exercised the path and the log to have been captured. Runtime receipt not yet captured — pending dell boot (notes.md §"Static-evidence ceiling" explicitly confirms this). This is a runtime-pending MISSING, not a code gap.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "ArkShop/Permissions `config.json` on the volume has `UseMysql=true` + `MysqlHost=mariadb` + creds, written at boot from `.env` (password NOT present in git or container logs)"
Verdict: MET
Evidence: entrypoint.sh:293-368 (`inject_plugin_db_config()`); entrypoint.sh:19-26 (ARKSHOP_DB_* env block); .gitignore:8-9 (`plugins-config/**` / `!plugins-config/.gitkeep`); entrypoint.sh:346 (log line omits password)
Reason: Four legs all confirmed in the diff. (1) `UseMysql=true` + all five Mysql fields injected: entrypoint.sh:337-342 — jq filter sets `.Mysql.UseMysql = true | .Mysql.MysqlHost = $host | .Mysql.MysqlUser = $user | .Mysql.MysqlPass = $pass | .Mysql.MysqlDB = $db | .Mysql.MysqlPort = ($port | tonumber)`. `MysqlHost` defaults to `mariadb` via the two-level fallback `${ARKSHOP_DB_HOST:-${MARIADB_HOST:-mariadb}}` at entrypoint.sh:22. (2) Written at boot from `.env`: the ARKSHOP_DB_* vars fall through to MARIADB_* which are plumbed into `the-island.environment` in docker-compose.yml:70-79; inject runs on every boot inside `ENABLE_ASAAPI=1` branch. (3) Password NOT in git: `.gitignore:8` adds `plugins-config/**` — the runtime-written config.json (which contains the live password) is gitignored. The `.gitkeep` placeholder (`!plugins-config/.gitkeep`) is the only tracked file in that dir. Passwords only appear in gitignored `.env*` files; `.env.test.example` / `.env.prod.example` carry placeholder `use-a-long-random-*` values only. (4) Password NOT in container logs: entrypoint.sh:346 logs `host=... db=... user=...` and explicitly comments "Password intentionally omitted from the log line above." jq receives the password via `--arg pass "${ARKSHOP_DB_PASS}"` (not echoed to stdout). The fail-fast fatal message at entrypoint.sh:315 names the required vars but does not print their values.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "A points/shop action (e.g. RCON `AddPoints` or playtime accrual) persists a row to MariaDB — verified by querying the DB"
Verdict: MISSING
Evidence: —
Reason: This AC is explicitly end-to-end runtime — it requires a live server, a shop action fired (RCON or in-game playtime), and a DB query confirming a new row. None of that can be proved statically. No runtime receipt file for Phase 5 exists in the diff or scratch. notes.md §"Static-evidence ceiling" explicitly flags this AC as requiring the pending dell boot. The code plumbing (MariaDB compose service wired via notes.md Phase 1; ArkShop plugin deployed via Phase 2; creds injected at boot via inject_plugin_db_config(); mod 955333 appended so no Singleton error) is present and correct in the diff, but the AC asserts an observable outcome ("persists a row") not a code shape. Runtime-pending MISSING, not a code gap.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "Plugin `config.json` is edit-on-host (edit → restart → change takes effect) and is NOT clobbered by the boot sync"
Verdict: WEAK
Evidence: entrypoint.sh:256-291 (`setup_plugin_configs()`); entrypoint.sh:279 (seed-if-absent guard); entrypoint.sh:286-287 (rm -rf + ln -sfn per plugin); entrypoint.sh:72-145 (`deploy_plugins()` stash/rm/restore); docker-compose.yml:83 (`./plugins-config:/home/container/plugins-config` bind mount); .gitignore:8
Reason: The "NOT clobbered" half is statically MET: the mechanism is provably correct in the diff. First boot: deploy_plugins() lays down real plugin dirs with image-default config.json; setup_plugin_configs() copies config.json to host dir (seed-if-absent check at entrypoint.sh:279); then symlinks the plugin dir → host dir. Warm boot: deploy_plugins() stash loop at entrypoint.sh:93-100 reads config.json via the symlink (follows it to the host file), stashes it; rm -rf at entrypoint.sh:104 removes the symlink-as-link only (standard Unix semantics — rm -rf on a symlink to a directory removes the symlink, not the target's contents); fresh dir is cp'd from image; stash is restored into the fresh real dir; then setup_plugin_configs() re-symlinks. Host file at ./plugins-config/ArkShop/config.json is never deleted. inject_plugin_db_config() at entrypoint.sh:337-342 only mutates .Mysql.* fields via a targeted jq filter — non-DB shop config (item prices, rates, etc.) in the same config.json is untouched. The "edit-on-host" half is structurally guaranteed: the compose bind at docker-compose.yml:83 mounts `./plugins-config` and the symlink routes the plugin's reads/writes through it, so any host edit is live on the next server start. HOWEVER: the "edit → restart → change takes effect" half is runtime-dependent — it requires actually editing the host file, restarting the container, and observing the in-game plugin pick up the change. That observation requires a live dell boot that has not yet occurred. The "NOT clobbered" sub-AC is statically MET; the "takes effect on restart" sub-AC is runtime-pending. Grading WEAK because the AC is a conjunction and the restart→takes-effect leg lacks a runtime receipt.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "ASA API Utils mod ID recorded + the mod downloaded under the game's mods dir"
Verdict: WEAK
Evidence: notes.md:142 ("ASA API Utils CurseForge mod ID = **955333**"); notes.md:153 ("ASA API Utils mod ID confirmed: 955333"); plan.md:441 (mod ID 955333 in Phase 4 AC1 evidence); entrypoint.sh:405-412 (auto-appends 955333 to MODS); entrypoint.sh:426 (`[[ -n "$MODS" ]] && flags="${flags} -mods=${MODS}"`); README.md:112 (CurseForge mod ID `955333` documented); .env.test.example / .env.prod.example comment noting auto-add
Reason: The "recorded" half is statically MET — mod ID 955333 appears in notes.md (twice: Phase 4 discovery note + Phase 5 confirmation), plan.md Phase 4 AC1 evidence, the entrypoint comment at line 405, and README.md:112. The "mod downloaded under the game's mods dir" half is runtime-pending: the game's native mod download mechanism fires when `-mods=955333` is passed at launch (entrypoint.sh:426), and the download lands in the game's mods directory. The code path that passes the flag is complete and correct in the diff — entrypoint.sh:409-412 appends 955333 to MODS when ENABLE_ASAAPI=1 with de-duplication, and line 426 includes it in the launch flags. But whether ASA's mod manager actually downloads the mod to the mods dir on the dell boot is an observable runtime outcome not yet captured. notes.md §"Static-evidence ceiling" lists this as runtime-pending. Grading WEAK: one leg MET statically, one leg requires the dell boot receipt.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "README \"Shared store\" section added (config loop + data location)"
Verdict: MET
Evidence: README.md:76-115 (`## Shared store (ArkShop + points economy)` section, +40 lines in diff)
Reason: The section exists and covers both required elements verbatim. Config loop: README.md:81-93 (`### Plugin config edit loop`) describes the `./plugins-config/` directory structure, seed-on-first-boot behavior, and edit-on-host → docker compose restart → picks up change workflow. Data location: README.md:101-108 (`### Where economy data lives`) states "All points balances, shop transactions, and player records are stored in the `arkshop` MariaDB database on the `ark-db` named volume" with the direct query command. Additionally covers DB credentials injection (README.md:95-99) and the required ASA API Utils mod (README.md:110-114 — documents mod ID 955333 and that the entrypoint adds it automatically). The Documentation Deliverables table row "README: roadmap line bump … document the shared-store usage + plugin-config loop" is also satisfied: the MariaDB section at README.md:67-75 (Phase 1, already MET) plus the new Shared store section at :76-115. Roadmap line updated to "M2 (current)" at README.md:118.

NOTE on Documentation Deliverables: the plan's `## Documentation Deliverables` table lists `README: roadmap line bump (M2 in progress → traits) + "Database" note | 1 / 5 |`. The README now has 8 top-level `##` sections (grep -c "^## " = 8), which triggers the documentation.md growth predicate (≥6 → promote to docs/ tree). This is a documentation.md concern outside this AC's scope — flagged for the rules-compliance-reviewer, not a MISSING here.
--- END AC ENTRY ---

---

### Overall Verdict

OVERALL VERDICT: BLOCK — 3 AC are MISSING or WEAK (AC1 MISSING runtime receipt, AC3 MISSING runtime receipt, AC4 WEAK runtime receipt for restart→takes-effect leg, AC5 WEAK runtime receipt for mod-downloaded leg); 2 AC are runtime-pending dell boot, not code defects

---

### Required Fixes

1. **[.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md:500]** AC: "`ArkApi.log` shows ArkShop + Permissions loaded with NO `Singleton not found` and NO MySQL connection error". VERDICT: MISSING. FIX: Boot the dell test box with `ENABLE_ASAAPI=1` and mod 955333 active; capture the ArkApi log output showing both ArkShop and Permissions loaded lines plus the absence of `Singleton not found` and `failed to connect`/MySQL error strings. Write to `phase5-runtime-evidence.md` §AC1. This is a runtime receipt task, not a code change.

2. **[.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md:504]** AC: "A points/shop action (e.g. RCON `AddPoints` or playtime accrual) persists a row to MariaDB — verified by querying the DB". VERDICT: MISSING. FIX: On the dell boot, fire an RCON `AddPoints` command or trigger playtime accrual; then run `docker compose exec mariadb mariadb -u arkshop -p<PASS> arkshop -e 'SELECT * FROM <points table> LIMIT 5;'` and capture the output showing a row. Write to `phase5-runtime-evidence.md` §AC3. Runtime receipt task.

3. **[.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md:506]** AC: "Plugin `config.json` is edit-on-host (edit → restart → change takes effect) and is NOT clobbered by the boot sync". VERDICT: WEAK. FIX: The "NOT clobbered" half is statically MET (code proof above). For the "takes effect" half: edit a non-DB field in `./plugins-config/ArkShop/config.json` on the dell host (e.g. a point rate), `docker compose restart the-island`, and confirm the plugin loaded the edited value (via ArkApi.log or in-game verification). Write to `phase5-runtime-evidence.md` §AC4. The static code analysis is sufficient for "NOT clobbered"; the coordinator may choose to accept the static proof for that sub-AC and only require the restart receipt for the "takes effect" leg.

4. **[.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md:508]** AC: "ASA API Utils mod ID recorded + the mod downloaded under the game's mods dir". VERDICT: WEAK. FIX: "Recorded" is already MET. For "downloaded": during the dell boot, confirm the mod actually downloaded by checking the game's mods directory (e.g. `docker compose exec the-island ls ${ARK_DIR}/ShooterGame/Content/Mods/` and verify 955333 or its named folder appears). Write to `phase5-runtime-evidence.md` §AC5. The coordinator may choose to accept the static proof for the "recorded" sub-AC and only require the download confirmation.

---

### Bottom Line

Chief, two ACs are pure runtime with zero receipts (AC1 and AC3 — the actual log and the actual DB row), one is a conjunction where the static half is solid but the restart receipt is missing (AC4), and one is a split where "recorded" is rock-solid but "downloaded" needs the dell boot to confirm. The code is well-constructed — this BLOCK is entirely on the pending dell boot, not on code gaps. Fire up the dell, capture `phase5-runtime-evidence.md`, and this gates to PASS in round 2 the same way Phase 4 did.
