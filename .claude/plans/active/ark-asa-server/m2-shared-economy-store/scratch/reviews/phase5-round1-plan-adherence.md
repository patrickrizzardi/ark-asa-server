# Plan Adherence Review: m2-shared-economy-store Phase 5 Round 1

### Verdict: BLOCK

### Diff Scope
- Files changed: 10 total in diff; 2 are prior-phase bookkeeping (plan.md `Committed:` line, state.md radar — excluded per coordinator instruction); **8 files carry Phase 5 content**
- Lines added/removed: +240 / -4 (total diff); Phase 5 content is approximately +232 / -3
- Diff source: `git diff 4f19274` (working tree vs Phase-4 base commit)

---

### Step-by-Step Audit

Phase 5 Steps (from plan.md Phase 5 `**Steps**` block):

**Step 1**: Decide the plugin-config host home: a host-bound dir (reuse `./config` or add `./plugins-config`) symlinked into `…/ArkApi/Plugins/<name>/` per the entrypoint.sh:62-69 pattern. Seed the default `config.json` on first boot if absent; never overwrite an existing one.

**MET** — `./plugins-config/` chosen as host home (documented approach deviation #1 / plan-sanctioned option). `setup_plugin_configs()` in `entrypoint.sh:253-289` implements the symlink pattern: `mkdir -p "${host_dir}"` → seed-if-absent `cp "${plugin_dir}/config.json" "${host_dir}/config.json"` when `! -f "${host_dir}/config.json"` → `rm -rf "${plugin_dir}"` → `ln -sfn "${host_dir}" "${plugin_dir}"`. Seed-if-absent is explicit; never-overwrite enforced by the `-f` guard. `docker-compose.yml:83` adds the bind: `./plugins-config:/home/container/plugins-config`. `plugins-config/.gitkeep` (documented scope deviation #3) anchors the host dir.

**Step 2**: entrypoint: inject DB secrets into ArkShop + Permissions `config.json` at boot from the `MARIADB_*`/dedicated `ARKSHOP_DB_*` env (set `UseMysql=true`, `MysqlHost=mariadb`, `MysqlUser`, `MysqlPass`, `MysqlDB`, `MysqlPort=3306`). Use a placeholder-substitution or `jq` approach; never echo the password.

**MET** — `inject_plugin_db_config()` in `entrypoint.sh:293-368` uses `jq --arg` (documented approach deviation #2 — plan-sanctioned option). Sets all six Mysql fields (`UseMysql`, `MysqlHost`, `MysqlUser`, `MysqlPass`, `MysqlDB`, `MysqlPort`). `MysqlPort` coerced via `tonumber` to stay integer. Fail-fast on empty creds at `entrypoint.sh:308-315`. Password never echoed — the log line at `entrypoint.sh:356` explicitly omits it. Permissions plugin injection gated on `jq -e 'has("Mysql")'` check. Env var fallback chain at `entrypoint.sh:19-23` feeds `ARKSHOP_DB_*` from `MARIADB_*` when unset. `jq` added to Dockerfile apt layer (documented scope deviation #1).

**Step 3**: Look up + add the **ASA API Utils** CurseForge mod ID to `MODS` (entrypoint already passes `-mods`). Record the ID in plan notes.

**MET** — Mod ID 955333 auto-appended inside `if [[ "${ENABLE_ASAAPI}" == "1" ]]` block at `entrypoint.sh:400-413` with de-duplication guard (documented approach deviation #3 — plan-sanctioned variation; gating inside ENABLE_ASAAPI=1 is a strict improvement over baking into the MODS default). ID recorded in `notes.md` Phase 5 section line 153: "ASA API Utils mod ID confirmed: 955333". The `.env.*.example` both carry the comment "ASA API Utils (955333) is added automatically when ENABLE_ASAAPI=1."

**Step 4**: compose/env: add the plugin-config bind + any `ARKSHOP_DB_*` vars to `.env.*.example`.

**MET** — `docker-compose.yml:83` adds `./plugins-config:/home/container/plugins-config` bind. `.env.test.example` and `.env.prod.example` both gain `# --- ArkShop DB connection (M2+) ---` block with `ARKSHOP_DB_HOST/PORT/NAME/USER/PASS` commented-out overrides + explanatory comment. `docker-compose.yml:68-80` wires `MARIADB_DATABASE/USER/PASSWORD` and `ARKSHOP_DB_*` into the `the-island` environment block.

**Step 5**: Boot on dell; verify `ArkApi.log` has no `Singleton not found` and no DB connection error; run a points/shop action (RCON or in-game) and confirm a row appears in MariaDB.

**PARTIAL** — The code side of Step 5 is fully implemented (all the config injection and mod-append that will produce the clean log exists). However, the dell boot itself has not yet occurred — `phase5-runtime-evidence.md` shows all AC results as "(pending dell boot)". Per coordinator instruction, this is a coordinator-driven pending step (evidence scaffold is in place with exact commands), NOT a skipped executor step. The code that would satisfy this step at boot time is complete. Classifying PARTIAL rather than MISSING because the code deliverable is done; the runtime receipt is a coordinator action.

**Step 6**: README: add a "Shared store" section — plugin-config edit loop, how points/shop work, where the data lives.

**MET** — `README.md` gains `## Shared store (ArkShop + points economy)` at line 75: explains ArkShop + points economy, plugin config edit loop with directory listing (`./plugins-config/ArkShop/config.json`, `Permissions/config.json`), DB credentials injection explanation, "where economy data lives" with a `docker compose exec mariadb` query command, and ASA API Utils mod requirement + auto-append behavior. All three sub-topics the plan specified are present.

---

### Scope Audit

**Files (expected scope) per plan Phase 5**: `entrypoint.sh`, `docker-compose.yml`, `config/**` (or a new `plugins-config/` bind), `.env.test.example`, `.env.prod.example`, `README.md`

Files touched by Phase 5 diff (excluding prior-phase bookkeeping files plan.md + state.md):

- `entrypoint.sh`: **IN SCOPE** — primary Phase 5 file; `setup_plugin_configs()` + `inject_plugin_db_config()` + MODS auto-append + ARKSHOP_DB_* env block
- `docker-compose.yml`: **IN SCOPE** — Phase 5 expected scope; adds plugins-config bind + ARKSHOP_DB_*/MARIADB_* env vars to the-island service
- `.env.test.example`: **IN SCOPE** — Phase 5 expected scope; ARKSHOP_DB_* override block added
- `.env.prod.example`: **IN SCOPE** — Phase 5 expected scope; ARKSHOP_DB_* override block added
- `README.md`: **IN SCOPE** — Phase 5 expected scope; "Shared store" section added
- `Dockerfile`: **DEVIATION (DOCUMENTED)** — scope deviation #1; jq added to apt layer because `inject_plugin_db_config()` requires jq, not in base image. Rationale in phase5-deviations.md is clear and technically correct.
- `.gitignore`: **DEVIATION (DOCUMENTED)** — scope deviation #2; `plugins-config/**` + `!plugins-config/.gitkeep` added to prevent committing the runtime-injected DB password. Documented in phase5-deviations.md.
- `plugins-config/.gitkeep`: **DEVIATION (DOCUMENTED)** — scope deviation #3; empty anchor file so the host bind-mount dir exists pre-compose-up, avoiding root-owned dir creation. Documented in phase5-deviations.md.
- `notes.md`: **DEVIATION (DOCUMENTED)** — scope deviation #4; Phase 5 churn entries added. Standard plan practice; documented in phase5-deviations.md.

**Content-level creep within in-scope files — BLOCK item found:**

`docker-compose.yml` gains `command: --default-authentication-plugin=mysql_native_password` on the `mariadb` service (lines 24-27 in the diff). This is content within an in-scope file, but:
- No Phase 5 Step mentions changing the MariaDB authentication plugin
- Not listed in phase5-deviations.md (7 deviations documented; none reference this line)
- Not mentioned in notes.md Phase 5 section
- This is a behavioral change to the MariaDB service (forces mysql_native_password auth plugin server-wide), not a mechanical wiring of the plugin-config bind or ARKSHOP_DB_* vars

This is **silent content-level scope creep within an in-scope file** — the file is in scope, but the specific change is undocumented and not called for by any step. Per Section 5: BLOCK.

**Files in expected scope NOT touched**: `config/**` — not touched; this is intentional (plan offered `./config` OR `./plugins-config` as the plugin-config home; executor chose `./plugins-config/`, making `config/**` a non-touch by design).

---

### Approach Audit

**Approach hint 1**: "reuse `./config` or add `./plugins-config`" (Step 1) → **MATCHED (DOCUMENTED DEVIATION #1)** — executor chose `./plugins-config/`. Plan explicitly offered this as a sanctioned option ("or add `./plugins-config`"), so this is the plan's own Option B, not a true deviation. Documented in phase5-deviations.md Deviation #1 anyway. Non-blocking.

**Approach hint 2**: "Use a placeholder-substitution or `jq` approach" (Step 2) → **MATCHED (DOCUMENTED DEVIATION #2)** — executor chose jq with `--arg`. Plan explicitly sanctioned both; jq is the safer choice for arbitrary password values. Documented in phase5-deviations.md Deviation #2. Non-blocking.

**Approach hint 3**: "never echo the password" (Step 2) → **MATCHED** — `inject_plugin_db_config()` log line at `entrypoint.sh:356` explicitly omits the password: "Password intentionally omitted from the log line above."

**Approach hint 4**: per entrypoint.sh:62-69 pattern (Step 1) → **MATCHED** — `setup_plugin_configs()` mirrors the existing pattern: `mkdir -p`, seed-if-absent, `ln -sfn`.

**Approach hint 5**: "gated in ENABLE_ASAAPI=1" for mod auto-append (documented approach deviation #3) → **MATCHED (DOCUMENTED DEVIATION #3)** — `entrypoint.sh:400` wraps the MODS append inside `if [[ "${ENABLE_ASAAPI}" == "1" ]]`. Plan Step 3 said "add mod ID to MODS"; gating it to the modded path only is a stricter implementation that avoids contaminating vanilla boots. Documented in phase5-deviations.md Deviation #3. Non-blocking.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

- **"ArkApi.log shows ArkShop + Permissions loaded with NO `Singleton not found` and NO MySQL connection error"**: Unclear / Pending — code delivers mod 955333 auto-append (required for no Singleton not found) and DB config injection (required for no MySQL error), but the actual log hasn't been captured yet. `phase5-runtime-evidence.md` §AC1 shows "(pending dell boot)". Cross-flag: acceptance-verifier must verify on dell boot receipt.

- **"ArkShop/Permissions config.json on the volume has `UseMysql=true` + `MysqlHost=mariadb` + creds, written at boot from `.env` (password NOT in git or container logs)"**: Yes (code-complete, statically verifiable) — `inject_plugin_db_config()` at `entrypoint.sh:293-368` sets all six Mysql fields; fail-fast on empty creds; password omitted from logs. Git check: `ARKSHOP_DB_PASS` only in `.example` files as commented-out placeholder; `.gitignore` now excludes `plugins-config/**`. `phase5-runtime-evidence.md` §AC2 has runtime verification commands but result is "(pending dell boot)" — the static evidence is strong; runtime receipt pending.

- **"A points/shop action persists a row to MariaDB — verified by querying the DB"**: No visible diff content proves end-to-end persistence — this requires a live server boot + RCON command + DB query. `phase5-runtime-evidence.md` §AC3 has the exact commands but result is "(pending dell boot)". Cross-flag: acceptance-verifier must verify on dell boot receipt.

- **"Plugin config.json is edit-on-host and NOT clobbered by the boot sync"**: Yes (code-complete, statically verifiable) — `setup_plugin_configs()` seed-if-absent guard (`! -f "${host_dir}/config.json"`) + symlink pattern ensures the host-bound file is never overwritten. The warm-boot path: `deploy_plugins()` removes the symlink-as-link (not the host target), then `setup_plugin_configs()` re-symlinks. `phase5-runtime-evidence.md` §AC4 has runtime verification commands but result is "(pending dell boot)".

- **"ASA API Utils mod ID recorded + the mod downloaded under the game's mods dir"**: Partial — mod ID 955333 is recorded in notes.md + `.env.*.example` comments + entrypoint.sh comment. The "downloaded under game's mods dir" half requires a dell boot. `phase5-runtime-evidence.md` §AC5 has verification commands; result "(pending dell boot)". Cross-flag: acceptance-verifier must verify on dell boot receipt.

- **"README 'Shared store' section added (config loop + data location)"**: Yes — `README.md` gains `## Shared store (ArkShop + points economy)` with plugin config edit loop, DB credentials section, "where economy data lives" with query command, and Required mod section. MET.

---

### Out-of-Scope Content Creep

**`docker-compose.yml` — `command: --default-authentication-plugin=mysql_native_password` on the `mariadb` service**: This is a behavioral change to the MariaDB authentication configuration. It is:
- Within an in-scope file (docker-compose.yml is Phase 5 expected scope)
- NOT called for by any of the 6 Phase 5 Steps
- NOT listed in phase5-deviations.md (7 deviations documented; this is not one of them)
- NOT mentioned in notes.md Phase 5 section
- The inline comment references "DataGrip's MariaDB Connector/J" — a developer tooling concern, not a Phase 5 deliverable

The comment on the line is well-reasoned (MariaDB 11.4 `caching_sha2_password` default vs ArkShop client lib expecting `mysql_native_password`), and if correct it would fix a real ArkShop connectivity issue. But the executor did not document it as a deviation. This is **silent content-level scope creep** — BLOCK.

Note for the coordinator: the change may well be correct and necessary for ArkShop to connect. The fix is not "remove it" but "document it as a deviation in phase5-deviations.md with the reason." One line in the deviations file closes this BLOCK.

---

### Deviation Rationale Phrase Check

Checking all 7 documented deviations from phase5-deviations.md against the banned phrases in `no-duct-tape.md §Phrases That Trigger Review` (mechanical substring match, case-insensitive):

- **Deviation #1** (Dockerfile jq): "jq required for safe JSON mutation; not in base image; added to Dockerfile apt layer (only place to bake it)." — No banned phrases detected.
- **Deviation #2** (.gitignore plugins-config): "plugins-config/** gitignored (except .gitkeep) so the runtime-injected DB password in ArkShop/config.json can't be accidentally committed." — No banned phrases detected.
- **Deviation #3** (plugins-config/.gitkeep): "plugins-config/.gitkeep created so the host bind-mount dir exists pre-`up`, preventing root-owned dir creation that would block the non-root container user." — No banned phrases detected.
- **Deviation #4** (notes.md): "notes.md updated with Phase 5 execution decisions (established churn-log pattern for this plan)." — No banned phrases detected.
- **Deviation #5** (./plugins-config/ separate dir): "separate concerns (engine INI vs plugin config.json), distinct target paths, cleaner operator model." — No banned phrases detected.
- **Deviation #6** (jq --arg approach): "safe for special chars in passwords; tonumber coercion keeps MysqlPort integer-typed." — No banned phrases detected.
- **Deviation #7** (auto-append 955333 MODS): "avoids adding the mod to vanilla boots; prevents doubled entry if operator already lists it." — No banned phrases detected.

All rationales clean — no banned phrases detected.

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

`Scope-escape: FLAGGED — 1 escape below`

The `command: --default-authentication-plugin=mysql_native_password` addition to the `mariadb` service in `docker-compose.yml` is content-level work within an in-scope file that is not called for by any Phase 5 Step and is undocumented in the deviation trail. This already constitutes undocumented content-level scope creep per Sections 2/5. Annotating with cross-milestone facts per Section 7:

- **[docker-compose.yml:24]** SCOPE-ESCAPE — crept symbol/work: `command: --default-authentication-plugin=mysql_native_password` (new `command:` key on the `mariadb` service). Ledger-ownership (fact a): no exact match in `capability-ledger.md` for this specific capability string — the `mariadb` service is covered by `"Self-contained MariaDB service in compose"` (owning milestone: `m2-shared-economy-store` = this milestone), but the authentication-plugin configuration is not a declared capability string in the ledger at all; reporting: `no ledger match`. Used/unused (fact b): `grep -nFw 'default-authentication-plugin' $(git diff 4f19274 --name-only)` — the string appears only at its definition site in `docker-compose.yml`; no other Phase 5 in-scope code references it. UNUSED (`no non-definition reference`). ADJUDICATION: orchestrator (`execute-plan §3.f.2`) — NOT decided here.

---

### Required Fixes (BLOCK summary)

1. **[docker-compose.yml:24]** SOURCE: Section 5 silent content-level scope creep. ISSUE: `command: --default-authentication-plugin=mysql_native_password` added to the `mariadb` service without documentation in phase5-deviations.md or notes.md — not called for by any Phase 5 Step, not listed among the 7 documented deviations. FIX: Add a Scope Deviation entry to `phase5-deviations.md` (and a note in `notes.md` Phase 5 section) documenting this change — why the auth plugin override was needed (ArkShop client lib + MariaDB 11.4 default incompatibility), which step it relates to (Step 4/the-island DB connectivity), and why it touches the mariadb service. The change itself may be correct; the missing paper trail is the BLOCK.

---

### Bottom Line

Five of six steps land clean, all seven documented deviations are well-reasoned and bang-phrase-free, and the runtime evidence scaffold is correctly deferred to the dell boot. But the `mariadb` `command: --default-authentication-plugin` line is a silent undocumented scope creep — it's sitting in an in-scope file with a perfectly reasonable inline comment, and zero entry anywhere in the deviation trail. One line in phase5-deviations.md closes this. Chief, fix the paperwork, not the code.
