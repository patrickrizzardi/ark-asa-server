# Handoff — Phase 3 (m3-cluster)

**Resume-at pointer:** `phase-3/step-6`

## Follow-up segment (session `8c4255f4-dc90-4012-9ecd-287cd28f9794`, 2026-07-06)

Two mechanical, non-step text fixes only — resume pointer UNCHANGED, still `phase-3/step-6`:
- Applied FRAGO 006 to `plan.md` Phase 3 Step 1 text: rewrote the stale single-anchor prose to
  describe the real `&ark-server` (build/image/depends_on/stop_grace/restart/logging) +
  `&ark-common-env` (shared env, merged inside each service's own `environment:`) two-anchor
  structure, with `volumes:`/`ports:` fully restated per service (no YAML merge for sequences).
  Verified against the live `docker-compose.yml` (lines 14-36, 112-162) — prose now matches code.
- Fixed the stale `docker compose restart the-center` (singular) command reference in
  `docs/internal/design/economy/shop.md:278` → `the-center genesis`, same staleness class already
  fixed in `README.md`'s cluster section this phase.
- No code (`docker-compose.yml`, `entrypoint.sh`, `Dockerfile`) touched. Nothing committed — left
  staged/uncommitted for the conductor's CONFIRM-mode commit gate.

## Steps done this segment (session `ec937db0-96ea-4c68-9108-58dafc4fd5f6`, 2026-07-06)

Steps 1-5 of Phase 3 are COMPLETE:

1. `docker-compose.yml` refactored: `&ark-server` anchor (build/image/depends_on/stop_grace_period/
   restart/logging) + `&ark-common-env` anchor (all shared env keys — MAX_PLAYERS, ARK_ADMIN_PASSWORD,
   UPDATE_ON_BOOT, SAVE_ON_STOP, ENABLE_BATTLEYE, ENABLE_ASAAPI, MODS, ARK_CLUSTER_ID, CLUSTER_DIR,
   WINEDEBUG, all MARIADB_*/ARKSHOP_DB_* vars).
2. Two services defined via `<<: *ark-server`: `the-center` (container_name `ark-the-center`,
   SERVER_MAP `TheCenter_WP`, SESSION_NAME `${SESSION_NAME:-ARK-Test}`, ports 7777/udp+27020/tcp via
   `CENTER_GAME_PORT`/`CENTER_RCON_PORT`) and `genesis` (container_name `ark-genesis`, SERVER_MAP
   `Genesis_WP`, SESSION_NAME `"${SESSION_NAME:-ARK-Test} - Genesis"`, ports 7779/udp+27021/tcp via
   `GENESIS_GAME_PORT`/`GENESIS_RCON_PORT`). Each service's `environment:` merges `<<: *ark-common-env`
   then adds its own SERVER_MAP/SESSION_NAME/SERVER_PORT/RCON_PORT.
3. Volumes block: `ark-game-center`, `ark-game-genesis` (new, per-map, NOT migrated from the old
   single-server `ark-game` volume — additive per plan.md:279), `ark-db` + `ark-cluster` (shared,
   unchanged names).
4. `.env.test.example` / `.env.prod.example` updated: added `CENTER_GAME_PORT=7777`,
   `CENTER_RCON_PORT=27020`, `GENESIS_GAME_PORT=7779`, `GENESIS_RCON_PORT=27021` + a 2-map-cluster
   layout comment block above `ARK_ADMIN_PASSWORD`.
5. `README.md`: new "## Cluster (multi-map)" section (One config every map / Per-map ports table /
   The clusterid secret / Transferring between maps — Genesis Mission Terminal ~85,63 Bog / Known
   limitation: Genesis-exclusive crate loot). Updated 3 stale single-service
   `docker compose restart the-center` mentions (Fast config loop, Plugin config edit loop, and the
   new Cluster section itself) to `docker compose restart the-center genesis`. Updated the Database
   section's singular "the game service" → "each map service". Updated Run section to note `up` now
   boots the whole cluster + Roadmap line to `**M3 (current)**`. No stale `plugins-config` mentions
   were found in README (already clean from Phase 2).

## Decisions/invariants discovered this segment

- **YAML merge-key mechanics forced a 2-anchor design**, not the single `&ark-server` anchor Step 1's
  prose might suggest literally: `<<:` replaces a key's value WHOLESALE on override, so a per-map
  override of just `SERVER_MAP`/`SESSION_NAME`/ports inside `environment:` requires `environment:` to
  NOT be part of the anchor that also needs full per-service replacement — hence `&ark-common-env` is
  a separate nested anchor, merged inside each service's own `environment:` block alongside its
  per-map keys. This is an implementation-mechanics necessity, not a deviation from Step 1's intent
  (recorded in the Quality-gate item 1 evidence in plan.md).
- **`volumes:` and `ports:` cannot be partially inherited either** (same YAML limitation — no
  element-wise list merge) — each service fully restates its own `volumes:`/`ports:` list (the 2
  shared mounts repeated verbatim, the 1 unique game volume differing). This is why the shared
  `./config` + `ark-cluster` mounts appear literally in both services rather than via the anchor.
- **`ENABLE_ASAAPI` stays in the shared `&ark-common-env` anchor**, not overridden per-service — Step
  2's override list does not name it, so both maps read the SAME toggle value. The Phase 3 AC "
  `ENABLE_ASAAPI=0` on a service still produces vanilla rollback for that map" verifies the existing
  Phase 1/2 invariant continues to hold when read by 2 services, not independent per-map toggling.
- **The-Center's game volume is now `ark-game-center` (NEW), not the pre-existing `ark-game`
  volume.** Per plan.md:279 ("Additive volumes... existing `ark-game`/`ark-db` data is not migrated or
  destroyed"), this is an intentional, already-decided design choice — but it means The Center's FIRST
  boot post-Phase-3 on dell will re-download the ~13GB install fresh (same as Genesis), not reuse
  dell's already-installed `ark-game` volume. Worth flagging to Patrick before Step 6 deploy so the
  slower first boot isn't a surprise (the old `ark-game` volume is simply orphaned, not destroyed).

## Verification receipts (orientation paid this segment)

- **`docker compose config` — compose file parses clean, both services resolve correctly.** Verified
  TWICE: (1) with `ARK_CLUSTER_ID` unset (empty-default path — the single-server M2 invariant) and
  (2) with `ARK_CLUSTER_ID=my-secret-cluster` set (the cluster-active path, never previously exercised
  per Phase 1's own note). Both runs exit 0, no errors. Tree state verified against: the
  `docker-compose.yml` / `.env.test.example` / `.env.prod.example` content as committed by THIS
  segment (not yet git-committed to a branch — working tree only, no commit SHA yet). A resuming
  segment does not need to re-run this compose-parse check unless it changes `docker-compose.yml` or
  the env-example files again.
- **No live boot, no dell access, no in-game action was performed or attempted this segment** — Steps
  6-7 and all Acceptance Criteria requiring live behavior are genuinely untouched, not just
  unconfirmed. This is a hard capability gap (this executor dispatch has no dell/game access), not a
  scoping choice.

## Build + test status

Green-building tree: `docker-compose.yml` is valid YAML, `docker compose config` resolves both
services with no port/volume collisions, distinct container names, shared clusterid+cluster-volume+DB
env. No code (entrypoint.sh/Dockerfile) was touched this phase — out of Phase 3's declared file scope.
Nothing is broken; nothing has been deployed.

## What remains (gated on Patrick + dell — NOT this executor's to do)

- **Step 6**: `git pull` + `docker compose up -d --build` on dell, boot both services.
- **Step 7**: the Genesis Mission Terminal (~85,63 Bog biome) bidirectional transfer gate — Patrick
  in-game, BEFORE treating Center↔Genesis as the transfer proof.
- All 7 remaining unchecked Acceptance Criteria (boot-advertise, transfer-bidirectional,
  checkable-transfer-artifact, move-not-dupe, concurrent-shutdown GUS integrity, shared points via
  RCON, config/loot consistency pop-test) + the `ENABLE_ASAAPI=0` rollback AC — all require the live
  dell boot + Patrick in-game/RCON actions this executor cannot perform.
- The optional adversarial clusterid-gate Quality-gate check (also live-only).
- Phase Review Gates (all 5 reviewers) have not run yet — this phase has not been through review or
  been committed; no PR/branch created yet (`feat/m3-multi-map-cluster` per plan.md:1115 not yet cut).
