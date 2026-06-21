# Design Compliance Review: m2-shared-economy-store Phase 5 Round 1

### Verdict: PASS

---

### Diff Scope
- **Diff source**: `git diff 4f19274` (working tree vs Phase-4 BASE commit 4f19274)
- **Files changed**: 4 primary files with Phase 5 content
  - `entrypoint.sh` — new functions `setup_plugin_configs()`, `inject_plugin_db_config()`; new env vars `ARKSHOP_DB_*`; `jq` call for JSON mutation; `MODS` auto-append for mod 955333; call sequence updated in `main()`
  - `Dockerfile` — `jq` added to the `apt-get install` layer alongside `unzip`
  - `docker-compose.yml` — `MARIADB_*` + `ARKSHOP_DB_*` env vars plumbed to `the-island`; `./plugins-config` host bind added
  - `plugins-config/.gitkeep` — directory scaffold committed

- **Prior-phase chore deltas ignored per instruction**: `plan.md` and `.claude/state.md` updates from earlier phase commits are not analyzed (not Phase 5 design-relevant material)

---

### Registry State
- **Registry path**: `/home/patrick/docs/development/ark-asa/.claude/design-sources.md`
- **Registry status**: present-and-valid
- **Entries**: 3 entries, all `[locked]`:
  1. `.claude/rules/build-time-vs-runtime.md`
  2. `docs/internal/decisions/0001-db-engine-mariadb.md`
  3. `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`
- **Fallback globs used**: no

---

### Stale Registry Entries

None — all three registry globs resolve to real files on disk:
- `.claude/rules/build-time-vs-runtime.md` ✓
- `docs/internal/decisions/0001-db-engine-mariadb.md` ✓
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` ✓

---

### Design Docs Loaded

- `.claude/rules/build-time-vs-runtime.md` [locked] — domain match: every Dockerfile and entrypoint.sh change is subject to the 3-question split. Loaded per Sentinel Guard (c) (always load `[locked]` docs when domain overlaps).
- `docs/internal/decisions/0001-db-engine-mariadb.md` [locked] — domain match: Phase 5 wires ArkShop to MariaDB via `MysqlHost=mariadb`. DB engine and connection topology directly in scope.
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` [locked] — domain match: Phase 5 introduces `setup_plugin_configs()` (symlink/seed pattern for plugin configs) and `inject_plugin_db_config()` (runtime config mutation). Both operate on the volume at runtime — the exact pattern ADR 0002 governs.

---

### Design Docs Skipped

None — all three registry docs were loaded.

---

### Reconciliation: build-time-vs-runtime.md

**The Rule**: Immutable + cacheable + version-pinned → Dockerfile. Mutable + volume-backed + must-be-fresh-each-boot → entrypoint. Apply the 3-question test to every step; any "yes" → entrypoint.

**Phase 5 additions — 3-question test applied to each:**

#### 1. `jq` added to `apt-get install` in the Dockerfile

The `jq` tool is a build-time OS package addition to the image. Applying the test:
- Q1: Depends on runtime state (env vars, mounted volumes, network)? **No** — it is an OS binary installed at build time.
- Q2: Does the thing it produces change often? **No** — `jq` is a fixed-version system package baked into the layer.
- Q3: Must it re-run on every container start? **No** — once in the image layer, available forever.

All three questions: No → **Dockerfile**. This is exactly where the diff puts it. ✓

The doc's §The Split table includes "OS packages, Proton/Wine, winetricks, libs, curl → Dockerfile" with reason "fixed deps, cached layer, identical every run." `jq` is a fixed dep that falls squarely in this category. No contradiction.

#### 2. `setup_plugin_configs()` — symlink plugin config dirs onto host bind

This function runs in the entrypoint. Applying the test:
- Q1: Depends on runtime state (mounted volumes)? **Yes** — it operates on `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/` which is on the `ark-game` named volume, and links to `/home/container/plugins-config` which is a host bind mount (`./plugins-config:/home/container/plugins-config` in `docker-compose.yml`).
- Q2: Does what it produces change often? The symlinks themselves are idempotent, but the *contents* (operator-edited configs) can change between boots.
- Q3: Must it re-run on every boot? **Yes** — `deploy_plugins()` (which runs before it) replaces the plugin dirs with a clean copy each boot; `setup_plugin_configs()` must then re-establish the symlinks into the host-bind path after every `deploy_plugins()` run.

