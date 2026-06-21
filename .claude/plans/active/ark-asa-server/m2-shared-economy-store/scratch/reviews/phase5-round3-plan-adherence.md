# Plan Adherence Review: m2-shared-economy-store Phase 5 Round 3

### Verdict: PASS

### Diff Scope
- Files changed: 9 (code-bearing; excluding plan/notes/scratch churn in the stat)
- Lines added/removed: +164 / -4 in `entrypoint.sh` (the round-3 delta); Dockerfile +1/-1 (`jq`); docker-compose.yml +14/-2; `.env.*.example` +11 each; `.gitignore` +5; `README.md` +40; `plugins-config/.gitkeep` +1 (new)
- Diff source: `git diff 4f19274` (working tree from Phase 4 commit; plan/state.md chore deltas excluded from analysis per coordinator instruction)

### Step-by-Step Audit

Phase 5 Steps (from plan.md):

1. **Decide the plugin-config host home: a host-bound dir (reuse `./config` or add `./plugins-config`) symlinked into `…/ArkApi/Plugins/<name>/` per the entrypoint.sh:62-69 pattern. Seed the default `config.json` on first boot if absent; never overwrite an existing one.**

   MET — `./plugins-config/` chosen as the separate host bind (Deviation #5, documented). `docker-compose.yml:83` adds the bind mount `./plugins-config:/home/container/plugins-config`. `setup_plugin_configs()` (entrypoint.sh:254–290) iterates ArkShop + Permissions, seeds host config.json from image default if absent (`-f host_dir/config.json` guard), then symlinks ONLY `config.json` (the file, not the whole dir) into the deployed plugin dir. The "never overwrite" contract is enforced by the `[[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` seed-if-absent guard.

   **Round-3 note (the correctness fix this review is re-checking):** The prior implementation `rm -rf`'d the whole plugin dir and symlinked it to the config-only host dir — deleting the deployed DLL (confirmed on dell: "Plugin ArkShop does not exist"). The round-3 diff corrects this: `ln -sfn "${host_dir}/config.json" "${plugin_dir}/config.json"` symlinks ONLY the file, leaving the DLL in place. The fix is documented in notes.md §"Phase 5 — RUNTIME BUG caught by dell boot" and §"Phase 5 — dell runtime verification + 2 runtime bugs fixed". This is a correctness fix to Step 1's implementation, same step, same scope — not a new deviation.

2. **entrypoint: inject DB secrets into ArkShop + Permissions `config.json` at boot from the `MARIADB_*`/dedicated `ARKSHOP_DB_*` env. Use a placeholder-substitution or `jq` approach; never echo the password.**

   MET — `inject_plugin_db_config()` (entrypoint.sh:370–430) + `_inject_mysql_block()` helper (entrypoint.sh:294–365). jq used with `--arg` for all creds (Deviation #6, documented). Fail-fast on missing/empty creds + numeric port guard. Password present in jq argv (documented in comment: "transiently visible in this container's own /proc/<pid>/cmdline — acceptable in a single-user game container") and explicitly omitted from the log line. Symlink-resolution via `readlink -f` + `mv` onto real target keeps host-bind intact (part of the round-3 runtime-bug fix).

3. **Look up + add the ASA API Utils CurseForge mod ID to `MODS` (entrypoint already passes `-mods`). Record the ID in plan notes.**

   MET — mod ID `955333` auto-appended inside the `ENABLE_ASAAPI=1` branch (entrypoint.sh:421–430) with de-dup guard (Deviation #7, documented). ID recorded in notes.md §"Phase 5 — execution notes" and in the plan's Phase 4 AC1 evidence annotation. Auto-append rationale: avoids silently adding the mod to vanilla (ENABLE_ASAAPI=0) boots.

4. **compose/env: add the plugin-config bind + any `ARKSHOP_DB_*` vars to `.env.*.example`.**

   MET — `docker-compose.yml:83` adds `./plugins-config:/home/container/plugins-config` bind. `.env.test.example` and `.env.prod.example` each gain an `# --- ArkShop DB connection (M2+) ---` section with all `ARKSHOP_DB_*` vars as commented-out overrides with explanation. Compose `the-island.environment` block adds `MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD` pass-through plus `ARKSHOP_DB_*` defaults (docker-compose.yml:72–81). Note: `MARIADB_PASSWORD` uses `:?` (fail-loud on unset) rather than `:-` — correct defensive pattern.

5. **Boot on dell; verify `ArkApi.log` has no `Singleton not found` and no DB connection error; run a points/shop action (RCON or in-game) and confirm a row appears in MariaDB.**

   MET — notes.md §"Phase 5 — dell runtime verification + 2 runtime bugs fixed" records: AC1 MET (ArkApi log shows ArkShop V1.4 + Permissions V1.1 loaded, no Singleton-not-found, no MySQL error); AC3 MET (RCON `SetPoints <eosid> 250` → "Successfully set points" → `SELECT … ArkShopPlayers` shows Points=250; schema auto-created proving DB connection). Both runtime-bug fixes were applied and re-verified on dell before this review was requested.

6. **README: add a "Shared store" section — plugin-config edit loop, how points/shop work, where the data lives.**

   MET — `README.md` adds `## Shared store (ArkShop + points economy)` (line 75+), covering: plugin config edit loop, `./plugins-config/` layout, DB credentials injection, where economy data lives (`ark-db` volume, query example), required mod (ASA API Utils 955333 + auto-append explanation).

### Scope Audit
- Files in expected scope (plan.md Phase 5): `entrypoint.sh`, `docker-compose.yml`, `config/**` (or new `plugins-config/` bind), `.env.test.example`, `.env.prod.example`, `README.md`
- Files touched by diff (code-bearing):

  - `entrypoint.sh`: IN SCOPE
  - `docker-compose.yml`: IN SCOPE
  - `.env.test.example`: IN SCOPE
  - `.env.prod.example`: IN SCOPE
  - `README.md`: IN SCOPE
  - `Dockerfile`: DEVIATION (DOCUMENTED) — Scope Deviation #1: jq apt layer required for `inject_plugin_db_config()`; jq not in base image; Dockerfile is the only place to bake it. plan.md Step 2 explicitly offered the jq approach.
  - `.gitignore`: DEVIATION (DOCUMENTED) — Scope Deviation #2: `plugins-config/**` gitignored (! except .gitkeep) so runtime-injected DB password in ArkShop/config.json can't be accidentally committed. Quality gate requires "DB password never committed."
  - `plugins-config/.gitkeep`: DEVIATION (DOCUMENTED) — Scope Deviation #3: dir must exist pre-`docker compose up`; Docker would create it root-owned otherwise, blocking the non-root `container` user.
  - `notes.md` (plan churn): DEVIATION (DOCUMENTED) — Scope Deviation #4: established churn-log pattern for this plan; all prior phases recorded execution decisions here.

- Files in expected scope NOT touched: `config/**` — intentional. Step 1 chose `./plugins-config/` as a new separate bind rather than reusing `./config` (Deviation #5, documented). No change to the existing `./config` bind was needed.

**Round-3 specific scope check:** The two runtime-bug fixes both land in `entrypoint.sh` (IN SCOPE). The Xvfb stale-lock cleanup (`rm -f /tmp/.X0-lock /tmp/.X11-unix/X0`) touches Phase-4-introduced code, but it lives in `entrypoint.sh` which is in Phase 5 scope, and it is a correctness prerequisite for Phase 5's AC4 (edit-on-host restart loop). No new out-of-scope file is introduced by the round-3 fixes.

### Approach Audit

- **"reuse `./config` or add `./plugins-config`"** (Step 1) → DEVIATED (DOCUMENTED) — chose `./plugins-config/` (Deviation #5). Rationale: `./config` holds engine INI files with a distinct target path (`…/Saved/Config/WindowsServer`); mixing plugin configs would make the bind ambiguous. Separate concerns, separate dirs, cleaner operator model. Documented in phase5-deviations.md.

- **"symlinked into `…/ArkApi/Plugins/<name>/` per the entrypoint.sh:62-69 pattern"** (Step 1) → DEVIATED-WITH-REASON (implementation-corrected in round 3). Round-2 implementation symlinked the whole plugin dir (per the pattern). Round 3 corrects to symlink ONLY `config.json` (the file), because the whole-dir symlink deleted the DLL. The pattern is preserved conceptually (host bind → symlink → plugin dir) but scoped to file-level, not dir-level. Fix documented in notes.md §"RUNTIME BUG" — no plan deviation required since this is a correctness fix to the step's implementation, not a philosophical departure from the approach.

- **"Use a placeholder-substitution or `jq` approach; never echo the password"** (Step 2) → MATCHED — jq chosen exclusively, `--arg` used for all creds. Password omitted from log line. (Deviation #6 documents the jq-only choice over sed/placeholder.)

- **"Look up + add the ASA API Utils CurseForge mod ID to `MODS`"** (Step 3) → DEVIATED (DOCUMENTED) — auto-appended in code rather than baked into the `MODS` default (Deviation #7). Rationale: baking into the default would add it on ENABLE_ASAAPI=0 vanilla boots. Documented in phase5-deviations.md.

- **"Seed the default `config.json` on first boot if absent; never overwrite an existing one"** (Step 1 sub-requirement) → MATCHED — `[[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` guard at entrypoint.sh:58–62 (within `setup_plugin_configs`). Dell AC4 confirmed: marker key added to host config.json survived restart (not clobbered).

- **Xvfb stale-lock cleanup** (no plan step; Phase-4-introduced code touched within in-scope file) → DOCUMENTED — notes.md §"BUG 2" documents the diagnosis (reused container /tmp, stale lock, crash loop), fix (`rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true` before Xvfb start), and the no-duct-tape grounding (fix-at-discovery; prerequisite for AC4's restart loop). The fix is in `entrypoint.sh` (in scope) and is required for AC4.

### Acceptance Criteria Sanity Check

- **"ArkApi.log shows ArkShop + Permissions loaded with NO `Singleton not found` and NO MySQL connection error"** (AC1): Yes — notes.md §"dell runtime verification" records: `Loaded plugin Ark:SA ArkShop V1.4` + `Loaded plugin Ark:SA Permissions V1.1` + `Loaded all plugins`; NO does-not-exist, NO Singleton-not-found, NO MySQL error. Dell boot receipt in notes.md; `phase5-runtime-evidence.md` was flagged as pending fill before commit.

- **"ArkShop/Permissions `config.json` on the volume has `UseMysql=true` + `MysqlHost=mariadb` + creds, written at boot from `.env` (password NOT present in git or container logs)"** (AC2): Yes — `inject_plugin_db_config()` sets all Mysql block fields via jq. `plugins-config/**` gitignored (Scope Deviation #2). Password omitted from log line (comment in code). Dell notes.md: `UseMysql:true, MysqlHost:mariadb, MysqlPort:3306 (int), pass present (host-bound file)`.

- **"A points/shop action persists a row to MariaDB"** (AC3): Yes — notes.md: RCON `SetPoints <eosid> 250` → "Successfully set points" → `SELECT … ArkShopPlayers` shows Points=250; schema auto-created.

- **"Plugin `config.json` is edit-on-host (edit → restart → change takes effect) and is NOT clobbered by the boot sync"** (AC4): Yes — this is precisely what the round-3 fix enables. notes.md: "added a marker key to host config.json → restart → marker survived + plugins still loaded (not clobbered)". The Xvfb stale-lock fix is the prerequisite (without it, restart crash-loops before setup_plugin_configs runs).

- **"ASA API Utils mod ID recorded + the mod downloaded under the game's mods dir"** (AC5): Yes — mod ID 955333 recorded in notes.md + auto-append in entrypoint.sh:421–430. notes.md: "no Singleton-not-found = ASA API Utils loaded" (inferring download succeeded from the absence of the Singleton error).

- **"README `Shared store` section added"** (AC6): Yes — `README.md` lines 75–113 add the full section (edit loop, DB creds, data location, required mod).

### Out-of-Scope Content Creep

- **Xvfb stale-lock cleanup at entrypoint.sh:193** — touches Phase-4-introduced Xvfb launch code within an in-scope file. This is a no-duct-tape fix-at-discovery: the crash loop directly breaks Phase 5's AC4 restart requirement. Documented in notes.md §"BUG 2" with diagnosis, fix, and the "critical because the config loop uses `docker compose restart`" rationale. NOT silent scope creep — documented, causal, and in-scope file.

- **`_inject_mysql_block()` `readlink -f` symlink resolution** — added as part of the round-3 runtime bug fix to the jq injection helper. In-scope function, in-scope file, correctness fix (without it, `mv tmp symlink` would orphan the host-bound config). Documented in notes.md.

- **docker-compose.yml header comment update** (line 2: "MariaDB backs the ArkShop shared economy store; the modded AsaApi + plugin services are not present yet." → "MariaDB backs the ArkShop economy; AsaApi + ArkShop + Permissions run when ENABLE_ASAAPI=1.") — in-scope file, accurate update reflecting Phase 5's actual state. Not gratuitous refactor.

None observed as silent or undocumented.

### Deviation Rationale Phrase Check

Checking all 7 documented deviations' rationale text against the `no-duct-tape.md` "Phrases That Trigger Review" list (mechanical substring match, case-insensitive):

- **Deviation #1** (Dockerfile jq apt layer): "jq required for safe JSON mutation; not in base image; added to Dockerfile apt layer (only place to bake it)." — No banned phrases detected.
- **Deviation #2** (.gitignore plugins-config): "plugins-config/** gitignored (except .gitkeep) so the runtime-injected DB password in ArkShop/config.json can't be accidentally committed." — No banned phrases detected.
- **Deviation #3** (plugins-config/.gitkeep): "plugins-config/.gitkeep created so the host bind-mount dir exists pre-`up`, preventing root-owned dir creation that would block the non-root container user." — No banned phrases detected.
- **Deviation #4** (notes.md): "notes.md updated with Phase 5 execution decisions (established churn-log pattern for this plan)." — No banned phrases detected.
- **Deviation #5** (./plugins-config/ dir): "chose separate ./plugins-config/ dir (not reusing ./config) — separate concerns (engine INI vs plugin config.json), distinct target paths, cleaner operator model." — No banned phrases detected.
- **Deviation #6** (jq --arg): "jq --arg for all creds (no sed/placeholder) — safe for special chars in passwords; tonumber coercion keeps MysqlPort integer-typed." — No banned phrases detected.
- **Deviation #7** (auto-append 955333): "auto-append 955333 to MODS inside ENABLE_ASAAPI=1 branch with de-dup — avoids adding the mod to vanilla boots; prevents doubled entry if operator already lists it." — No banned phrases detected.

All rationales clean — no banned phrases detected.

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

[Per Section 7 — per plan.md front-matter: `roadmap: ark-asa-server`, `milestone: m2-shared-economy-store`. Plan is initiative-backed. Phase 5 carries no `**Scope Boundary**` block in the plan.md source. Without a declared Scope Boundary block, the cross-milestone identity-matching mechanism has no verbatim capability strings to match against the ledger — the prerequisite for Section 7 annotation is absent.]

`Scope-escape: N/A — Phase 5 carries no **Scope Boundary** block; cross-milestone ledger matching requires verbatim Scope-Boundary capability strings. Generic creep (Sections 2+5) handled above; all touched work is documented or in-scope.`

### Required Fixes (BLOCK summary — empty if PASS)

None — all plan steps MET and scope respected.

### Bottom Line

Both runtime bugs — the whole-dir symlink that deleted the DLL and the Xvfb stale lock that crash-looped on restart — are documented, causally tied to Phase 5 ACs, and fixed in the only in-scope file that matters. Six steps MET, seven deviations documented, zero silent creep. The dell receipts in notes.md close the runtime ACs that were pending at round 2. PASS, chief.