Q1 yes, Q3 yes → **entrypoint**. That is exactly where it lives. ✓

The doc's §The Split table includes "Config templating from env → entrypoint (depends on runtime env)" and "mkdir-p / touch logfiles → entrypoint (prep on the live volume)." The symlink/seed step is the same category — volume prep that can't happen at build time. No contradiction.

#### 3. `inject_plugin_db_config()` — jq mutation of ArkShop config.json at boot

Applying the test:
- Q1: Depends on runtime state (env vars, mounted volumes)? **Yes** — both of these. The config.json target is on the host-bind path (a bind mount, runtime state). The credentials (`ARKSHOP_DB_*`) come from env vars that exist only at runtime.
- Q2: Does what it produces change often? **Yes** — credentials could be rotated; the operator could change env vars between boots.
- Q3: Must it re-run on every boot? **Yes** — the doc's §The Split says "Config templating from env → entrypoint." This is exactly that: template injection into a config from runtime env.

Q1 yes, Q2 yes, Q3 yes → **entrypoint**. That is where it lives. ✓

The doc's §The Split table explicitly names "Config templating from env → entrypoint — depends on runtime env." This is the canonical example of that row. The diff honors it precisely.

#### 4. `MODS` auto-append for ASA API Utils mod 955333

The `MODS` manipulation runs inside `main()` in the entrypoint, conditional on `ENABLE_ASAAPI=1`. Applying the test:
- Q1: Depends on runtime state (env vars)? **Yes** — reads `${MODS}` from env and `${ENABLE_ASAAPI}`.
- Q3: Must it re-run every boot to stay correct? **Yes** — `MODS` value comes from the runtime env on each boot.

Q1 yes → **entrypoint**. Correct placement. ✓

**Summary for build-time-vs-runtime.md**: Every new placement in Phase 5 passes the 3-question test. The `jq` binary → Dockerfile (build-time tool, immutable). All runtime logic → entrypoint (volume-backed, env-dependent, must-be-fresh). **No contradiction.**

---

### Reconciliation: ADR 0001 — DB Engine = MariaDB

**The Decision**: Use MariaDB 11.4 as the DB engine. ArkShop connects via `mariadb:3306` (compose service name, internal network, no host port).

**Phase 5 additions checked:**

1. **`ARKSHOP_DB_HOST` defaults to `mariadb`** — `entrypoint.sh:22`: `ARKSHOP_DB_HOST="${ARKSHOP_DB_HOST:-${MARIADB_HOST:-mariadb}}"`. The default resolves to `mariadb`, which is the compose service name for the MariaDB container. This is exactly what ADR 0001 §Consequences specifies: "ArkShop connects via `mariadb:3306` (compose service name)." ✓

2. **`docker-compose.yml` `ARKSHOP_DB_HOST: ${ARKSHOP_DB_HOST:-mariadb}`** — the compose environment block passes the default `mariadb` service name. Internal network, no host port. ✓

3. **`ARKSHOP_DB_PORT` defaults to `3306`** — standard MariaDB port. ✓

4. **`inject_plugin_db_config()` injects `MysqlHost`, `MysqlPort`, `UseMysql=true`** — the jq filter at `entrypoint.sh:337-343` sets `.Mysql.MysqlHost = $host` (receives `mariadb` from env), `.Mysql.MysqlPort = ($port | tonumber)` (receives `3306`), and `.Mysql.UseMysql = true`. This is the correct wire-up for ArkShop → MariaDB per the ADR's decision and the plan's Decision Ledger rows #11 and #12.

5. **No MySQL ≥8.0.28 introduced** — the diff uses `mariadb:11.4` (already in compose from Phase 1). Phase 5 adds no new database or engine configuration that could violate the MySQL-rejection constraint. ✓

6. **No host port published for MariaDB** — the `mariadb` service in `docker-compose.yml` has no `ports:` key (unchanged from Phase 1; Phase 5 does not touch the mariadb service definition). ✓

**Summary for ADR 0001**: Phase 5 wires ArkShop to the MariaDB service correctly — service-name connection, correct port, internal-only — exactly as the ADR specifies. **No contradiction.**

---

### Reconciliation: ADR 0002 — Bake Immutable Artifacts, Deploy at Runtime

**The Pattern**: Bake immutable source into image at `/opt/` path. Deploy from `/opt/` onto the volume at entrypoint runtime, idempotent/marker-guarded.

**Phase 5 additions checked:**

1. **Plugin config seeding** (`setup_plugin_configs()` §seed-if-absent logic): Seeds `config.json` from the deployed plugin dir (which `deploy_plugins()` already placed from `/opt/asaapi/` baked content) into the host-bind `plugins-config/` path if absent. This is a config-seeding step, not a binary-deployment step. It operates at runtime on the volume — consistent with ADR 0002's pattern. The image bakes the default configs (inside `/opt/asaapi/ArkApi/Plugins/*/config.json`); the entrypoint seeds them to the host bind on first boot. This is the natural extension of the bake-to-/opt + deploy-at-runtime pattern. ✓

2. **`inject_plugin_db_config()` mutates config.json at boot**: This function writes DB credentials into the host-bound config.json using `jq`. The mutated file is on the volume (via the symlink to the host bind). This is consistent with ADR 0002's pattern: the file is on the volume, the mutation happens at runtime, it is idempotent (re-running with the same env produces the same file). ✓

3. **`jq` tool placement**: `jq` is used by `inject_plugin_db_config()` at runtime but is an OS package baked into the Dockerfile. ADR 0002 §Decision says "Bake the immutable source into the image... Deploy from `/opt/` onto the volume at entrypoint runtime." An OS-package tool (`jq`) used at entrypoint runtime is not a deployable artifact in the ADR's sense — it is a build dependency (like `curl`, `unzip`). The ADR governs deployable artifacts (installer binaries, plugin DLLs), not OS build dependencies. The `jq` placement follows the Dockerfile rule for OS packages (immutable, build-time, same category as the existing `unzip`). No tension with ADR 0002. ✓

4. **`plugins-config/` host bind**: The `./plugins-config:/home/container/plugins-config` bind in `docker-compose.yml` is runtime state — a host directory path. ADR 0002 governs bake-to-image artifacts, not compose-level bind mounts. This is orthogonal to ADR 0002's scope and introduces no contradiction. ✓

5. **No new `/opt/` artifacts introduced**: Phase 5 does not add new baked artifacts to the image. All image-baked content was established in Phases 2 and 3 (`/opt/asaapi/`, `/opt/vcredist/`). Phase 5 is purely a runtime-wiring phase. ADR 0002's bake-pattern is already in effect and not modified. ✓

**Summary for ADR 0002**: Phase 5 is a pure entrypoint-runtime phase. All new operations (config seeding, symlink setup, credential injection) run at boot on the volume — consistent with the ADR's pattern. The `jq` binary as a build-time OS package addition does not interact with the ADR's artifact-deployment scope. **No contradiction.**

---

### Design Divergences Check

**Plan's `## Design Divergences` table**: Contains one recorded divergence — the `AsaApiLoader.exe` launch row being transiently unmet through Phases 1–3. That divergence was closed by Phase 4 (the launcher flip). The divergence entry does not cover any Phase 5 change.

**New divergences needed for Phase 5**: None. Every Phase 5 placement passes the 3-question test without requiring an exemption. No `[locked]` doc is contradicted.

---

### Required Fixes (BLOCK only)

None — no design-doc contradictions found.

---

### Concerns (aspirational contradictions — non-blocking)

None. The registry contains no `[aspirational]` entries. No concerns to record.

---

### Project-vs-Global Overrides

N/A — single project registry, no scope conflict.

---

### Bottom Line

Every Phase 5 touch hits the right side of the build/runtime split — `jq` baked as a fixed OS dep at build time, all runtime logic (config seeding, symlink setup, credential injection via `jq`) correctly placed in the entrypoint where the volume exists. MariaDB is reached via service name `mariadb:3306` with no host exposure, the `inject_plugin_db_config()` jq filter wires up exactly what ADR 0001 specifies, and nothing in Phase 5 changes or weakens any `[locked]` doc. Clean phase.

OVERALL VERDICT: PASS
