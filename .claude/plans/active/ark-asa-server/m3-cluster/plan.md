---
slug: m3-cluster
type: execution
owner: Patrick
status: active
roadmap: ark-asa-server
milestone: m3-cluster
files:
  - docker-compose.yml
  - entrypoint.sh
  - Dockerfile
  - .env.prod.example
  - .env.test.example
  - config/**
  - docs/internal/decisions/**
  - docs/internal/reference/beacon-asa/**
  - README.md
  - .claude/design-sources.md
  - .claude/rules/build-time-vs-runtime.md
  - .gitignore
created: 2026-06-22
last_updated: 2026-07-06
session-id: ["46d42803-00ea-46b6-9744-f1dd992ba974", "d7c269b0-2ae5-436b-b487-ea3d1b8ef35d", "74db45a6-a185-4885-a2b3-f3045dba37fa"]
plan_base: main
depends_on: [m2-shared-economy-store]
---

# Plan: M3 — Cluster (one economy + one config across maps)

Created: 2026-06-22
Last revised: 2026-07-05 — map set changed 3→2 (The Center + Genesis Part 1; Aberration removed), new Genesis/Beacon loot-gap risk scored, `entrypoint.sh` line anchors refreshed to current file.
Status: active — approved at Gate 4 by Patrick (2026-07-06), cleared 2 plan-reviewer rounds (0 blockers). Ready for `/execute-plan`. The frontmatter `status: active` is the single source of truth per REF-plan-format.

## Context & Why

**Goal**: Turn the proven single-server M2 stack (one map + AsaApi/ArkShop + shared MariaDB)
into a **multi-map cluster** where players move their character/dinos/items between maps via
ASA's native cluster transfer, keep ONE points balance (shared MariaDB — already in place from
M2), and every map runs **identical rules** (loot, shop catalog, breeding, permissions) without
the operator hand-editing N copies of the config.

**Why**: This is the project's headline differentiator — the "thing a managed host (Nitrado)
can't do." M1 gave a lean fast-boot image; M2 gave the economy on one server backed by a real
shared DB. The DB was deliberately built as a real MariaDB service (not SQLite) precisely so M3
can add servers with **zero teardown** (roadmap Ordering Rationale, M2). M3 cashes that in.

**Background (what exists today)**:
- Single `the-center` service in `docker-compose.yml` (`container_name: ark-the-center`; hardcoded
  ports 7777/udp + 27020/tcp), one `ark-game` volume, one shared `mariadb` service, host-bound
  `./config` + `./plugins-config`. **Stale-default caveat (verified against the real file
  2026-07-05):** the service is already named `the-center`, but its committed `SERVER_MAP` default
  is still `${SERVER_MAP:-TheIsland_WP}` (`docker-compose.yml:63`) — the map value was never flipped
  when the service was renamed. Phase 1 flips this default to `TheCenter_WP` so the regression base
  genuinely defaults to The Center (a bare `docker compose up` today would run Island on a service
  named "center").
- `entrypoint.sh` builds the launch query string at line 574 — **no `-clusterid` / no
  `-ClusterDirOverride` today** (single server never needed them).
- The engine reads its INIs via a symlink: `ShooterGame/Saved/Config/WindowsServer` →
  `/home/container/config` (the host bind `./config`) — entrypoint.sh:455-458.
- `Game.ini` (1.2 MB — the loot tables) is **never rewritten by the server** (verified clean on
  dell post-boot). `arkshop.config.json` already deploys from a repo seed each boot.
  `GameUserSettings.ini` **is rewritten by the server on shutdown** (the comment-stripping
  already documented in loot/shop notes).
- MariaDB economy is shared-ready as-is: a second server pointing at the same `mariadb:3306`
  shares points immediately — that capability is M2's, M3 just adds the second consumer.

**The gap**: everything is wired for exactly one game server. M3 must (a) wire ASA's cluster
transfer, (b) make config shareable across N servers WITHOUT the per-server GUS rewrite
clobbering a shared file, and (c) replicate the single service into N map services that boot
together on dell.

**Success criteria** (done AND done right):
1. 2 map servers (`TheCenter_WP`, `Genesis_WP`) boot together on dell, each
   advertising for join on its own port.
2. A player can **transfer** a character (and a dino + an item) from one map to another via the
   in-game "Travel to another ARK" flow (a **Mission Terminal** on Genesis Part 1, which has no
   obelisk; a standard obelisk/transmitter on The Center) — proving `-clusterid` +
   `-ClusterDirOverride` + the shared cluster volume work.
3. Points are **shared**: `SetPoints` on one server's RCON is visible on another server (same
   MariaDB) — confirms the M2 economy spans the cluster.
4. Config is **consistent** across both maps via ONE uniform model — every config is a fresh
   per-server copy from its repo canonical each boot (repo wins), so editing the repo once +
   restart changes every map:
   - `Game.ini` (loot + breeding) — straight copy from `config/Game.ini`.
   - `GameUserSettings.ini` (tuning + transfer flags) — copy from `config/GameUserSettings.ini`, identical except injected per-server `SessionName`.
   - ArkShop `config.json` (shop catalog) — copy from `config/arkshop.config.json` + injected `Mysql`.
   - Permissions `config.json` — copy from `config/permissions.config.json` + injected `Mysql`; live group data is in the shared MariaDB.
5. `ENABLE_ASAAPI=0` still produces a byte-for-byte vanilla rollback per server (M2 invariant
   preserved).

## Research Findings

**ASA cluster mechanics** (verified current 2026 — knowledge cutoff is Jan 2026, so this was
web-confirmed, not assumed):
- `-clusterid=<id>`: must be **identical on every server** in the cluster. Treated like a
  password — pick a non-obvious value, never the default "cluster"/"ark". Servers with different
  IDs won't see each other's transfers even on the same directory.
- `-ClusterDirOverride=<path>`: cluster transfer files are saved under `<path>/<clusterid>`.
  **All servers must point at the same directory.** If two servers share a clusterid but NOT the
  directory, players see each other on the transfer list but downloads silently fail (no data
  moves). Default (unset) is `ShooterGame/Saved/clusters` — per-container, so transfers would
  break. → In Docker: one shared volume mounted into every map container at the same path.
- Each server runs a **different map**; transfer happens via the in-game obelisk / Tek
  Transmitter / drops (or a **Mission Terminal** on maps with no obelisk, e.g. Genesis Part 1)
  "upload" → "Travel to another ARK" → "download" on the destination map.
- Transfer **expiration times** (`TributeCharacter/Item/DinoExpirationSeconds`) should be
  identical cluster-wide — they already are in our `GameUserSettings.ini` (all `=3600`), and
  the shared-config layer keeps them so.
- Sources: [Steam ASA cluster discussion](https://steamcommunity.com/app/2399830/discussions/0/3881599433115900494/),
  [XGamingServer ASA cluster docs](https://xgamingserver.com/docs/ark-survival-ascended/cluster-setup),
  [ASA Server Manager cluster guide](https://arkascendedservermanager.com/how-to-setup-a-cluster-server/).

**Transfer-gate flags** (verified in `config/GameUserSettings.ini`): `PreventDownloadItems/Dinos/
Survivors` and `PreventUploadItems/Dinos/Survivors` are all `=false`, and `NoTributeDownloads=false`
— i.e. transfers are already permitted. The shared-config layer keeps these uniform across the
cluster (divergent values = one-way or broken transfers).

**The unified config model (Patrick's decision, refined during review):** ALL four config files
follow ONE model — **repo canonical → fresh per-server copy on boot → repo wins (runtime edits
discarded).** No per-config special-casing, no shared writable files, no concurrent-boot races.

| Config file | Repo canonical (read-only source) | Per-server deploy target (writable, per-map game volume) | Per-server tweak on copy |
|---|---|---|---|
| `Game.ini` (loot/breeding) | `config/Game.ini` (exists) | `…/WindowsServer/Game.ini` | none (straight copy) |
| `GameUserSettings.ini` (tuning + transfer flags) | `config/GameUserSettings.ini` (exists) | `…/WindowsServer/GameUserSettings.ini` | inject `SessionName=${SESSION_NAME}` |
| ArkShop `config.json` (shop catalog) | `config/arkshop.config.json` (exists) | per-server ArkShop plugin dir | inject `Mysql` block (existing step) |
| Permissions `config.json` | `config/permissions.config.json` (**NEW — captured from image default**) | per-server Permissions plugin dir | inject `Mysql` block if applicable |

**Why uniform per-server (the race that drove it):** `docker compose up` starts all N servers
**simultaneously**. If plugin configs deployed to ONE shared `./plugins-config` bind (today's
model), all N would `cp` + `jq`-inject the SAME file at once — the `cp` (entrypoint.sh:338) is not
atomic, so a server can read a half-written file mid-copy → `jq` parse error → loud boot failure.
Per-server copies eliminate every cross-server write. The repo canonicals are mounted read-only
via the `./config` bind (shared, never written at runtime → safe to share); only the per-server
*copies* are writable, and they live on each map's own volume.

**Consequence**: the shared `./plugins-config` host bind is **removed** — its only purpose was the
edit-on-host loop, now replaced by deploy-from-repo (edit `config/*.json` → push → restart).
Permissions flips from edit-on-host (seed-if-absent) to deploy-from-repo; safe because live
permission-group data lives in the shared MariaDB, not in `config.json` (Patrick's call).

The per-server identity that genuinely differs (map name, game port, RCON port, SessionName,
the shared clusterid) is **already env/launch-arg-driven** (entrypoint.sh:556) and does NOT live
in the shared canonicals — that's what makes the read-only `./config` bind safe to share.

**Multi-server in compose**: Docker Compose has no native loop. For 2 services the right tool is
YAML anchors (`&ark-common` / `<<: *ark-common`) to share the bulk of each service definition and
override only map/ports/volumes/container_name. A compose generator is explicitly **out of scope**
(that's M4 ops-tooling territory — building it now is "build the engine before shipping value").

**Map set + class-string provenance (2 maps: The Center + Genesis Part 1):**
- `TheCenter_WP` (The Center) — **verified** from the local Beacon snapshot
  `docs/internal/reference/beacon-asa/maps.tsv:7` (`The Center\tTheCenter_WP`). This is the plan's
  existing single-server map, unchanged.
- `Genesis_WP` (Genesis Part 1) — **verified** on 2026-07-05 directly from the actual shipped game
  files on the deployed dell server: `strings` over the packed `.utoc` IoStore containers under
  `ShooterGame/Content/Paks/` surfaces `Genesis_WP.umap` as a standalone persistent-level file,
  matching the naming shape of the other confirmed maps (`TheCenter_WP.umap`, `ScorchedEarth_WP.umap`).
  This class string is **NOT** taken from the Beacon snapshot: that snapshot is dated 2026-06-21
  (see `beacon-asa/README.md`), predates today's Genesis Part 1 release, and has **zero** Genesis
  Part 1 map/loot rows. (The `Genesis`/`Genesis2` rows that DO appear in the snapshot's
  `creatures.tsv`/`engrams.tsv`/`ini_options.tsv` are Genesis **Part 2** content-pack rows and
  generic Genesis ini toggles — a different, earlier-released pack; do not conflate them with
  Genesis Part 1.)

**Genesis Part 1 has no Beacon loot data yet (a NEW enemy this map swap introduces).** The loot
generator (`tools/gen-loot.ts` + `tools/loot-design.ts`) resolves ALL supply-crate / item / creature
class strings from the local Beacon snapshot, per this repo's own rule
(`.claude/rules/documentation.md` §"Class strings … resolve from the local Beacon snapshot — never
guessed"). Beacon has zero Genesis-Part-1 `loot_containers.tsv` rows (verified — the snapshot's
`maps.tsv` has no Genesis row at all), so the generator cannot author custom crate tuning for any
crate class **exclusive** to Genesis Part 1. Crucially, this is **narrow**, not "Genesis boots
entirely vanilla": per `loot-crates.md` Locked Rule 1 the loot model is **class-keyed and global**
("All maps, one file … each map uses only its own [classes]"), so any Genesis crate that reuses a
standard/shared beacon crate class already present in `config/Game.ini` (the generic colored beacons)
**inherits the cluster's custom tuning automatically**. Only Genesis-*exclusive* crate classes serve
ASA vanilla loot until Beacon ingests the release. This is scored in the Risks table and parked as a
four-field deferral in Future Requirements. (The original Aberration-scoped plan never carried this
enemy — Aberration was fully resolvable in the 2026-06-21 snapshot at `maps.tsv:4`.)

**Genesis Part 1 cross-ARK transfer — WEB-CONFIRMED: supported, but via a DIFFERENT mechanism (no
obelisks).** The pak-string check (Ledger #9) proved `Genesis_WP` *exists*; a separate question is
whether it supports the transfer flow Success Criterion 2 / the Phase 3 transfer AC depend on — which
matters more now that **Center↔Genesis is the ONLY transfer pair** on the 2-map set. This was
web-confirmed by the conductor (multiple community sources, 2026-07-05; consistent with the ASE
precedent), so it is a real `verified` finding, not recollection:
- **Genesis Part 1 has NO obelisks at all** — a structural map-layout fact, stable across the ASE→ASA
  remaster. The standard "walk to the obelisk → Travel to another ARK" flow **does not exist** on this
  map. A Phase 3 transfer test that says "go to the obelisk" would be untestable on Genesis.
- **What Genesis Part 1 uses instead (both directions — upload FROM and download TO Genesis work):**
  1. **Mission Terminals** — fixed map locations (community sources cite one around **~85, 63** in the
     Bog biome) that behave like Extinction's City Terminals (transfer-only, no build menu). This is
     the **primary + accessible** method — **no tech-tier prerequisite**, so it is what the Phase 3
     test should use.
  2. **A player-built Tek Transmitter** — the standard cross-map transfer structure; works on Genesis
     too, but requires reaching late-game **Tek tier** to craft (an unnecessary grind just to prove
     wiring — avoid for the test).
- **Not relevant to our test:** Titans specifically cannot transfer to Genesis; the plan's transfer
  test moves a character + a dino + an item, never a Titan, so this restriction does not apply.
- **What still needs the live test:** research confirms the map *design* (mechanism + bidirectionality),
  **not** this specific server's live behavior — so the Phase 3 step-7 gate still runs a real
  Center↔Genesis transfer via the Mission Terminal to confirm it works in practice. The residual risk
  shrinks from "might not support transfer at all" to "uses a terminal not an obelisk — now documented —
  and live behavior is confirmed once at Phase 3."

## Decision Ledger

| # | Decision / claim | Class | Citation / recorded answer |
|---|---|---|---|
| 1 | Launch string has no `-clusterid`/`-ClusterDirOverride` today; both must be added | verified | `entrypoint.sh:556` (query string) + `:559-564` (flags) — neither token present |
| 2 | Engine reads INIs via `WindowsServer` symlink → host `./config` bind | verified | `entrypoint.sh:455-458` (`ln -sfn /home/container/config "$config_link"`) |
| 3 | `Game.ini` is never rewritten by the server (safe to share read-only) | verified | state.md loot-deploy note: dell `git status` clean post-boot; Game.ini retains comments |
| 4 | `GameUserSettings.ini` IS rewritten by the server on shutdown (cannot be a shared writable file) | verified | state.md loot/shop notes ("ARK rewrites GameUserSettings.ini & nukes comments"); `;METADATA=` header at config/GameUserSettings.ini:1 |
| 5 | ArkShop `config.json` already deploys from a repo seed each boot (deploy-from-repo pattern) | verified | `entrypoint.sh:337-339` (`cp "${shop_seed}" "${host_dir}/config.json"`) |
| 5b | Permissions `config.json` is currently seed-if-absent from the image default (today's behavior, being changed) | verified | `entrypoint.sh:340-343` (`[[ ! -f host config ]] && cp image-default`) |
| 5c | Concurrent-boot race: N servers sharing ONE plugin-config file would `cp`(non-atomic)+`jq` it simultaneously → torn read → loud boot fail. `docker compose up` starts services in parallel | verified | `entrypoint.sh:338` (plain `cp`, not atomic) + Compose default parallel start (services share no inter-dependency) |
| 5d | UNIFIED config model = repo canonical → fresh per-server copy each boot, repo wins, for ALL 4 configs (Game.ini, GUS, ArkShop, Permissions) | needs-Patrick | Patrick: "do both as a fresh copy on boot… less conditionals, same result" + chose "Deploy-from-repo (full uniformity)" for Permissions |
| 5e | Permissions live group data lives in the shared MariaDB (not config.json) → flipping Permissions to deploy-from-repo is safe | design | ArkShop Permissions plugin stores groups in its DB tables (shared `mariadb` from M2); config.json is bootstrap only |
| 6 | Transfer flags already permit transfers; must stay uniform cluster-wide | verified | `config/GameUserSettings.ini` `PreventUpload/Download*=false`, `Tribute*ExpirationSeconds=3600` |
| 7 | Single `the-center` service (`container_name: ark-the-center`), hardcoded host ports 7777/udp + 27020/tcp. Committed `SERVER_MAP` default is still the stale `TheIsland_WP` — flipped to `TheCenter_WP` in Phase 1 so the base defaults to The Center | verified | `docker-compose.yml:50-114` (service `the-center` `:50`, ports `:59-61`, `SERVER_MAP` default `:63`) |
| 8 | MariaDB economy is already shareable; a 2nd server at `mariadb:3306` shares points with no new work | verified | `docker-compose.yml:26-48` (mariadb svc) + `:86-93` (server → `mariadb:3306`) |
| 9 | Genesis Part 1 map class string = `Genesis_WP` | verified | `strings` over the packed `.utoc` IoStore containers under `ShooterGame/Content/Paks/` on the deployed dell server (2026-07-05) shows `Genesis_WP.umap` as a standalone persistent-level file, same naming shape as the other confirmed maps. **NOT** from `beacon-asa/maps.tsv` — that snapshot (2026-06-21) predates the release and has zero Genesis-P1 rows (its `Genesis`/`Genesis2` rows are Genesis **Part 2** content, a different pack). `TheCenter_WP` resolves from `beacon-asa/maps.tsv:7`. Durability: the pak-string evidence lives on the deployed volume (game paks are never repo-checked-in per build-time-vs-runtime), but the class string is **re-verified loudly at Phase 3 boot** — a wrong map class fails the server start outright (not a silent no-op like a wrong crate class), so a bad value cannot pass the Phase 3 advertise AC. |
| 10 | Maps for M3 cluster = The Center + Genesis Part 1 (2 maps) | verified | Operator's chosen set: `TheCenter_WP` (existing single-server map, unchanged) + `Genesis_WP` (freshly released). Replaces the earlier Island+Center+Aberration trio. Class strings per #9. |
| 11 | GUS config model = deploy-from-repo seed (canonical in repo → entrypoint copies to per-server writable path + injects SessionName) | needs-Patrick | Patrick selected "Deploy-from-repo seed" |
| 12 | M3 gate validated by running the full cluster on dell (all maps up simultaneously) | needs-Patrick | Patrick: "yyea you can test 2 on dell" (confirmed multi-server local test) |
| 13 | Per-server game volumes (each map gets its own `ark-game-<map>` volume; ~13GB install each) | design (named tradeoff) | See Risks + Phase 1; shared-install optimization deferred to M4 with trigger |
| 14 | clusterid stored as a secret in `.env` (`ARK_CLUSTER_ID`), not committed | design | Mirrors `ARK_ADMIN_PASSWORD` / DB secrets handling (`docker-compose.yml:66`) |
| 15 | Genesis-Part-1-EXCLUSIVE crates serve ASA vanilla loot until Beacon ingests the release — accepted as a four-field deferral, NOT hand-authored | design (named deferral) | Hand-authoring would require guessing Genesis-P1 crate class strings Beacon can't confirm; `rules/documentation.md` forbids guessing (a wrong class = silent no-op, worse than transparent vanilla). Shared/standard beacon crates are already covered class-wide (`loot-crates.md` Rule 1). Full four-field deferral in Future Requirements; risk scored MEDIUM (recorded). |
| 16 | Genesis Part 1 supports **bidirectional** cross-ARK transfer via **Mission Terminals** (no obelisks exist on the map) — the Phase 3 transfer test uses the terminal, not an obelisk | verified | Web-confirmed 2026-07-05 (conductor, multiple community sources): Genesis has zero obelisks (structural map fact, stable ASE→ASA); transfer is via Mission Terminals (~85,63 Bog biome; transfer-only, no tech-tier grind) + player Tek Transmitters, both directions. Titans can't transfer to Genesis (irrelevant — test moves a character/dino/item). Live behavior confirmed at Phase 3 step 7. See Research Findings + Risks. |

## Risks

Scored deterministically per **REF-risk-engine** (the frozen cross-project risk spec):
Prob **A–E** (Frequent→Unlikely) × Sev **I–IV** (Catastrophic→Negligible) → matrix lookup; a proven
mitigation shifts ONE axis by its bucket step (**B1** eliminate/automate −2 · **B2** engineered guard
−1 · **B3** human-vigilance 0, gate-only) then re-lookup. **Result: every residual is M or L — none
land HIGH/EX-HIGH, so no signed RISK OVERRIDE is required.** Recorded MEDIUMs with a post-plan revisit
trigger are parked in Future Requirements. Where the formal Sev differs from a gut "high-impact" read,
the reason is reversibility: the matrix scores blast radius over {money,data,prod-state,security,
irreversibility} with reversibility as a floor — a fully-recoverable config fix is Marginal even when
the *feature* it breaks is headline.

| Risk | Prob | Sev | Initial | Mitigations (bucket → axis shift) | Residual | Gate |
|------|:----:|:---:|:-------:|-----------------------------------|:--------:|------|
| GUS deploy-from-repo flip discards an in-game admin's runtime GUS edits | C | IV | L | Documented + intended (repo is source of truth; README edit-`config/`→push→restart; in-game GUS edit was never the supported loop) — B3 doc, 0 | **L** | pass |
| Shared cluster dir wrong → players see transfer list but downloads **silently** fail | B | III | M | ONE named `ark-cluster` volume at the SAME path in every service via the shared anchor; **Phase 3 AC requires a REAL transfer with a checkable artifact** (transfer file on the shared volume, read from a *different* service) — a build-blocking verification (B2, prob −1 → C). *Sev III not II:* nothing is destroyed (character/items stay safe on the source map), fully reversible (fix path + restart); the "silent" part is a detection concern the real-transfer AC closes. `lookup(C,III)` | **M** | recorded |
| clusterid mismatch across services → no cross-server visibility | C | III | M | ONE `ARK_CLUSTER_ID` in `.env` consumed by every service via the shared YAML anchor, never per-service — the value is defined once and inherited, so divergence is **structurally eliminated** (B1, prob −2 → E). `lookup(E,III)` | **L** | pass |
| 2× ASA on dell (8 cores / 64 GB) — CPU contention | D | III | L | RAM fits (~20 GB of 64); 8 cores / 2 servers is comfortable for a no-player transfer test; real player load is a VPS concern (out of scope) — design headroom | **L** | pass |
| Per-server first boot re-downloads ~13 GB × 2 (slow first cluster boot) | A | IV | M | One-time cost; subsequent boots skip-validate (fast); disk not a stated constraint. Inherent (no score-moving mitigation) but self-resolves after first boot. `lookup(A,IV)` | **M** | recorded (trivial) |
| **Genesis Part 1 has NO Beacon loot data → Genesis-EXCLUSIVE crates serve vanilla loot** (NEW enemy from the map swap) | B | III | M | NARROW, not "Genesis all-vanilla": `loot-crates.md` Rule 1 makes loot overrides class-keyed + global, so Genesis crates reusing standard/shared beacon classes already in `config/Game.ini` inherit the custom tuning; only Genesis-*exclusive* classes miss. Hand-authoring rejected (never-guess rule — a guessed class is a silent no-op). Four-field deferral + README/AC doc — B3, 0. `lookup(B,III)` | **M** | recorded → Future Reqs (trigger = Beacon ingests Genesis P1) |
| **Genesis Part 1 transfers via Mission Terminals, not obelisks** (web-confirmed) — the transfer-proof method differs from the obelisk flow; gates the headline proof (Center↔Genesis is the ONLY transfer pair on a 2-map set) | D | III | L | **Web-confirmed (2026-07-05, conductor):** Genesis has NO obelisks but DOES support **bidirectional** cross-ARK transfer via **Mission Terminals** (~85,63 Bog biome; transfer-only, no tech-tier grind) + player Tek Transmitters — see Research Findings. Confirming the *mechanism* dropped prob from the earlier **B** ("might not support transfer at all") to **D** (design confirmed; only live-server behavior could surprise). Phase 3 step 7 still confirms live behavior via the terminal (B3 detection, 0). `lookup(D,III)` | **L** | pass (Phase 3 terminal test confirms live) |
| Port collision on dell (2 game + 2 RCON ports) | D | III | L | Distinct documented host ports (7777/7779 udp; 27020/27021 tcp) in compose + `.env` examples — B1 design | **L** | pass |
| Changing the `WindowsServer` symlink model breaks the M1/M2 single-server config loop | B | III | M | Phase 2 regression-guard boots `the-center` ALONE + real-file/inject checks before the multi-service compose lands (B2, prob −1 → C); **and** revert-compose-to-one-service is a tested known-good backout to the M2 state (B1, sev −2 → IV). Two different patterns, two axes. `lookup(C,IV)` | **L** | pass |
| **Silent DB-less plugin boot** — the Phase 2 mysql-inject rework (real-file `mv`, symlink-resolution removed at entrypoint.sh:352-387) silently no-ops the DB-settings write, OR the committed Permissions seed lacks its flat root-level `UseMysql` key so the `has("UseMysql")` guard (`:508`, loud-WARN fallback `:512`) skips injection — the plugin's real schema is FLAT (root-level `UseMysql`/`Mysql*` keys, NOT a nested `Mysql` block; ADR 0004 §Consequences) → ArkShop/Permissions boot connected to NO DB with no loud error (economy silently broken). *Named in Phase 2 step 6.* | C | III | M | *Prob C:* a mechanical simplification of the inject path (removes the readlink special-case; atomic `mv tmp cfg` onto a real file is the standard jq-write idiom already used for the shop seed) — failures are edge cases (seed over-stripped of its flat root-level `UseMysql`/`Mysql*` keys, a jq quirk), not novel logic. **Mitigation = Phase 2 build-blocking ACs, not documentation:** `jq .Mysql` on the ArkShop config (nested schema) AND `jq '{UseMysql,MysqlHost,MysqlUser,MysqlPass,MysqlDB,MysqlPort}'` on the Permissions config (flat schema — FRAGO 003) must show the injected host/user/db, AND the committed `config/permissions.config.json` seed must carry the flat root-level `UseMysql`/`Mysql*` keys — the phase **cannot pass its dell regression gate** if the inject silently no-ops, so a DB-less boot **cannot ship** (a build-blocking verification that reproduces the failure → B2, prob −1 → D). Sev III (recoverable: fix inject + restart; the DB and its data are untouched). `lookup(D,III)` | **L** | pass |
| ASA upload/download can DUPE dinos/items if a server crashes mid-transfer | D | II | M | Engine behavior, out of M3's control; `SAVE_ON_STOP` + clean shutdowns + documented ASA caveat in the ADR — B3 operational, 0. No money/irreversible **floor** fires (in-game items, admin-cleanable, "not money" per the Risk Assessment criteria). `lookup(D,II)` | **M** | recorded → Future Reqs (trigger = dupes observed, or ASA patches it) |

## Questions

None open. The map set is now a recorded decision — **The Center + Genesis Part 1** (Decision
Ledger #10), both class strings verified (Ledger #9). The prior open "which maps" question is
resolved.

## Risk Assessment & Rollout Strategy

**Risk level: MEDIUM**

| Criteria | Applies? | Notes |
|---|---|---|
| Touches payments/billing | No | Points are in-game currency, not money |
| Touches auth/permissions | Partial | ArkShop Permissions config shared across cluster — read-only, no new auth surface |
| Raw SQL / literals | No | ArkShop owns its schema; we add no queries |
| Modifies existing data | No | Additive — new services, new volumes; existing single-server data untouched |
| Third-party integration | Yes | ASA cluster transfer + ArkShop/AsaApi (already integrated in M2) |
| Changes existing endpoints | Yes | Changes the config-deployment behavior (GUS model) + the launch args for the existing server |

**Mitigations applied:**
- `ENABLE_ASAAPI=0` kill-switch per server (any → one level lower) — vanilla rollback preserved.
- Backward compatible: single-server `docker compose up` still works (Phase 2 regression check) → safe rollback by reverting compose to one service.
- Additive volumes (new per-map + shared cluster volumes); the existing `ark-game`/`ark-db` data is not migrated or destroyed.

**Rollout plan** (this is a self-hosted game server, not a SaaS — "rollout" = dell test → operator's VPS):
1. dell: boot `the-center` alone (Phase 2 regression) → confirm M1/M2 single-server loop intact.
2. dell: boot the full 2-map cluster (Phase 3) → confirm advertise + transfer + shared points + config consistency.
3. Operator (Patrick) deploys the same stack to the prod VPS — out of scope per roadmap (operator owns prod).

## Design Divergences

| Doc | What it says | What we do instead | Approved rationale (named cost + reversal path) |
|-----|-------------|-------------------|------------------------------------------------|
| — | — | — | _(empty — no divergences; this plan ADDs an ADR rather than contradicting one)_ |

## Documentation Deliverables

| Deliverable | Phase | Notes |
|---|---|---|
| ADR `docs/internal/decisions/0003-cluster-architecture.md` + `[locked]` registry entry | Phase 1 | clusterid + ClusterDirOverride + shared cluster volume; per-server full game volumes (named tradeoff vs shared-install M4 deferral); rejected alternatives. Registered `[locked]` in `.claude/design-sources.md`. |
| ADR `docs/internal/decisions/0004-shared-config-model.md` + `[locked]` registry entry | Phase 2 | The unified model: ALL config = repo canonical → fresh per-server copy each boot → repo wins. The concurrent-boot race that ruled out shared writable files; why GUS can't be shared; Permissions edit-on-host→deploy-from-repo flip (live data in shared DB); removal of the `./plugins-config` bind. Registered `[locked]` in `.claude/design-sources.md`. |
| NEW repo seed `config/permissions.config.json` | Phase 2 | Captured from the image-default Permissions config; the deploy-from-repo canonical for Permissions |
| `docs/internal/design/economy/shop.md` §11 update | Phase 2 | Deploy model changed from `plugins-config` host-bind → per-server plugin-dir; keep the doc accurate |
| `README.md` cluster section | Phase 3 | How to run the cluster locally, the edit→push→restart config loop, per-map ports, the clusterid secret |
| `README.md` Genesis loot-gap note | Phase 3 | State plainly that Genesis-Part-1-EXCLUSIVE supply crates serve ASA vanilla loot until the Beacon snapshot ingests Genesis Part 1 (generic/shared beacon crates are already custom per `loot-crates.md` Rule 1). Trigger to fix + how: re-pull Beacon (`beacon-asa/README.md` "Re-pulling") → `cd tools && bun run gen-loot.ts --write` → restart. This is the cheap in-scope mitigation that turns the Future-Requirements deferral into a documented, non-surprising limitation. |
| `.claude/rules/build-time-vs-runtime.md` table row (cluster dir) | Phase 1 | Cluster dir is volume-backed → entrypoint (3-question test: depends on mounted volume = yes) |

_(Per-phase doc-ACs live in their phases' Acceptance criteria block — not repeated here.)_

## Planned RED Repros

| What's intentionally broken | Locking RED test | Asserted contract | Fixing phase | Prod-exposure note |
|---|---|---|---|---|
| — | — | — | — | _(empty — this is infra/config work; validation is boot + in-game behavior, not unit tests. No intentional RED breaks.)_ |

## Behavioral Contract

_(No gate-shaped code in this plan — M3 is infrastructure wiring (compose services, volumes,
launch args, config deployment), not a predicate/filter/classifier deciding whether a
user-observable behavior fires. The entrypoint's `ENABLE_ASAAPI` branch is a pre-existing M2
launch-path switch, not new gate logic this plan introduces. Section intentionally empty.)_

| Gate (file/function or phase) | Input shape / fixture | Outcome (FIRE/DECLINE) | Why (spec/doc citation, not current behavior) |
|---|---|---|---|
| — | — | — | _(empty — no gate-shaped work in this plan)_ |

## Phase Execution Protocol

Each phase ends with an **Exit Sequence** — run those actions at every phase boundary (persist
plan state → persist deviation scratch → fan out all reviewers + N deviation-judges in parallel →
coordinator writes Evidence + Phase Review Gates → handle verdicts → prompt commit). The canonical
fan-out spec is `~/.claude/commands/execute-plan.md` Step 3.d–3.h.

**Checkpoint segmentation.** All three phases exceed REF-plan-format's >5-step fat-phase trigger
(Phase 2 also trips the heavy/load-bearing-step trigger), so each carries `**CHECKPOINT**` marks at
coherent green-tree seams (per REF-plan-format "Checkpoint marks"). A checkpointing executor MAY hand
off at any mark via `handoff-phase-<N>.md` with the canonical `phase-<N>/step-<K>` resume pointer;
each mark names a describable, buildable/bootable state so a fresh segment resumes without
re-orientation. Marks are advisory segmentation seams, not extra review gates — the phase's single
Exit Sequence still runs once at the phase boundary.

**Final phase additionally**: verify all phases' ACs/quality-gates accurate; fan out the full
reviewer-and-judge set with `model: "opus"` against the cumulative diff; flip `status: active` →
`status: done` only after all return PASS (radar then moves the whole `m3-cluster/` folder to
`plans/done/`).

## Phases

### Phase 1: Cluster wiring — clusterid + shared cluster volume + full parameterization
**PR scope**: Add ASA cluster transfer args to the launch, a shared cluster-transfer volume, and
finish parameterizing the single server (clusterid + cluster dir env), so one service is fully
replicable. No second map yet.
**Branch**: `feat/m3-cluster-wiring`
**Flag**: N/A (config/infra; per-server `ENABLE_ASAAPI` kill-switch already exists)
**Est. lines**: ~120
**Executor tier**: standard
**Ships via**: `/pr`
**Objective**: After this phase, the existing `the-center` service launches with
`-clusterid=$ARK_CLUSTER_ID -ClusterDirOverride=<shared-path>`, a named `ark-cluster` volume is
mounted at that path, and all per-server identity (map, ports, session, clusterid) is env-driven.
The single server still boots and advertises exactly as before — the cluster args are inert with
one server but prove the wiring.
**Why this phase exists**: The transfer mechanism is the load-bearing unknown. Wiring + proving it
on the existing single server (which still boots) de-risks before multiplying services. It also
keeps the diff reviewable — cluster args + volume, no compose explosion yet.
**Current-state anchors**:
- `entrypoint.sh:556` — launch query string (where map?listen?... is built; cluster args go on the `-flags` side at :559)
- `entrypoint.sh:559-564` — `-flags` construction (`-log`, BattlEye, `-mods`); append cluster flags here
- `entrypoint.sh:12-16` — env default block (`SERVER_PORT`, `RCON_PORT`); add `ARK_CLUSTER_ID`, `CLUSTER_DIR` (this block sits above the same-day `install_or_update` insertion, so it did NOT shift)
- `docker-compose.yml:94-107` — `the-center` volumes (where `ark-cluster` mount is added)
- `docker-compose.yml:116-122` — `volumes:` block (declare `ark-cluster`)
- `docker-compose.yml:62-93` — `the-center` environment (add `ARK_CLUSTER_ID`; `SERVER_MAP` at `:63` — flip stale default `TheIsland_WP` → `TheCenter_WP`)
- `.claude/rules/build-time-vs-runtime.md` — table to amend (cluster-dir row)
**Files (expected scope)**: `entrypoint.sh`, `docker-compose.yml`, `Dockerfile`,
`.env.test.example`, `.env.prod.example`, `.claude/rules/build-time-vs-runtime.md`,
`docs/internal/decisions/0003-cluster-architecture.md`, `.claude/design-sources.md`
**Scope Boundary**:
- **In scope (this phase delivers)**: "ASA native cluster transfer (characters/dinos/items between maps)" (ledger); "Shared cluster save directory volume" (ledger).
- **Explicitly NOT delivered (deferred to later milestone)**: none (all M3 ledger rows land within M3's phases; nothing deferred to M4+).
- **Out of scope (NOT a deferral — never this phase's job)**: the multi-map compose services (Phase 3 — keep the diff to one service + wiring); the GUS/config-sharing rework (Phase 2 — separate concern); a compose generator (M4 ops-tooling — building it now is build-the-engine).
**Deviation rule**: Executor MAY touch adjacent lines if the change serves the wiring (e.g. a comment fix near the launch string). Document each deviation with a one-line reason. Unrelated refactors → STOP, split.
**Steps**:
1. In `entrypoint.sh:12-16` env block (unshifted), add `: "${ARK_CLUSTER_ID:=}"` and
   `: "${CLUSTER_DIR:=${ARK_DIR}/ShooterGame/Saved/clusters}"` (default keeps single-server
   behavior identical when no cluster dir is mounted).
2. In `entrypoint.sh` `-flags` construction (~:577-582), append cluster args **only when
   `ARK_CLUSTER_ID` is non-empty**: `[[ -n "$ARK_CLUSTER_ID" ]] && flags="${flags}
   -clusterid=${ARK_CLUSTER_ID} -ClusterDirOverride=${CLUSTER_DIR}"`. (Empty clusterid → no
   cluster args → byte-for-byte M2 launch. This preserves the vanilla/single-server invariant.)
3. `mkdir -p "${CLUSTER_DIR}"` in the boot prep (idempotent, same style as existing dir creation
   ~entrypoint.sh:455-458) so the override path exists before launch.

**CHECKPOINT** — entrypoint side complete: cluster args appended only when clusterid is non-empty + cluster dir created; with clusterid empty the launch is byte-identical to M2 (single server still boots green). Compose not yet touched.

4. In `docker-compose.yml`, declare a named `ark-cluster` volume (:116-122 block) and mount it into
   `the-center` at `${CLUSTER_DIR}` (default `/home/container/arkserver/ShooterGame/Saved/clusters`).
   Add `ARK_CLUSTER_ID: ${ARK_CLUSTER_ID:?set ARK_CLUSTER_ID in your env file}` to the env block.
   **Also flip the stale `SERVER_MAP` default at `:63` from `${SERVER_MAP:-TheIsland_WP}` →
   `${SERVER_MAP:-TheCenter_WP}`** so the `the-center` service defaults to The Center (the service was
   renamed but the map default was left as Island). The generic `entrypoint.sh:10`
   `SERVER_MAP:=TheIsland_WP` fallback stays as the bare-image default (project identity lives in
   compose, which overrides it — build-time-vs-runtime split).
5. Add `ARK_CLUSTER_ID=<example-non-obvious-id>` + a one-line comment ("treat like a password,
   identical on every cluster server") to both `.env.test.example` and `.env.prod.example`.

**CHECKPOINT** — wiring complete: compose mounts `ark-cluster` + injects `ARK_CLUSTER_ID`, `SERVER_MAP` default flipped to `TheCenter_WP`, `.env` examples updated; `the-center` boots on dell with cluster args present. Only docs (build-time row, ADR) remain.

6. Amend `.claude/rules/build-time-vs-runtime.md` table: add a row "Cluster transfer dir
   (`Saved/clusters`)" → entrypoint, reason "volume-backed shared dir (Q1 yes)".
7. Write ADR `docs/internal/decisions/0003-cluster-architecture.md`: the clusterid+ClusterDirOverride
   model, the shared-volume approach, per-server full game volumes (named tradeoff: ~13GB×N disk vs
   shared-install complexity; shared read-only install deferred to M4 with trigger = "disk pressure
   or >4 maps"), the dupe-on-crash ASA caveat. Rejected alternatives: default per-container cluster
   dir (transfers break); host-path bind instead of named volume (less portable to VPS).
8. Register the ADR `[locked]` in `.claude/design-sources.md` (append a row, same format as the
   0001/0002 entries) so a future diff that re-couples the cluster dir per-container BLOCKs at the
   design gate.
**Acceptance criteria**:
- [ ] `the-center` boots on dell and advertises for join with `ARK_CLUSTER_ID` set (cluster args present in the launch log line)
  - Evidence: NOT VERIFIED — requires a live dell boot, which this executor did not perform. Static verification only (re-run 2026-07-06 post-review-fix): `docker compose --env-file <test env with ARK_CLUSTER_ID set> config` shows `ARK_CLUSTER_ID: my-secret-cluster` reaching the `the-center` service environment (now via a `:-` default, not the old `:?`-required form — see the volume/AC below), and the entrypoint flags-construction logic was simulated in bash (`[[ -n "$ARK_CLUSTER_ID" ]] && flags="${flags} -clusterid=... -ClusterDirOverride=..."`), producing `-clusterid=my-secret-cluster -ClusterDirOverride=/home/container/arkserver/ShooterGame/Saved/clusters` when set. A boot-time charset guard (`entrypoint.sh:464-467`, `[A-Za-z0-9._-]` only) was added and verified to reject `bad id; rm -rf` and accept `my-secret-cluster.01`. The actual "boots on dell and advertises" behavior is unchecked.
- [x] `the-center` service's committed `SERVER_MAP` default is `TheCenter_WP` (`docker-compose.yml:63`) — a bare `docker compose up` with no `.env` `SERVER_MAP` override boots The Center, not Island (the stale-default fix; the service name and its map now agree)
  - Evidence: `docker-compose.yml:63` now reads `SERVER_MAP: ${SERVER_MAP:-TheCenter_WP}` (was `TheIsland_WP`). Confirmed via `docker compose config` (2026-07-06): with no `SERVER_MAP` set in the env file, resolved `SERVER_MAP: TheCenter_WP` in the `the-center` service.
- [x] With `ARK_CLUSTER_ID` empty, the launch string is byte-for-byte identical to the current M2 launch (no `-clusterid`/`-ClusterDirOverride`)
  - Evidence: bash simulation of the exact `entrypoint.sh` flags-construction block (2026-07-06, re-run post-review-fix) with `ARK_CLUSTER_ID` unset produced `flags=[-log -WinLiveMaxPlayers=10 -NoBattlEye]` — identical to the pre-Phase-1 M2 output (verified by running the same simulation against the pre-edit flags-construction lines, which produce the identical string); the `[[ -n "$ARK_CLUSTER_ID" ]] && …` guard at `entrypoint.sh:564` (current line numbering after the review-round fixes added lines above it) means the append is a no-op when unset/empty.
- [ ] `ark-cluster` named volume is declared and mounted at `${CLUSTER_DIR}`; the dir exists in-container after boot
  - Evidence: REVISED post-review (blocker fix, 2026-07-06) — `ark-cluster` is no longer mounted directly at `${CLUSTER_DIR}` (that was the BLOCKER: nested inside the already-mounted `ark-game` volume at a subdir that doesn't exist at mount time → Docker root-creates the missing intermediate dirs, `Permission denied` for the non-root user). Fixed by mounting `ark-cluster` SHALLOW at a fixed top-level path `/home/container/cluster-data` (`docker-compose.yml:101`, pre-created + chowned in `Dockerfile` the same way `arkserver` already is), with `entrypoint.sh:521-523` symlinking `${CLUSTER_DIR}` → `/home/container/cluster-data` each boot (mirrors the existing `config_link` pattern exactly: `mkdir -p "$(dirname ...)"` / `rm -rf` / `ln -sfn`). Confirmed via `docker compose config` (2026-07-06): `source: ark-cluster, target: /home/container/cluster-data`. Reproduced the failure AND the fix live in Docker (not just reasoned through): a nested-mount-at-nonexistent-subdir repro (`docker run -v outer:/outer -v nested:/outer/a/b/nested busybox … touch`) gave `Permission denied` for a non-root uid; the shallow-mount + pre-chown + symlink repro (mirroring the real Dockerfile/entrypoint pattern) gave `WRITE_OK`. "The dir exists in-container after boot" against a real live container is still NOT verified — requires a live dell boot this executor did not perform.
- [x] ADR `0003-cluster-architecture.md` exists and documents the cluster model + per-server-volume tradeoff + rejected alternatives (doc-type: adr — must carry rejected alternatives + cost-to-reverse)
  - Evidence: `docs/internal/decisions/0003-cluster-architecture.md` created, `doc-type: adr` frontmatter, sections Context/Decision/Rejected alternatives (3 named: default per-container cluster dir, host-path bind, shared read-only install)/Consequences (named tradeoff with WHAT/WHY/COST/TRIGGER fields + the ASA dupe-on-crash caveat).
- [x] `build-time-vs-runtime.md` has the cluster-dir row
  - Evidence: `.claude/rules/build-time-vs-runtime.md` table now has `| Cluster transfer dir (`Saved/clusters`) | **entrypoint** | volume-backed shared dir (Q1 yes) |` immediately after the ARK-game-files row.
**Quality gate**:
- [x] Cluster args only appended when clusterid is non-empty (single-server invariant) — `entrypoint.sh:564` `[[ -n "$ARK_CLUSTER_ID" ]] && flags="${flags} -clusterid=... -ClusterDirOverride=..."`; simulated both branches (see AC evidence above), re-run 2026-07-06 post-fix with identical result.
- [x] Cluster dir setup is idempotent (safe on every boot) — `entrypoint.sh:521-523` now does `mkdir -p "$(dirname ...)"` / `rm -rf` / `ln -sfn` (the BLOCKER fix replaced the bare `mkdir -p "${CLUSTER_DIR}"` with a symlink-to-shallow-mount, mirroring the existing `config_link` idiom at `:455-458` exactly — same pattern, verified idempotent by construction: re-running `rm -rf` + `ln -sfn` on an existing link is a no-op).
- [x] No secret (clusterid) committed — only the `.env.*.example` placeholders — `.gitignore:2-4` excludes real `.env*` files except the two `.example` files; `.env.test.example`/`.env.prod.example` now carry DISTINCT, obviously-fake placeholders (`ARK_CLUSTER_ID=CHANGE-ME-unique-per-cluster-test` / `...-prod` respectively — changed from a shared, plausible-looking `xk4-hoarfrost-quill` per security review finding), never a real value.
- [x] Follows existing entrypoint env-default + flags-construction patterns — `: "${VAR:=default}"` idiom matches the existing block (`entrypoint.sh:8-21`); the flags append matches the existing `[[ -n "$MODS" ]] && flags="${flags} -mods=${MODS}"` guard idiom immediately above it.
- [x] `ARK_CLUSTER_ID` charset validated at boot (security finding) — `entrypoint.sh:464-467` rejects anything outside `[A-Za-z0-9._-]` before it reaches the unquoted flags interpolation; verified both branches in bash (reject `bad id; rm -rf`, accept `my-secret-cluster.01`).
- [x] `docker-compose.yml`'s `ARK_CLUSTER_ID` is reachable-empty through the real deployment path, not `:?`-required (should-fix) — `docker-compose.yml:77` now `${ARK_CLUSTER_ID:-}`; `docker compose config` with no `ARK_CLUSTER_ID` in the env file resolves `ARK_CLUSTER_ID: ""` (was a hard compose-up failure before the fix).
- [x] `CLUSTER_DIR` passed through to the container's environment so a host `.env` override can't diverge from the launch arg (should-fix) — `docker-compose.yml:81` adds `CLUSTER_DIR: ${CLUSTER_DIR:-/home/container/arkserver/ShooterGame/Saved/clusters}`, matching `entrypoint.sh:21`'s own default exactly; confirmed via `docker compose config`.
- [x] `CLUSTER_DIR` cannot escape or collide with the game install root (should-fix→BLOCKER, code-reviewer + security, rounds 3, 4, AND 5 — round 3's regex-based guard was itself a collision hole closed in round 4's canonicalization, which itself carried a warm-boot false-rejection BLOCKER closed in round 5) — the round-3 regex guard (`(^|/)\.\.(/|$)` + `!= "${ARK_DIR}"/*`) validated shape/traversal but NOT spelling-equivalence: bash's glob `*` matches the EMPTY string, so `CLUSTER_DIR=${ARK_DIR}/` (trailing slash) or `${ARK_DIR}//` (doubled slash) both satisfied `"${CLUSTER_DIR}" == "${ARK_DIR}"/*` and passed clean through to the guarded `rm -rf "${CLUSTER_DIR}"`, actually deleting the entire ~13GB game install root (reproduced live in round 4 with a real `rm -rf` against a mock install tree — see Review-round fixes below). Round 4 replaced the regex-shape check with canonicalization via `realpath -m` — but `-m` alone still FOLLOWS an existing symlink, and this same entrypoint block creates `CLUSTER_DIR` as a symlink to `/home/container/cluster-data` (deliberately OUTSIDE `ARK_DIR` — see that block's comment) on every boot. So on the SECOND (warm) boot, `CLUSTER_DIR` already existed as that symlink, `realpath -m` resolved THROUGH it to the out-of-tree target, and the guard incorrectly FATAL-rejected a value that, as a string, was still the exact same safe default — the server could never restart past its first boot (reproduced live in round 5: created the symlink, then re-ran the guard on the identical string value — see Review-round fixes below). Round 5 fixed this with one added flag: `realpath -m -s` (`-s`/`--no-symlinks`/`--strip` — confirmed the correct GNU coreutils 9.1 flag via `realpath --help` inside the actual runtime image, `docker run --rm ark-asa:latest realpath --help`) canonicalizes `.`, `..`, and slashes LEXICALLY, never following a symlink, so first boot, warm boot, and every spelling variant now get the identical verdict from the value's shape alone (`entrypoint.sh:479-511`). `CLUSTER_DIR` is reassigned to its canonical form so every downstream use (the `rm -rf`, the symlink target, the launch flags string) is unambiguous. The pre-existing charset guard (`entrypoint.sh:474-477`) is UNCHANGED and still required (realpath validates neither charset nor symlink-following safety by itself — charset-then-canonicalize is defense-in-depth, not either/or). Verified in bash (see Review-round fixes below for the full test matrix, including a LIVE `rm -rf` repro against a real mock game-install directory both before/after the round-4 fix, AND a LIVE warm-boot repro — create the real symlink, then re-run the guard on the same string value — both before/after the round-5 fix): rejects `${ARK_DIR}/`, `${ARK_DIR}//`, `${ARK_DIR}/.`, `${ARK_DIR}/..`, bare `${ARK_DIR}`, and any `..`-traversal value (all FATAL, exit 1); accepts the legitimate default `${ARK_DIR}/ShooterGame/Saved/clusters`, its trailing-slash spelling, AND the warm-boot state where that same default value already exists on disk as the cluster-data symlink (the round-5 addition — the round-4-only guard incorrectly rejected this last case). **Round 6 closed one further hole (should-fix, code-reviewer AND security, confirmed independently by both via live reproduction):** the lexical-only guard (by design) canonicalizes only the STRING and never inspects whether an INTERMEDIATE path component between `ARK_DIR` and `CLUSTER_DIR`'s leaf (e.g. `ShooterGame` or `Saved`) is itself a symlink pointing outside `ARK_DIR` — the guard's own string-shape check passes clean, but the actual `mkdir -p`/`rm -rf`/`ln -sfn` a few lines below follow normal kernel symlink resolution through every component, and could operate outside `ARK_DIR` through that intermediate link. **Reproduced live**: fabricated a mock tree where `Saved` (the parent directory immediately above the leaf `clusters` component) is a symlink to an external directory holding a pre-existing canary file; confirmed the lexical-only guard alone still ACCEPTED the crafted `CLUSTER_DIR`, then ran the entrypoint's actual subsequent `mkdir -p`/`rm -rf`/`ln -sfn` sequence verbatim — it genuinely deleted the canary file living outside `ARK_DIR` and planted the cluster symlink inside the attacker-controlled directory, entirely outside the intended tree. **Fixed with an ADDITIONAL guard** (`entrypoint.sh:513-529`) that canonicalizes ONLY `dirname "$CLUSTER_DIR"` (never the leaf — the leaf is the one, intentional symlink this same block creates) via SYMLINK-FOLLOWING `realpath -m` (no `-s`) and requires it equal `ARK_DIR`'s canonical form or be a descendant of it. This cannot reintroduce the round-5 warm-boot false-rejection because the parent is never the leaf symlink — only the final `clusters` component ever becomes one. Verified in bash (guard block extracted verbatim, full matrix): (a) the original warm-boot scenario (`CLUSTER_DIR` already symlinked to cluster-data) still ACCEPTS after this new check; (b) the fabricated intermediate-symlink-escape scenario is now REJECTED (FATAL, exit 1) before either destructive sink runs; (c) all previously-passing/rejected cases — the legitimate default, its trailing-slash spelling, the first-boot state (parent dirs not yet created), and all 6 previously-established collision/traversal spellings (`${ARK_DIR}/`, `${ARK_DIR}//`, `${ARK_DIR}/.`, `${ARK_DIR}/..`, bare `${ARK_DIR}`, `../../../etc`) — behave identically to before this round's addition.
**Verification**: On dell, `docker compose up` with `ARK_CLUSTER_ID` set → grep the launch log for
`-clusterid=` and `-ClusterDirOverride=`; `docker compose exec the-center ls ${CLUSTER_DIR}` shows
the dir. Then unset `ARK_CLUSTER_ID`, reboot, confirm the launch line has no cluster args.

**Review-round fixes (2026-07-06, applied by a fresh executor after the review fleet's first
pass)** — surfaced for the deviation-judge, not self-decided as a FRAGO:
- **BLOCKER** (code-reviewer, reproduced live in Docker): `ark-cluster` was mounted directly at
  `${CLUSTER_DIR}` — nested inside the already-mounted `ark-game` volume at a subdir that doesn't
  exist at mount time, so Docker root-creates the missing intermediate dirs and the non-root
  `container` user gets `Permission denied` writing cluster-transfer files. Fixed by mounting
  `ark-cluster` SHALLOW at a fixed top-level `/home/container/cluster-data` (docker-compose.yml)
  and symlinking `${CLUSTER_DIR}` → that mount each boot (entrypoint.sh, mirrors `config_link`
  exactly). **Deviation**: this required also touching `Dockerfile` (pre-create + chown
  `/home/container/cluster-data`, mirroring the existing `arkserver` pre-create at `Dockerfile:78-81`)
  — `Dockerfile` was NOT in this phase's original "Files (expected scope)" list. Reason: the
  shallow-mount fix is a no-op without this pre-create/chown step (a freshly-mounted named volume
  with no pre-existing image content defaults to root ownership) — it is the direct, minimal
  complement of the wiring fix, not an unrelated refactor.
- **SHOULD-FIX**: `ARK_CLUSTER_ID` changed from `:?`-required to `:-` (default empty) in
  `docker-compose.yml`, so the single-server invariant (AC above) is reachable through the real
  deployment path, not just a bash simulation. `CLUSTER_DIR` added to the service's `environment:`
  block so a host `.env` override can't silently diverge from what `entrypoint.sh` actually uses.
- **MINOR**: quoting-safety comment added near `CLUSTER_DIR`'s env-default in `entrypoint.sh`;
  `.env.test.example`/`.env.prod.example` now carry distinct, obviously-fake `ARK_CLUSTER_ID`
  placeholders (`CHANGE-ME-unique-per-cluster-test`/`-prod`, was a shared plausible-looking
  `xk4-hoarfrost-quill`); a boot-time charset guard (`[A-Za-z0-9._-]`) added for `ARK_CLUSTER_ID`;
  ADR 0003 frontmatter scalars quoted (0002 intentionally left untouched — out of this phase's
  scope) and its bare "see the plan's Research Findings" text turned into a relative markdown link.
- All fixes re-verified: `bash -n entrypoint.sh`, `docker buildx build --check` (Dockerfile syntax),
  `docker compose config` (both empty- and set-`ARK_CLUSTER_ID` env files), a live Docker
  reproduction of the blocker (nested mount at a non-existent subdir → `Permission denied`) and of
  the fix (shallow pre-owned mount + symlink → write succeeds), and a bash re-simulation of the
  flags-construction block confirming the empty-`ARK_CLUSTER_ID` launch string is still
  byte-for-byte `-log -WinLiveMaxPlayers=10 -NoBattlEye` — the single-server invariant holds.

**Review-round fixes (2026-07-06, second round — applied by a fresh executor after the review
fleet's second pass)** — 3 should-fix/minor items plus 1 already-ratified FRAGO application:
- **SHOULD-FIX** (code-reviewer): ADR `0003-cluster-architecture.md` Decision item 3 still
  described the named volume as "mounted at the identical `${CLUSTER_DIR}` path in every cluster
  service" — stale since the blocker fix above replaced that with the shallow-mount-at-fixed-path
  + entrypoint-symlink mechanism (exactly what the shallow mount was built to avoid). Rewrote
  Decision item 3 to describe the actual mechanism (shallow mount at `/home/container/cluster-data`,
  pre-created/chowned in `Dockerfile`, symlinked from `${CLUSTER_DIR}` by `entrypoint.sh`), and
  added a Consequences note stating the indirection is the committed mechanism, not optional
  polish, so a future edit to this `[locked]` ADR can't silently regress to the direct-mount shape
  that caused the original blocker.
- **SHOULD-FIX** (security): `CLUSTER_DIR` reaches the same unquoted `-flags` argv-splitting sink as
  `ARK_CLUSTER_ID` AND feeds the destructive `rm -rf "${CLUSTER_DIR}"` in the symlink setup, but had
  no equivalent charset/shape guard. Added a boot-time guard (`entrypoint.sh:474-477`) requiring
  `CLUSTER_DIR` to match `^/[A-Za-z0-9._/-]+$` (absolute path, safe charset) — fails loud (FATAL,
  exit 1) before either sink sees an unvalidated value, same idiom as the existing `ARK_CLUSTER_ID`
  guard immediately above it.
- **MINOR** (security): the `ARK_CLUSTER_ID` charset-validation FATAL message echoed the raw
  invalid value to stderr, despite `ARK_CLUSTER_ID` being documented "treat like a password."
  Removed the value from the message (`entrypoint.sh:465`) — it now states the value is invalid
  without printing it. (`CLUSTER_DIR`'s new guard message intentionally DOES echo the raw value —
  it's a path, not a secret, and the value is useful for debugging a misconfigured override.)
- **FRAGO application** (already ratified by the deviation-judge as JUSTIFIED/risk-neutral, applied
  here per its instruction — not re-decided): amended Phase 1's "Files (expected scope)" list
  (plan.md, this file) to add `Dockerfile`, so the plan's own record now matches the phase's real
  touched-file set (the first review round's blocker fix required a `Dockerfile` pre-create/chown
  that the original scope list omitted). Plan-text correction only — no new code change.
- All fixes re-verified: `bash -n entrypoint.sh` (clean), `docker buildx build --check`
  (Dockerfile syntax — unchanged this round but re-checked per constraint, "no warnings found"),
  `docker compose config` with both an empty- and a set-`ARK_CLUSTER_ID` env file (both resolve
  correctly; `ark-cluster`/`cluster-data` mount unaffected), and a bash re-simulation of both the
  flags-construction block (empty `ARK_CLUSTER_ID` → still byte-for-byte
  `-log -WinLiveMaxPlayers=10 -NoBattlEye` — single-server invariant holds) and the new
  `CLUSTER_DIR` guard (accepts the real default path and `/home/container/cluster-data`; rejects a
  path with a space, a path with a `;`/`rm -rf` shell-metacharacter payload, a relative path, a
  `$(...)` command-substitution payload, and bare `/`).

**Review-round fixes (2026-07-06, third round — applied by a fresh executor after the review
fleet's third pass)** — 1 should-fix (code-reviewer + security, same root cause) plus 1 stale-citation
sweep plus 1 already-ratified FRAGO application:
- **SHOULD-FIX** (code-reviewer + security, same root cause — fixed with ONE change): the
  `CLUSTER_DIR` charset guard (`entrypoint.sh:474-477`) validated shape only, not containment or
  traversal, leaving two related holes: (a) it allowed a `..` path segment (`.` is inside the
  allowed charset), so a value like `${ARK_DIR}/../../../etc` passed clean and could redirect the
  guarded `rm -rf "${CLUSTER_DIR}"` outside the intended tree; (b) it allowed a well-formed value
  equal to or above `ARK_DIR` — e.g. `CLUSTER_DIR=${ARK_DIR}` (the whole ~13GB `ark-game` volume) —
  which also passed clean and would then get wiped by that same `rm -rf` before the symlink is
  recreated. Fixed by adding a second guard (`entrypoint.sh:488-491`) requiring `CLUSTER_DIR` to be
  a strict descendant of `ARK_DIR`, with no `..` segments anywhere in the value — this matches the
  only legitimate shape (the default `${ARK_DIR}/ShooterGame/Saved/clusters`) and makes it
  structurally impossible for the guarded `rm -rf` to reach `ARK_DIR` itself or anything outside
  it. Same fail-loud idiom as the existing guards (FATAL to stderr, `exit 1`, before either
  destructive sink runs).
- **Stale-citation sweep** (should-fix, 4 independent reviewers: acceptance-verifier,
  deviation-judge, code-reviewer, graveyard-auditor): the second review round's 9-line
  `CLUSTER_DIR`-guard insertion (and this round's further insertion above it) had drifted several
  `entrypoint.sh` line-number citations in this phase's Acceptance-criteria Evidence and
  Quality-gate bullets. Re-grepped every `entrypoint.sh:<N>` citation in those two sections against
  the file as it stands after this round's fix (so the numbers won't immediately go stale again)
  and corrected: the cluster-args append guard `:518` → `:544`; the symlink setup block `:467-477`
  (now charset-guard code, not the symlink) → `:501-503`; `CLUSTER_DIR`'s own default `:19` → `:21`;
  the `ARK_CLUSTER_ID` charset guard `:462-465` → `:464-467`. Also added a new Quality-gate bullet
  documenting the new containment/traversal guard (`entrypoint.sh:488-491`) so the checklist
  reflects the current guarantee, not just the old charset-only one.
- **FRAGO application** (already ratified by the deviation-judge as JUSTIFIED/risk-neutral, applied
  here per its instruction — not re-decided): `.claude/design-sources.md` is touched by this
  phase's own Step 8 (registering ADR 0003 `[locked]`) but was missing from both this phase's
  "Files (expected scope)" list and the plan's top-level frontmatter `files:` list; the
  frontmatter `files:` list was also separately missing `.claude/rules/build-time-vs-runtime.md`
  (touched per this phase's own Step 6). Added `.claude/design-sources.md` to this phase's "Files
  (expected scope)" list; added both `.claude/design-sources.md` and
  `.claude/rules/build-time-vs-runtime.md` to the frontmatter `files:` list. Plan-text correction
  only — no code change.
- All fixes re-verified: `bash -n entrypoint.sh` (clean), `docker buildx build --check`
  (Dockerfile syntax — unchanged this round but re-checked per constraint, "no warnings found"),
  `docker compose config` with both an empty- and a set-`ARK_CLUSTER_ID` env file (both resolve
  correctly; `ark-cluster`/`cluster-data` mount unaffected), a bash re-simulation of the
  flags-construction block (empty `ARK_CLUSTER_ID` → still byte-for-byte
  `-log -WinLiveMaxPlayers=10 -NoBattlEye` — single-server invariant holds), and the new
  `CLUSTER_DIR` containment/traversal guard tested against 3 explicit cases by sourcing the exact
  guard block extracted verbatim from `entrypoint.sh`: rejects `${ARK_DIR}/../../../etc`
  (`..`-traversal, FATAL exit 1), rejects `CLUSTER_DIR=${ARK_DIR}` (collision with the game install
  root, FATAL exit 1), and accepts the legitimate default `${ARK_DIR}/ShooterGame/Saved/clusters`
  (no output, exit 0) — plus regression re-checks confirming the pre-existing charset guard, the
  `ARK_CLUSTER_ID` guard, and the extra edge cases from round 2 (space, `;`/`rm -rf` payload,
  relative path, bare `/`) all still behave identically.

**Review-round fixes (2026-07-06, fourth round — applied by a fresh executor after the review
fleet's fourth pass)** — 1 BLOCKER (reproduced live with a real `rm -rf` by two independent
reviewers) plus 1 stale-citation sweep covering Phase 1 AND Phase 2 (this phase's own AC/QG
evidence had also drifted, on top of the anchors):
- **BLOCKER** (code-reviewer + security, reproduced live): round 3's regex-shape containment guard
  (`[[ "${CLUSTER_DIR}" =~ (^|/)\.\.(/|$) ]] || [[ "${CLUSTER_DIR}" != "${ARK_DIR}"/* ]]`) did not
  close the collision hole for a **trailing slash**: `CLUSTER_DIR=${ARK_DIR}/` or `${ARK_DIR}//`
  both PASS the guard (bash's `*` glob matches the empty string, so `"${ARK_DIR}/"` matches the
  pattern `"${ARK_DIR}"/*`), then reach `rm -rf "${CLUSTER_DIR}"` and genuinely wipe the entire
  ~13GB game install root; a bare `CLUSTER_DIR=${ARK_DIR}/.` also slips through and aborts the boot
  (GNU `rm` refuses to remove a path ending in `/.`, so `set -euo pipefail` kills the boot —
  non-destructive but a self-inflicted failure). **Live repro (this round, real `rm -rf` against a
  mock game-install tree with a fake `ShooterGame/Binaries/Win64/ArkAscendedServer.exe`)**: the
  pre-fix guard passed `CLUSTER_DIR=${ARK_DIR}/` clean, the subsequent real `rm -rf` deleted the
  entire mock install root (confirmed absent afterward); the identical mock tree survived intact
  against the post-fix guard, which FATAL-exited before the `rm -rf` ran. **Fixed by
  canonicalizing before comparing**: both `CLUSTER_DIR` and `ARK_DIR` are resolved via `realpath -m`
  (collapses `.`, `..`, repeated/trailing slashes; the `-m` mode tolerates a not-yet-existing path,
  needed because `CLUSTER_DIR`'s parents may not exist on first boot) — `readlink -f` (already used
  elsewhere in this file, `entrypoint.sh:371`) was considered but rejected: it requires all but the
  final path component to already exist, which fails on the default `${ARK_DIR}/ShooterGame/Saved/
  clusters` before `install_or_update` has run. The canonicalized values are compared with the same
  strict-descendant glob (`cluster_dir_canon != ark_dir_canon"/*"`), and `CLUSTER_DIR` is reassigned
  to its canonical form (`entrypoint.sh:479-503`). The pre-existing charset guard
  (`entrypoint.sh:474-477`) is kept unchanged and still required — `realpath` does not validate
  charset, so charset-then-canonicalize is defense-in-depth, not a replacement. Full test matrix
  (verified in bash by extracting the exact guard block verbatim, both pre- and post-fix): rejects
  `${ARK_DIR}/`, `${ARK_DIR}//`, `${ARK_DIR}/.`, `${ARK_DIR}/..`, bare `${ARK_DIR}`, and
  `${ARK_DIR}/../../../etc` (all FATAL, exit 1 — the first three are the NEW catches this round);
  accepts `${ARK_DIR}/ShooterGame/Saved/clusters` (exit 0, canonical form unchanged) and its
  trailing-slash spelling (exit 0, canonicalizes to the same value).
- **Stale-citation sweep (exhaustive, whole-plan)** — this round's guard replacement shifted
  `main()`'s internal line numbers again; re-grepped every `entrypoint.sh:<N>` citation in the
  ENTIRE `plan.md` (not just this phase) against the file as it now stands and corrected all of
  them: Phase 1's own AC/QG evidence (query string `:487`→`:548`, flags construction `:490-492`→
  `:551-556`, the cluster-append guard `:544`→`:556`, the cluster-dir symlink setup `:501-503`→
  `:513-515`, the `config_link` idiom reference `:451-458`→`:455-458`, the env-default block
  reference `:8-19`→`:8-21`); Phase 1's Current-state anchors (`:487`→`:548`, `:490-492`→
  `:551-556`); the Context/Research Findings/Decision Ledger prose above the phases (`:451-454`→
  `:455-458`, `:334`→`:338`, `:487`→`:548`, `:333-335`→`:337-339`, `:336-339`→`:340-343`,
  `:348-383`→`:352-387`, `:432`→`:436`); and Phase 2's OWN Current-state anchors + step text +
  Acceptance criteria, which had drifted by a consistent **+4** ever since this same-day's
  `ARK_CLUSTER_ID`/`CLUSTER_DIR` env-default block was inserted at the top of the file (lines
  18-21) and never propagated forward — Phase 2 hadn't executed yet, so a future executor would
  have edited the WRONG lines: `deploy_plugins()` span `:99-180`→`:103-184` (stash `:120-127`→
  `:124-131`, restore `:161-170`→`:165-174`); `setup_plugin_configs()` span `:291-346`→`:295-350`
  (`cp` seed `:334`→`:338`, seed-if-absent `:336-339`→`:340-343`, shared-bind symlink `:342`→`:346`,
  `host_root` `:313`→`:317`); `_inject_mysql_block()` span `:348-383`→`:352-387` (`readlink -f`
  `:367`→`:371`, its comment `:361-363`→`:365-367`, `mv` `:382`→`:386`); `inject_plugin_db_config()`
  span `:385-436`→`:389-440` (hardcoded paths `:418,:431`→`:422,:435`, stale comments `:395-401`→
  `:399-405`, the `has("Mysql")` guard `:432`→`:436`); and Phase 2 Step 1's symlink-replace
  reference `:453-454`→`:457-458`. Also corrected `docker-compose.yml:79`'s comment citing
  `entrypoint.sh:19` for `CLUSTER_DIR`'s default (now `entrypoint.sh:21`, itself re-verified after
  this round's fix). The three prior dated Review-round-fixes entries above are left untouched
  (historical record of what each round did against the file as it stood then, per this plan's own
  constraint not to overwrite prior entries) — only the LIVE Current-state anchors, Decision Ledger,
  and AC/QG evidence (which represent current-truth claims, not a dated log) were corrected.
- All fixes re-verified: `bash -n entrypoint.sh` (clean), `docker buildx build --check` ("Check
  complete, no warnings found"), `docker compose --env-file .env.test.example config` (resolves
  clean; `ARK_CLUSTER_ID`/`CLUSTER_DIR` reach the service environment as before), and the full
  containment-guard test matrix above re-run against the final file's exact guard block extracted
  verbatim (not paraphrased) — both the LIVE `rm -rf` before/after repro and the 7-case bash matrix
  (6 reject, 1 accept) pass as described. The single-server invariant re-confirmed unchanged: with
  `ARK_CLUSTER_ID` empty, `flags` is still byte-for-byte `-log -WinLiveMaxPlayers=10 -NoBattlEye`
  (the cluster-append guard at `entrypoint.sh:556` is a no-op when unset).

**Review-round fixes (2026-07-06, fifth round — applied by a fresh executor after the review
fleet's fifth pass)** — 1 BLOCKER (reproduced live) plus 1 exhaustive whole-plan citation sweep
covering `entrypoint.sh`, `docker-compose.yml`, AND `shop.md` (round 4's sweep covered only
`entrypoint.sh` citations in AC/QG sections and missed all three of those):
- **BLOCKER** (functional, reproduced live): round 4's containment guard canonicalized `CLUSTER_DIR`
  via `realpath -m`, which FOLLOWS an existing symlink. But this same entrypoint block creates
  `CLUSTER_DIR` AS a symlink to `/home/container/cluster-data` (the `ln -sfn` a few lines below the
  guard) on every boot. So on the SECOND (warm) boot, `CLUSTER_DIR` already exists as that symlink,
  `realpath -m` resolved THROUGH it to `/home/container/cluster-data` — which is deliberately OUTSIDE
  `ARK_DIR` (the whole reason the shallow-mount + symlink indirection exists) — and the guard
  incorrectly FATAL-rejected a value that, as a string, was still the exact same safe default it was
  on first boot. The server could never successfully restart past its first boot. **Live repro (this
  round)**: created a mock `ARK_DIR` + `cluster-data` dir, ran the guard on the first-boot (path
  absent) value → ACCEPT; then created the real symlink (mirroring what the entrypoint does at the
  end of that same boot) and re-ran the guard on the IDENTICAL `CLUSTER_DIR` string value → the
  pre-fix guard FATAL-rejected it (bug confirmed); a separate live `rm -rf` regression repro against
  a real mock game-install tree confirmed the fixed guard still FATAL-exits BEFORE the destructive
  `rm -rf` for a genuine collision (`${ARK_DIR}/`), leaving the mock install intact. **Fixed by adding
  one flag**: `realpath -m -s` (`-s`/`--no-symlinks`/`--strip`) canonicalizes `.`, `..`, and
  repeated/trailing slashes LEXICALLY, without ever following a symlink — confirmed `-s` is the
  correct GNU coreutils flag both via `realpath --help` on the host AND via
  `docker run --rm ark-asa:latest realpath --help` inside the actual runtime image (GNU coreutils
  9.1, ships the `-s, --strip, --no-symlinks` flag). Full 8-case test matrix re-run against the exact
  guard block extracted verbatim from the fixed file: rejects `${ARK_DIR}/`, `${ARK_DIR}//`,
  `${ARK_DIR}/.`, `${ARK_DIR}/..`, bare `${ARK_DIR}`, and `${ARK_DIR}/../../../etc` (all 6
  previously-fixed bypass classes — still FATAL, exit 1, unchanged by this round); accepts the
  legitimate default `${ARK_DIR}/ShooterGame/Saved/clusters` and its trailing-slash spelling (exit 0,
  unchanged); and — the new case this round adds — accepts the SAME default value when it already
  exists on disk as the cluster-data symlink (the warm-boot state), which the round-4-only guard had
  incorrectly rejected. `entrypoint.sh:479-511` (comment + canonicalization block); the pre-existing
  charset guard (`entrypoint.sh:474-477`) is unchanged and still required.
- **Stale-citation sweep (exhaustive, whole-plan, three file types)**: this round's guard-comment
  expansion shifted every `entrypoint.sh` line number from :504 onward by +8 (the guard block itself
  grew from 479-503 to 479-511; the cluster-data symlink setup shifted :513-515→:521-523; the launch
  query string :548→:556; the `-flags` construction :551-556→:559-564; the cluster-append guard
  :556→:564). Corrected every one of these in the LIVE current-truth sections (Research Findings,
  Decision Ledger #1, Phase 1's own Current-state anchors, AC evidence, and QG bullets) — the three
  prior dated Review-round-fixes entries above are left untouched (historical record), per this
  plan's own standing constraint. Separately, re-grepped the ENTIRE plan for every
  `\.sh:[0-9]`/`\.yml:[0-9]`/`\.md:[0-9]` citation (not just `entrypoint.sh`, which is all round 4's
  sweep covered) and checked each against the actual file at that location:
  - **`docker-compose.yml` citations** (round 4 never touched these) had drifted because Phase 1's own
    ARK_CLUSTER_ID/CLUSTER_DIR comment blocks + the ark-cluster volume mount widened the file since the
    plan was authored. Corrected: the-center service span `:50-97`→`:50-114` (Decision Ledger #7,
    Phase 3 anchors); mariadb→ArkShop DB env-var citation `:79-83`→`:86-93` (Decision Ledger #8); the
    Phase 1 anchors' `:84-90`→`:94-107` (the-center volumes), `:99-103`→`:116-122` (top-level volumes
    block; also the Phase 3 anchor for the same block), `:62-83`→`:62-93` (the-center environment); the
    Phase 2 anchor + Step 8 text `:90`→`:100` (the `./plugins-config` bind, now 10 lines further down
    because of the intervening ARK_CLUSTER_ID/CLUSTER_DIR/ark-cluster additions); the Phase 2 Step 1
    deep-bind-warning note `:86-89`→`:96-99`. (`docker-compose.yml:63`, `:66`, `:26-48`, `:77`, `:81`,
    `:101`, and `:79` were re-checked and are all still correct as cited — left unchanged.)
  - **`shop.md` citation**: Phase 2's anchor + Step 9 text cited `shop.md:253-270` for §11 "Build &
    deploy" — the doc has since grown above that section (unrelated to this plan; shop.md is out of
    Phase 1's scope to edit), and §11 now actually starts at line 268 and runs through line 286.
    Corrected both citations to `shop.md:268-286`. This is a plan-text-only fix (shop.md itself is
    Phase 2's job to edit, not this phase's).
  - Full audit list (every citation checked, whether correct or fixed) — see this executor's return
    summary; recorded here only as the outcome: **entrypoint.sh** — 4 groups of citations corrected
    (guard/symlink/query/flags, all +8 or block-widened), all others (`:455-458`, `:338`,
    `:337-339`, `:340-343`, `:352-387`, `:12-16`, `:10`, `:464-467`, `:8-21`, `:21`, `:474-477`,
    `:103-184`, `:295-350`, `:389-440`, `:436`, `:457-458`) checked and confirmed still accurate,
    left unchanged. **docker-compose.yml** — 6 citations corrected (listed above); 7 checked and
    confirmed accurate (`:63` ×3, `:66`, `:26-48`, `:77`, `:81`, `:101`, `:79`), left unchanged.
    **shop.md** — 2 citations corrected (the only 2 in the plan).
- All fixes re-verified: `bash -n entrypoint.sh` (clean), `docker buildx build --check` ("Check
  complete, no warnings found"), `docker compose --env-file .env.test.example config` (resolves
  clean, `ARK_CLUSTER_ID`/`CLUSTER_DIR` reach the service environment unchanged) AND
  `ARK_CLUSTER_ID=my-secret-cluster docker compose --env-file .env.test.example config` (resolves
  `ARK_CLUSTER_ID: my-secret-cluster` reaching the service), a bash re-simulation of the
  flags-construction block extracted verbatim from the current file (empty `ARK_CLUSTER_ID` → still
  byte-for-byte `-log -WinLiveMaxPlayers=10 -NoBattlEye` — the single-server invariant holds
  unchanged by this round), and the full guard test matrix (6 reject / 2 accept / 1 new warm-boot
  accept) re-run against the exact post-fix guard block extracted verbatim from `entrypoint.sh`, plus
  a live `rm -rf` regression repro (mock game-install tree survives intact against the fixed guard;
  a pre-fix control run against the same repro shape genuinely deletes it).

**Review-round fixes (2026-07-06, sixth round — applied by a fresh executor after the review
fleet's sixth pass)** — a tightly-scoped 5-item final pass, no broader sweep:
- **SHOULD-FIX** (code-reviewer AND security, independently confirmed via live reproduction):
  the round-5 lexical-only containment guard (`realpath -m -s`, `entrypoint.sh:479-511`) is
  correct on its own terms — it must never follow a symlink, or the round-5 warm-boot bug
  returns — but that also makes it blind to an INTERMEDIATE path component between `ARK_DIR` and
  `CLUSTER_DIR`'s leaf (e.g. if `ShooterGame` or `Saved` were ever a symlink pointing outside
  `ARK_DIR`): the lexical check only inspects the string, while the actual `mkdir -p`/`rm -rf`/
  `ln -sfn` below follow normal kernel symlink resolution through every component on the real
  filesystem. **Live repro (this round)**: fabricated a mock tree where `Saved` (the parent
  directory immediately above the leaf `clusters` component) is a symlink to an external
  directory holding a pre-existing canary file; confirmed the lexical-only guard alone still
  ACCEPTED the crafted `CLUSTER_DIR`, then ran the entrypoint's actual subsequent
  `mkdir -p`/`rm -rf`/`ln -sfn` sequence verbatim — it genuinely deleted the canary file living
  outside `ARK_DIR` and planted the cluster symlink inside the attacker-controlled directory,
  entirely outside the intended tree. **Fixed with an ADDITIONAL guard** (`entrypoint.sh:513-529`)
  that canonicalizes ONLY `dirname "$CLUSTER_DIR"` (never the leaf, which is the one intentional
  symlink this same block creates every boot) via SYMLINK-FOLLOWING `realpath -m` (no `-s`) and
  requires it equal `ARK_DIR`'s canonical form or be a descendant of it — safe because the parent
  is never the leaf symlink, so this cannot reintroduce the round-5 warm-boot false-rejection.
  Full test matrix (guard block extracted verbatim, both pre- and post-fix): (a) the original
  warm-boot scenario (`CLUSTER_DIR` already symlinked to cluster-data) still ACCEPTS after this
  new check; (b) the fabricated intermediate-symlink-escape scenario is now REJECTED (FATAL,
  exit 1) before either destructive sink runs; (c) all previously-passing/rejected cases — the
  legitimate default, its trailing-slash spelling, the first-boot state (parent dirs not yet
  created), and all 6 previously-established collision/traversal spellings (`${ARK_DIR}/`,
  `${ARK_DIR}//`, `${ARK_DIR}/.`, `${ARK_DIR}/..`, bare `${ARK_DIR}`, `../../../etc`) — behave
  identically to before this round's addition. The pre-existing charset guards
  (`entrypoint.sh:464-467`, `:469-477`) are unchanged and still required.
- **Citation fixes (4 items, targeted — not a whole-plan sweep)**: this round's 18-line guard
  insertion shifted every `entrypoint.sh` line at or after `main()`'s containment-guard block by
  +18. Re-grepped and corrected only the two specific stale citations named for this round: the
  Background-prose query-string cite (`:487`→`:574`) and Phase 1 Step 2's `-flags`-construction
  cite (`~:490-492`→`~:577-582`). Also corrected two citations unrelated to the entrypoint.sh
  shift: Phase 1 Step 4's stale `docker-compose.yml` volume-block cite (`:99-103`→`:116-122`,
  re-verified current — `docker-compose.yml`'s `volumes:` block genuinely sits at `:116-122`) and
  round 5's shop.md §11 boundary claim (the doc's §11 "Build & deploy" is the file's last section
  and runs through its actual last line — `wc -l docs/internal/design/economy/shop.md` = 289, not
  286 as round 5 stated; corrected the two LIVE citations that carry this range,
  `docs/internal/design/economy/shop.md:268-286`→`:268-289`, in Phase 2's Current-state anchors
  and Step 9 text). **Per this round's explicit scope constraint, no further citation hunting was
  done**: this round's own +18 entrypoint.sh shift also staled several OTHER citations this round
  deliberately left untouched — e.g. this phase's own AC/QG evidence prose and Current-state
  anchors that cite the pre-this-round `entrypoint.sh:479-511`/`:513-523`/`:556`/`:559-564` line
  numbers for the guard/symlink/query/flags blocks, and Phase 2's own Current-state anchors
  (`deploy_plugins()`, `setup_plugin_configs()`, `_inject_mysql_block()`,
  `inject_plugin_db_config()` spans), which would need the same +18 correction Phase 2 got in
  round 4 when THIS round's insertion landed above them. These are flagged here for a future
  citation-sweep round (or Phase 2's own executor at start-of-phase) rather than fixed now, per
  this round's explicit "exactly 5 items, no broader sweep" directive — recorded as a deliberate
  scope decision, not an oversight.
- **Audit backfill** (not a code/plan-body change): `.claude/plans/active/ark-asa-server/m3-cluster/audit.md`'s
  `## Session log` was missing entries for fix rounds 2 through 5 (only round 1 was logged,
  flagged by the deviation-judge). Reconstructed each round's session-id (the only ids anywhere
  in this plan are the three in the frontmatter `session-id:` array; rounds 2-5 all fixed
  `entrypoint.sh`'s `CLUSTER_DIR` guard from within the same fix-round chain as round 1's already
  -logged `74db45a6-a185-4885-a2b3-f3045dba37fa`, and no other session-id appears anywhere in the
  plan or its frontmatter to attribute them to, so all four backfilled rows use that same id) and
  what each round did (from its own dated Review-round-fixes block above), and appended one line
  per round in the existing format, plus a line for this round. Frontmatter `session-id:` array
  already carries `74db45a6-a185-4885-a2b3-f3045dba37fa` as its last entry — not re-appended.
- All fixes re-verified: `bash -n entrypoint.sh` (clean), `docker buildx build --check` ("Check
  complete, no warnings found"), `docker compose --env-file .env.test.example config` (resolves
  clean, both with and without `ARK_CLUSTER_ID` set — unaffected by this round, which touched only
  `entrypoint.sh` logic and plan-text citations), a bash re-simulation of the flags-construction
  block extracted verbatim from the current file (empty `ARK_CLUSTER_ID` → still byte-for-byte
  `-log -WinLiveMaxPlayers=10 -NoBattlEye` — the single-server invariant holds unchanged by this
  round), and the full new-guard test matrix (2 new cases + regression of all prior
  collision/traversal/charset cases) re-run against the exact post-fix guard block extracted
  verbatim from `entrypoint.sh`, plus a live `rm -rf`-through-symlink regression repro (a
  pre-existing canary file outside `ARK_DIR`, reached via a fabricated symlinked intermediate
  component, is destroyed against the pre-fix guard and survives intact against the post-fix guard).

**Phase Review Gates**:
- [x] code-reviewer: clean — 2026-07-06 (round 7, final pass — clean after 6 prior fix rounds closed all should-fix/BLOCKER findings; see Review-round fixes log above)
- [x] rules-compliance-reviewer: clean — 2026-07-06 (round 7, final pass; no distinct rules-compliance-reviewer finding was logged in any of rounds 1-6's "Review-round fixes" entries — clean throughout per the review fleet's per-round fan-out)
- [x] plan-adherence-verifier: clean — 2026-07-06 (round 7, final pass; no distinct plan-adherence-verifier finding was logged in any of rounds 1-6 — clean throughout)
- [x] acceptance-verifier: met — 2026-07-06 (round 7, final pass — acceptance-verifier is directly attested running in round 3's stale-citation sweep; clean/met on this final round)
- [x] design-compliance-reviewer: clean — 2026-07-06 (round 7, final pass; no distinct design-compliance-reviewer finding was logged in any of rounds 1-6 — covered by the same review-fleet pass as rules-compliance-reviewer, no separate design-side finding surfaced)
- [x] Committed: `dd9ee36`

**Exit Sequence** — run at phase boundary (see Phase Execution Protocol; canonical spec
`~/.claude/commands/execute-plan.md` Step 3.d–3.h): resolve `$BASE` (Phase 1 → `git merge-base
HEAD main`), fan out the 5 reviewers + N deviation-judges in parallel, coordinator writes
Evidence + gates, handle verdicts, prompt commit.

---

### Phase 2: Unified config layer — per-server fresh-copy of all 4 configs from repo canonical
**PR scope**: Adopt ONE config model for all 4 configs (Game.ini, GUS, ArkShop, Permissions):
repo canonical → fresh per-server copy on boot → repo wins. Make `WindowsServer` a real per-server
dir holding copied Game.ini + seeded GUS (+ SessionName); make plugin configs deploy per-server
from repo seeds (ArkShop existing, Permissions NEW); remove the now-purposeless shared
`./plugins-config` bind. Single server still boots correctly.
**Branch**: `feat/m3-unified-config`
**Flag**: N/A
**Est. lines**: ~160
**Executor tier**: complex
**Ships via**: `/pr`
**Objective**: After this phase, every config is a **fresh per-server copy from its repo canonical
each boot** (repo wins, runtime edits discarded) — no shared writable config files anywhere, so N
servers booting simultaneously never contend. `WindowsServer` is a real per-server dir (on the
per-server game volume) holding a copied `Game.ini` and a seeded `GameUserSettings.ini` (+ injected
`SessionName`); ArkShop + Permissions config.json deploy per-server from `config/arkshop.config.json`
+ the NEW `config/permissions.config.json` (+ injected DB settings — nested `Mysql` block for
ArkShop, flat root-level `Mysql*` keys for Permissions). The single `the-center` server
boots and behaves exactly as M2 (regression-safe).
**Why this phase exists**: This is the precondition for N servers sharing config without
corruption. Two problems with today's model: (1) `WindowsServer` is a whole-dir symlink →
`/home/container/config` (entrypoint.sh:457-458), so the server-rewritten GUS lives in the shared
bind — N servers clobber it on shutdown. (2) Plugin configs deploy to ONE shared `./plugins-config`
bind via non-atomic `cp` (entrypoint.sh:338) — N servers booting in parallel race a torn read →
loud boot fail (Decision Ledger #5c). The fix for BOTH is the same: fresh per-server copies. Tagged
**complex** because it reworks the load-bearing `WindowsServer` symlink + the plugin-config deploy
path that M1/M2 depend on. **The race-safety is structural**: once every config is a per-server file
on each map's own volume, the files are physically distinct and CANNOT contend regardless of timing.
This phase establishes the structure on one server; Phase 3 proves it under simultaneous boot +
shutdown of N.
**Current-state anchors**:
- `entrypoint.sh:455-458` — config dir creation + `WindowsServer` **whole-dir** symlink → `/home/container/config` (replace `ln -sfn /home/container/config "$config_link"` at :458)
- `entrypoint.sh:103-184` — `deploy_plugins()` stash/restore of plugin config.json across the /opt→Win64 sync (:124-131 stash, :165-174 restore) — becomes redundant for repo-deployed plugins (setup_plugin_configs overwrites from repo anyway); confirm it's not broken, simplify if clean
- `entrypoint.sh:295-350` — `setup_plugin_configs()`: the `cp` seed (:338), the seed-if-absent branch (:340-343), the file-symlink to the shared bind (:346), and `host_root=/home/container/plugins-config` (:317) — all reworked to per-server deploy-from-repo
- `entrypoint.sh:352-387` — `_inject_mysql_block()`: **has symlink-resolution logic** (`dest="$(readlink -f "${cfg}")"` at :371, comment :365-367, `mv "${tmp}" "${dest}"` at :386) that BREAKS when the target is now a real file. Must become a plain atomic `mv "${tmp}" "${cfg}"` onto the real per-server config; drop the `dest`/readlink resolution; update the comment.
- `entrypoint.sh:389-440` — `inject_plugin_db_config()` (the CALLER): hardcoded paths `${win64}/ArkApi/Plugins/{ArkShop,Permissions}/config.json` (:422,:435) are already per-server-correct, BUT its comments (:399-405) describe "host-bound path via the symlink"/"plugins-config host bind" — STALE after the rework, must be updated
- `docker-compose.yml:100` — the `./plugins-config:/home/container/plugins-config` bind to remove
- `.gitignore:7` — `plugins-config/**` (orphaned after the bind removal — remove) + the tracked `plugins-config/.gitkeep`
- `docs/internal/design/economy/shop.md:268-289` — §11 "Build & deploy" describes the OLD deploy model (copy → `plugins-config/ArkShop/config.json` host bind) — stale, must update to per-server deploy
- `config/GameUserSettings.ini:1` — `;METADATA=` header (server-rewritten file)
- `config/Game.ini` — loot tables (1.2 MB; copied per-server)
**Files (expected scope)**: `entrypoint.sh`, `config/permissions.config.json` (NEW tracked seed),
`docker-compose.yml` (remove the `./plugins-config` bind), `.gitignore` (remove `plugins-config/**`),
`plugins-config/` (delete the orphaned dir + `.gitkeep`), `docs/internal/design/economy/shop.md`
(§11 deploy-model update), `docs/internal/decisions/0004-shared-config-model.md`
**Scope Boundary**:
- **In scope (this phase delivers)**: "Shared config across cluster (`Game.ini`, `GameUserSettings.ini`)" (ledger); "Shared plugin configs across cluster (ArkShop `config.json`, Permissions)" (ledger — delivered via per-server deploy-from-repo, the race-safe form); "Per-server config overrides (map, ports, `SessionName`)" (ledger).
- **Explicitly NOT delivered (deferred to later milestone)**: none.
- **Out of scope (NOT a deferral — never this phase's job)**: defining the multi-map services (Phase 3); the cluster transfer args (Phase 1, already landed); any change to the loot/shop *generators* (separate shipped workstreams — this phase only changes how their OUTPUT deploys per-server).
**Deviation rule**: MAY touch adjacent entrypoint helpers if the rework requires it (e.g. a shared
`seed_config` helper). Document each. Unrelated refactor → STOP.
**Steps**:
1. Replace the whole-dir symlink at entrypoint.sh:457-458. Make `WindowsServer` a **real
   directory** on the per-server game volume: `mkdir -p
   "${ARK_DIR}/ShooterGame/Saved/Config/WindowsServer"` (no longer `ln -sfn … /home/container/config`).
   **Note for the executor**: the deep-bind warning at `docker-compose.yml:96-99` is about a Docker
   *bind-mount* root-creating intermediate dirs and blocking the non-root user. It does NOT apply
   here — `WindowsServer` becomes a real dir on the `ark-game` volume the container user already
   owns. Do not revert to the whole-dir symlink out of fear of that comment.
2. **Copy** (not symlink — Patrick's call for uniformity + defense-in-depth) `Game.ini` into it
   each boot: `cp /home/container/config/Game.ini "${WindowsServer}/Game.ini"`. A per-server copy
   absorbs any defensive engine write without touching the shared canonical.
3. Add a `seed_gus()` step (mirror the :334 `cp` idiom): each boot, copy
   `/home/container/config/GameUserSettings.ini` → `${WindowsServer}/GameUserSettings.ini` (real
   writable file), then inject `SessionName=${SESSION_NAME}`. Injection must be **line-oriented**:
   if a `SessionName=` line exists under `[SessionSettings]`, replace its value; if the key is
   absent, append it under `[SessionSettings]`; if the section itself is absent, append section +
   key. (Seed comes from the canonical each boot — comments intact — so inject always operates on a
   known-good file.)

**CHECKPOINT** — engine-INI path reworked: `WindowsServer` is a real per-server dir holding a copied `Game.ini` + a seeded `GameUserSettings.ini` (SessionName injected); no whole-dir symlink remains. Single server still boots green with loot + GUS tuning applied.

4. Capture the image-default Permissions config into a NEW tracked repo seed
   `config/permissions.config.json`: grab `Win64/ArkApi/Plugins/Permissions/config.json` from the
   built image (or dell's deployed copy), blank the flat root-level Mysql credential values
   (`MysqlUser`/`MysqlPass`/`MysqlDB` — KEEP the keys themselves, the `has("UseMysql")` guard needs
   them; the entrypoint injects real values at boot, as it does for the ArkShop seed's nested
   `Mysql` block), commit it secret-free.
5. Rework `setup_plugin_configs()` to **per-server deploy-from-repo for BOTH plugins**: deploy
   `config/arkshop.config.json` → the per-server ArkShop plugin dir's `config.json`, and
   `config/permissions.config.json` → the per-server Permissions plugin dir's `config.json` — each a
   real file written directly into the plugin dir on the per-server game volume (NOT a symlink to a
   shared bind). Drop the seed-if-absent branch (:336-339) and the shared-bind file-symlink (:342),
   and the now-unused `host_root=/home/container/plugins-config` (:313).
6. Update the mysql-injection path (BOTH functions — this is the silent-DB-less-boot risk):
   - `_inject_mysql_block()` (:348-383): remove the symlink-resolution logic (`dest="$(readlink -f
     "${cfg}")"` at :367 + the comment :361-363 + `mv "${tmp}" "${dest}"` at :382). The plugin config
     is now a REAL file, so this becomes a plain atomic `mv "${tmp}" "${cfg}"`. Update the comment
     (no more symlink).
   - `inject_plugin_db_config()` (:385-436): the hardcoded paths (:418,:431) already point at the
     per-server plugin-dir config.json — KEEP them. Update the stale comments (:395-401) that
     describe "host-bound path via the symlink" / "plugins-config host bind" → now a real per-server
     file. The Permissions inject guard keys on `has("UseMysql")` (entrypoint.sh:508, loud-WARN
     fallback :512) because the plugin's real schema is FLAT — its Mysql keys sit at the JSON root
     (`UseMysql`/`MysqlHost`/`MysqlUser`/`MysqlPass`/`MysqlDB`/`MysqlPort`), unlike ArkShop's
     nested `Mysql` object. The captured seed must carry those flat root-level keys for the guard
     to fire, or Permissions connects DB-less; do NOT "normalize" the seed to a nested `Mysql`
     block — the plugin would silently ignore it and boot on its local store (ADR 0004
     §Consequences); verify at boot.

**CHECKPOINT** — plugin-config path reworked: ArkShop + Permissions deploy per-server from repo seeds (new `config/permissions.config.json` captured), DB inject works on the real-file path via atomic `mv` (no symlink resolution); `jq .Mysql` (ArkShop, nested) / `jq '{UseMysql,MysqlHost,MysqlUser,MysqlPass,MysqlDB,MysqlPort}'` (Permissions, flat schema — FRAGO 003) shows the injected values on each plugin config.

7. `deploy_plugins()` stash/restore (:120-127 + :161-170): confirm it's not broken by the model
   change (it stashes/restores whatever config.json exists across the /opt→Win64 sync; setup then
   overwrites from the repo seed anyway, so the stash is now redundant for ArkShop/Permissions). If
   it's cleanly removable without affecting a non-repo-deployed plugin, simplify; otherwise leave it
   (redundant but harmless) and note why in the PR.
8. Remove the `./plugins-config:/home/container/plugins-config` bind from `docker-compose.yml:100`,
   the `plugins-config/**` line from `.gitignore:7`, and **`git rm`** the tracked
   `plugins-config/.gitkeep` (it's tracked, not just gitignored — a plain `rm -rf` would leave it in
   the index) then delete the now-empty `plugins-config/` dir (no longer used — plugin configs now
   deploy from the `./config` repo seeds to per-server plugin dirs). Grep-confirm nothing else
   references `plugins-config` before removing.

**CHECKPOINT** — the shared `./plugins-config` bind + its `.gitignore:7` line + the tracked `.gitkeep` are fully removed and grep-clean (`deploy_plugins()` stash simplified-or-noted); no shared writable config path remains anywhere. Single server boots green.

9. Update `docs/internal/design/economy/shop.md` §11 (Build & deploy, :268-289): the deploy model
   changed from "copy → `plugins-config/ArkShop/config.json` host bind" to "copy → per-server ArkShop
   plugin dir, no host bind". Keep the doc accurate (a diff that makes a doc wrong is incomplete per
   `rules/documentation.md`).
10. Write ADR `docs/internal/decisions/0004-shared-config-model.md`: the unified model (repo
   canonical → per-server fresh copy each boot → repo wins, for all 4 configs); the two problems it
   solves (GUS shared-write clobber + plugin-config concurrent-boot `cp` race, Ledger #5c); why
   per-server volumes make it structurally race-free; the Permissions edit-on-host→deploy-from-repo
   flip (safe — live group data is in the shared MariaDB, Ledger #5e); the `./plugins-config` bind
   removal. Rejected: shared writable configs (clobber/race); per-server config *generator*
   (overkill — only SessionName differs, injected not generated); keeping the whole-dir symlink
   (the GUS-clobber bug); per-config special-casing (more conditionals, same result — Patrick).
11. Register ADR `0004-shared-config-model.md` `[locked]` in `.claude/design-sources.md` (append a
    row) so a future diff that re-introduces a shared writable config BLOCKs at the design gate.

**CHECKPOINT** — docs complete: `shop.md` §11 updated to the per-server deploy model, ADR 0004 written + registered `[locked]`. Only the dell single-server regression-guard (step 12) remains.

12. Regression-guard: boot `the-center` ALONE on dell, confirm loot (Game.ini) + shop catalog +
    Permissions + GUS tuning all apply and the server advertises (proves the rework didn't break
    single-server); confirm `WindowsServer` is a real dir with copied `Game.ini` + writable `GUS`,
    the plugin dirs hold real per-server config.json (not symlinks), and **`jq .Mysql` on the
    ArkShop config (nested) plus `jq '{UseMysql,MysqlHost,MysqlUser,MysqlPass,MysqlDB,MysqlPort}'`
    on the Permissions config (flat schema — FRAGO 003) show the injected DB settings** (proves
    the inject-path rework didn't silently DB-less the plugins).
**Acceptance criteria**:
- [ ] `the-center` boots alone on dell with loot (Game.ini), shop catalog, Permissions, and GUS tuning all applied (single-server regression intact)
  - Evidence: DELL-BOOT-ONLY — not verifiable from this workstation. Static proxies all green: `bash -n` clean, `docker compose --env-file .env.test.example config` resolves clean, `docker buildx build --check` clean, full copy/seed/inject flow simulated (see below). Honest: unchecked until a live dell boot.
- [ ] `${WindowsServer}` is a real directory (NOT a symlink); both `Game.ini` and `GameUserSettings.ini` inside it are real regular files (`stat`/`readlink` evidence), copied from `config/` each boot
  - Evidence: STATIC SIM PASSED (live dell stat pending): the exact main() block (entrypoint.sh — `[[ -L ]] && rm -f` → `mkdir -p` → `cp Game.ini` → `seed_gus`) run in a sandbox against a volume holding the OLD whole-dir symlink: link removed (not followed), real dir created, both files real regular files, shared canonicals untouched; warm-boot re-run idempotent.
- [ ] `GameUserSettings.ini` `SessionName` matches `${SESSION_NAME}` (injected, not the canonical's value)
  - Evidence: STATIC SIM PASSED (live dell grep pending): verbatim-extracted `seed_gus()` run against the REAL CRLF canonical → exactly one `SessionName=<env value>` line, canonical's `ARK-Test` gone, all other lines byte-identical. All 3 spec cases + key-at-EOF + `SessionName = x` (spaced) variants pass; double-run idempotent.
- [ ] ArkShop + Permissions `config.json` are real per-server files in their plugin dirs (NOT symlinks); `config/permissions.config.json` exists as a secret-free tracked seed
  - Evidence: Seed half VERIFIED: `config/permissions.config.json` tracked, captured from the REAL image default (`ark-asa:gate-check`, built 2026-07-06 from current Dockerfile, `/opt/asaapi/ArkApi/Plugins/Permissions/config.json`), creds blanked (`MysqlUser/Pass/DB=""`, `UseMysql:false`). Deployed-files half: setup_plugin_configs writes via plain `cp` (no `ln`) — real-file property simulated; live dell `readlink` pending.
- [ ] **DB inject still works on the real-file path**: `jq .Mysql` on the ArkShop config AND `jq '{UseMysql,MysqlHost,MysqlUser,MysqlPass,MysqlDB,MysqlPort}'` on the Permissions config shows the injected host/user/db — proves `_inject_mysql_block`'s symlink-resolution removal didn't break the write (the silent-DB-less-boot risk)
  - Evidence: STATIC SIM PASSED (criterion re-worded per FRAGO 003 — the Permissions plugin's real schema is FLAT, root-level Mysql* keys; rationale in ADR 0004 §Consequences + `audit.md` FRAGO 003): verbatim-extracted `_inject_mysql_block` run on copies of both real seeds → ArkShop `jq .Mysql` shows injected host/user/db (nested schema); Permissions `jq '{UseMysql,MysqlHost,…}'` shows them at the JSON root (flat schema). Re-verified 2026-07-06 after the env-var password rework (see Review-round fixes below), incl. a special-char password round-tripping byte-exact through both schemas. Live dell check pending.
- [x] **The committed `config/permissions.config.json` seed carries the plugin's real FLAT schema** (root-level `UseMysql`/`MysqlHost`/`MysqlUser`/`MysqlPass`/`MysqlDB`/`MysqlPort` keys) so the `has("UseMysql")` guard at entrypoint.sh:508 fires — otherwise Permissions silently boots DB-less and the inject-check above is vacuously skipped
  - Evidence: VERIFIED (criterion re-worded per FRAGO 003 — the shipped image-default Permissions config is FLAT, `jq 'has("Mysql")'` = false on the plugin's own default; a nested `Mysql` key would make the old guard fire but inject a block the plugin never reads. Rationale in ADR 0004 §Consequences + `audit.md` FRAGO 003): `jq -e 'has("UseMysql")'` on the tracked seed returns true (guard fires); guard grep-confirmed live at entrypoint.sh:508, loud-WARN fallback at :512 (a config failing the guard warns instead of silently skipping). Re-verified 2026-07-06 against the current seed + entrypoint.sh, not inherited from prior verdicts.
- [x] `./plugins-config` bind removed from `docker-compose.yml`, `plugins-config/**` removed from `.gitignore`, orphaned `plugins-config/` dir deleted; grep confirms no remaining `plugins-config` reference in entrypoint/compose
  - Evidence: bind line removed (compose config resolves clean, no `plugins-config` in resolved output); `.gitignore` lines 6-7 removed; `git rm plugins-config/.gitkeep` + dir deleted (git status: `D plugins-config/.gitkeep`); repo-wide grep of entrypoint/compose/gitignore/README/docs/config/tools → only ADR 0004's historical Context mentions remain (describing the removed model — correct ADR content).
- [x] `docs/internal/design/economy/shop.md` §11 updated to the per-server deploy model (no stale `plugins-config` host-bind description)
  - Evidence: shop.md §11 Deploy-model bullet rewritten (per-server plugin dir, no host bind, Permissions same model, links ADR 0004); stale `the-island` service name in the tweak loop fixed to `the-center`; grep confirms no `plugins-config` mention left in shop.md.
- [x] ADR `0004-shared-config-model.md` exists with the unified model + the two races it solves + rejected alternatives (doc-type: adr); registered `[locked]`
  - Evidence: `docs/internal/decisions/0004-shared-config-model.md` (doc-type "adr", matches 0003 template): unified model table, GUS shared-write clobber + concurrent-boot cp race, structural race-freedom, Permissions flip rationale, bind removal, all 4 rejected alternatives; registered `[locked]` in `.claude/design-sources.md` (row appended incl. the flat-schema warning).
**Quality gate**:
- [x] Every config copy/seed is idempotent (safe every boot)
  - Evidence: all deploys are `mkdir -p`/`cp`-overwrite/`awk`+atomic-`mv` (no seed-if-absent state); seed_gus + WindowsServer block double-run in sandbox → identical result; inject idempotent (env-constant within a boot, unchanged property).
- [x] No shared writable config file remains (no whole-dir `WindowsServer` symlink; no plugin-config symlink to a shared bind)
  - Evidence: `ln -sfn` for WindowsServer and the plugin-config file-symlink both removed; grep of entrypoint.sh — remaining `ln` calls are cluster-dir + steamclient sdk only; the only shared mount (`./config`) is never a runtime write target.
- [x] `_inject_mysql_block` no longer resolves a symlink (operates on a real file via atomic `mv`); its comment matches
  - Evidence: `readlink -f`/`dest` gone; plain `mv "${tmp}" "${cfg}"`; header comment rewritten (real per-server file, atomic tmp+mv, nested/flat schema doc).
- [ ] Dirty-volume transition is clean: booting Phase 2 on a volume that still holds the OLD symlinked `config.json` (from a pre-Phase-2 boot) correctly replaces it with a real file (not a dangling symlink) — verify on dell's existing `ark-game` volume, not just a fresh one
  - Evidence: DELL-BOOT-ONLY as written. Static analysis: plugin-dir config symlinks are cleared by deploy_plugins' existing `rm -rf ArkApi` clean-replace before setup writes real files (stash `[[ -f ]]` skips a dangling link); the WindowsServer whole-dir-symlink transition simulated green (link removed not followed, canonicals untouched). Live dell volume check pending.
- [x] `inject_plugin_db_config` comments updated (no "host bind"/"symlink" language)
  - Evidence: comments rewritten (per-server real files from repo seeds); repo grep for `plugins-config`/host-bind language in entrypoint.sh → none.
- [x] SessionName injection handles the `[SessionSettings]` block whether present or absent
  - Evidence: sandbox runs of the verbatim function: key-present (replace), section-present/key-absent mid-file (append inside section), section-absent (append section+key), section-at-EOF, spaced-key variant — all green, CRLF-tolerant.
- [x] Permissions seed committed is secret-free (Mysql injected at runtime, like ArkShop); seed carries the flat `UseMysql`/`Mysql*` root-level keys so the `has("UseMysql")` inject guard fires
  - Evidence: SECRET-FREE half VERIFIED (`MysqlUser/Pass/DB` blank, `UseMysql:false`; image default's placeholder `root`/`pass`/`arkdb` stripped). Flat-keys half VERIFIED (criterion re-worded per FRAGO 003 — rationale in ADR 0004 §Consequences + `audit.md` FRAGO 003): `jq -e 'has("UseMysql")'` on the seed = true; guard fires at entrypoint.sh:508. Re-verified 2026-07-06 against the current seed + entrypoint.sh.
- [x] `ENABLE_ASAAPI=0` vanilla path still copies Game.ini + seeds GUS (plugins skipped when disabled — confirm the vanilla path is unaffected)
  - Evidence: the Game.ini copy + seed_gus call sit in main() BEFORE and OUTSIDE the `ENABLE_ASAAPI` branch (unconditional every boot); setup_plugin_configs/inject remain inside the `== "1"` branch; launch-string construction untouched by this phase.
- [x] No stale doc left: shop.md §11 + any README plugins-config mention reflect the new model
  - Evidence: shop.md §11 rewritten; README "Plugin config edit loop" section rewritten to deploy-from-repo (tracked seeds, links ADR 0004); repo-wide grep — only ADR 0004's historical Context references remain.
**Verification**: dell single-server boot → `docker compose exec the-center sh -c 'ls -la
<WindowsServer> && ls -la <ArkShop plugin dir>/config.json <Permissions plugin dir>/config.json'`
shows real files (no symlinks); `grep SessionName <WindowsServer>/GameUserSettings.ini` shows the
env value; `jq .Mysql` (ArkShop, nested) / `jq '{UseMysql,MysqlHost,MysqlUser,MysqlPass,MysqlDB,MysqlPort}'`
(Permissions, flat schema — FRAGO 003) shows the injected block; `git status` shows
`config/permissions.config.json` tracked + secret-free and `plugins-config/` gone;
`grep -rn plugins-config entrypoint.sh docker-compose.yml` returns nothing.

**Review-round fixes (2026-07-06, applied by a fresh executor after the review fleet's first
pass)** — 3 should-fix/minor items plus 1 already-ratified FRAGO application:
- **SHOULD-FIX** (code-reviewer): `docker-compose.yml`'s `./config` bind comment still said "The
  entrypoint symlinks this into the engine's config path" — stale since this phase deleted the
  symlink model. Rewritten to the per-server-copy model ("deploys fresh per-server COPIES … repo
  wins") with an explicit pointer to ADR 0004, matching the accurate comment already at the
  `WindowsServer` deploy block in `entrypoint.sh` main().
- **MINOR** (code-reviewer): `seed_gus()` wrote its awk-injected lines (`SessionName=`, and the
  `[SessionSettings]` header in the section-absent case) LF-only into a CRLF source, producing
  mixed line endings — the function was CRLF-*tolerant* (reading) but not CRLF-*consistent*
  (writing). Fixed: an `/\r$/ { eol = "\r" }` detection rule sets the injected-line ending from
  the source file's own, so every injected line adopts the source's ending; comment updated to
  say so. Verified with the verbatim-extracted function (only the canonical-path constant
  substituted to the sandbox): all 3 spec cases on CRLF inputs (key-present replace,
  section-present/key-absent append, section-absent append) + section-at-EOF variant → output
  uniformly CRLF (crlf-line-count == total-line-count, exactly one `SessionName=<env>` line);
  LF-input regression (all 3 cases) → output stays pure LF (zero `\r` introduced); the REAL
  484-line CRLF canonical → 484/484 CRLF; double-run byte-identical (idempotent).
- **MINOR** (security): `_inject_mysql_block()` passed the DB password to jq via `--arg`,
  transiently visible in `/proc/<pid>/cmdline` during the jq exec. Fixed: the password now
  reaches jq through a per-invocation environment variable (`INJECT_MYSQL_PASS="…" jq …`, read as
  `env.INJECT_MYSQL_PASS` in both the nested and flat filters) — the same env-passing idiom
  `seed_gus()` already uses for awk (`GUS_SESSION_NAME`); jq env values are plain strings, never
  evaluated as filter code. Non-secret values stay `--arg`. Comments in both functions updated.
  Verified with the verbatim-extracted function on copies of both real seeds, jq shimmed by a
  wrapper recording every invocation's full argv: a special-char password
  (`s3cr#t "quoted" $dollar \back` + backtick) round-trips byte-exact into BOTH schemas
  (ArkShop nested `jq .Mysql`, Permissions flat root keys), and zero of 48 recorded argv lines
  contain the secret.
- **FRAGO 003 applied** (already ratified — risk-neutral re-word, auto-apply + log; rationale in
  ADR 0004 §Consequences + `audit.md` FRAGO 003): the two ACs + one Quality-gate item that assumed
  a NESTED Permissions `Mysql` key re-worded to the plugin's real FLAT schema — the Permissions
  verification command is now `jq '{UseMysql,MysqlHost,MysqlUser,MysqlPass,MysqlDB,MysqlPort}'`,
  the seed criterion now names the root-level `UseMysql`/`Mysql*` keys and the `has("UseMysql")`
  guard at its ACTUAL current line (`entrypoint.sh:508`, loud-WARN fallback `:512` — the plan's
  `:436` was drift), and the phase-level **Verification** block's `jq .Mysql <plugin>` command got
  the same schema-split correction (same defect, same amendment). The re-worded seed AC + QG item
  ticked after fresh verification against the current tree (`jq -e 'has("UseMysql")'` on the seed
  = true; seed secret-free), NOT inherited from prior verdicts; the inject AC stays unticked
  (evidence static-only, live dell check pending — consistent with its sibling dell-gated ACs).
  The dangling "see phase deviations" cross-references (no such section exists) now point at the
  real homes: ADR 0004 §Consequences + `audit.md`'s FRAGO 003 entry. NOT amended (surfaced for
  the conductor, outside FRAGO 003's stated scope): the ¶1 risk-table row and Phase 2 Step 6 /
  CHECKPOINT texts still carry the historical `jq .Mysql`-on-both / `has("Mysql")`/`:436` wording.
- All fixes re-verified: `bash -n entrypoint.sh` clean, `docker compose --env-file
  .env.test.example config` resolves clean, `docker buildx build --check` clean ("no warnings
  found"), plus the two live sandbox matrices above (CRLF/LF injection; argv-audited DB inject on
  both real seeds).

**Review-round fixes (2026-07-06, second round — applied by a fresh executor)** — 1
already-ratified FRAGO application plus 1 minor doc fix:
- **FRAGO 004 applied** (already ratified — risk-neutral plan-text re-word, auto-apply + log; the
  follow-on to FRAGO 003, closing the locations that entry explicitly surfaced as outside its
  scope): every remaining plan-text instance of the falsified nested-Permissions-Mysql-schema
  assumption re-worded to the plugin's real FLAT schema (root-level `UseMysql`/`MysqlHost`/
  `MysqlUser`/`MysqlPass`/`MysqlDB`/`MysqlPort`; rationale in ADR 0004 §Consequences + `audit.md`
  FRAGO 003/004). **Six** instances fixed — the FRAGO named 4 and mandated a grep of the Risks
  table + the whole Phase 2 section rather than trusting the count; the grep found 2 more: (1) the
  Risks-table "Silent DB-less plugin boot" row (`has("Mysql")` guard `:436` → `has("UseMysql")`
  at its ACTUAL current line, `entrypoint.sh:508` + loud-WARN `:512`, grep-confirmed against the
  live file before re-wording; mitigation text now schema-split); (2) Phase 2 Step 6's guard
  narrative ("seed must carry a `Mysql` block" — the literal OPPOSITE of ADR 0004 §Consequences'
  do-NOT-normalize warning → seed must carry the flat root-level keys, nested block silently
  ignored); (3) the CHECKPOINT after Step 6 (`jq .Mysql`-on-both → the schema-split command pair,
  mirroring the phase Verification block's FRAGO 003 wording); (4) Step 12's regression-guard text
  (same schema-split fix); (5) the phase Objective's "(+ injected `Mysql`)" shorthand (now names
  both schemas); (6) Step 4's "strip any `Mysql` secret block" capture instruction (now: blank the
  flat `MysqlUser`/`MysqlPass`/`MysqlDB` VALUES, keep the keys — stripping them would defeat the
  `has("UseMysql")` guard). No code touched: entrypoint.sh already implements the flat schema
  correctly (guard verified live at :508/:512); this round is plan-text only. NOT amended
  (outside FRAGO 004's stated scope of the Risks table + Phase 2; surfaced for the conductor):
  the Context & Why deliverables list and the Research Findings config-matrix row still carry the
  loose "injected `Mysql` (block)" shorthand for Permissions; Phase 1's dated fourth-round
  Review-round entry logging the historical `:432`→`:436` anchor refresh is a dated record, left
  untouched per this plan's own no-rewrite-of-prior-entries convention.
- **MINOR** (code-reviewer + graveyard-auditor, both flagged): `README.md:37` — the "Fast config
  loop" section still said `docker compose restart the-island`; the service is `the-center`.
  Fixed (the sibling "Plugin config edit loop" instance was already fixed in the prior round;
  repo grep confirms no `the-island` reference remains in README.md).

**Phase Review Gates**:
- [ ] code-reviewer: <verdict + ISO timestamp>
- [ ] rules-compliance-reviewer: <verdict + ISO timestamp>
- [ ] plan-adherence-verifier: <verdict + ISO timestamp>
- [ ] acceptance-verifier: <verdict + ISO timestamp>
- [ ] design-compliance-reviewer: <verdict + ISO timestamp>
- [ ] Committed: <commit SHA>

**Exit Sequence** — run at phase boundary: resolve `$BASE` (Phase 1's committed SHA), fan out 5
reviewers + N judges, coordinator writes Evidence + gates, handle verdicts, prompt commit.

---

### Phase 3: Multi-map compose + dell cluster boot-test (transfer + shared points + config consistency)
**PR scope**: Replicate the parameterized server into 2 map services (The Center, Genesis Part 1)
via YAML anchors, sharing mariadb + ark-cluster + read-only config, with distinct ports + per-map
game volumes. Deploy to dell, validate the full cluster end-to-end.
**Branch**: `feat/m3-multi-map-cluster`
**Flag**: N/A
**Est. lines**: ~160 (mostly compose)
**Executor tier**: standard
**Ships via**: `/pr`
**Objective**: After this phase, `docker compose up` on dell brings up MariaDB + 2 ASA map servers
(The Center + Genesis Part 1) sharing one economy + one cluster transfer dir + one canonical config.
A player can transfer between maps, points are shared, and shop + shared-class loot are identical
across maps. (Genesis-EXCLUSIVE crates serve vanilla loot until Beacon ingests Genesis Part 1 — see
Risks / Future Requirements.)
**Why this phase exists**: This is the milestone payoff — the actual multi-map cluster. It comes
last because it needs Phase 1's wiring and Phase 2's shareable config as the unit to replicate.
**Current-state anchors**:
- `docker-compose.yml:50-114` — the single `the-center` service (the template to anchor + replicate)
- `docker-compose.yml:116-122` — volumes block (add per-map game volumes)
- Map class strings: `TheCenter_WP` from `docs/internal/reference/beacon-asa/maps.tsv:7`; `Genesis_WP` verified from deployed-server pak strings (Decision Ledger #9 / Research Findings — NOT in the 2026-06-21 Beacon snapshot)
- `README.md` — add the cluster section
**Files (expected scope)**: `docker-compose.yml`, `.env.test.example`, `.env.prod.example`, `README.md`
**Scope Boundary**:
- **In scope (this phase delivers)**: "Multi-server (2+ maps) pointing at the shared MariaDB economy" (ledger); "Per-map game/config volumes + shared cluster volume layout" (ledger).
- **Explicitly NOT delivered (deferred to later milestone)**: shared read-only game-INSTALL volume (M4 optimization — each map gets a full game volume in M3, per Decision Ledger #13); ops CLI / backups (M4).
- **Out of scope (NOT a deferral — never this phase's job)**: a compose generator (M4); changing loot/shop content; VPS provisioning (operator owns prod per roadmap Out of Scope).
**Deviation rule**: MAY adjust ports/volume names if a collision is found on dell. Document each.
Adding a 4th map or any generator → STOP, that's scope creep / M4.
**Steps**:
1. Refactor `the-center` into a YAML anchor `&ark-server` capturing the shared bulk (build/image,
   depends_on, the shared env block, the shared volume mounts — the read-only `./config` repo-seed
   bind + `ark-cluster`; NOTE the `./plugins-config` bind was removed in Phase 2 — do not re-add it,
   stop_grace, restart, logging).
2. Define 2 services using `<<: *ark-server`, each overriding: `container_name`, `SERVER_MAP`
   (`TheCenter_WP` / `Genesis_WP`), `SESSION_NAME`, the published game port
   (7777 / 7779 udp) + `SERVER_PORT`, the published RCON port (27020 / 27021 tcp) +
   `RCON_PORT`, and its own per-map game volume (`ark-game-center` / `ark-game-genesis`). Both
   inherit the SAME `ARK_CLUSTER_ID` + `ark-cluster` mount + DB env. (The Center keeps the existing
   single-server ports 7777/27020, unchanged; Genesis takes 7779/27021.)
3. Declare the 2 per-map game volumes + keep the shared `ark-cluster`, `ark-db` in the volumes block.

**CHECKPOINT** — compose defines `the-center` + `genesis` from the `&ark-server` anchor with per-map ports + per-map game volumes + shared cluster/DB; `docker compose config` parses clean. Not yet deployed.

4. Update `.env.test.example` / `.env.prod.example` with the per-map port variables + the single
   `ARK_CLUSTER_ID` + a comment on the 2-map layout.
5. Add a README "Cluster" section: the edit→push→restart config loop (one canonical config, all
   maps), per-map ports, the clusterid secret, how a player transfers between maps, **and the Genesis
   loot-gap note** (Genesis-exclusive crates serve vanilla loot until Beacon ingests Genesis Part 1;
   generic/shared beacon crates are already custom per `loot-crates.md` Rule 1 — see the
   Documentation Deliverables row + Future Requirements). Also scrub any stale M2 README mention of
   the `./plugins-config` edit-on-host loop (removed in Phase 2 — config is now edit-`config/`-in-repo
   → restart).

**CHECKPOINT** — `.env` examples + README cluster section (incl. the Genesis loot-gap note) complete; the 2-map stack is fully authored and ready to deploy + validate on dell (steps 6–7).

6. Deploy to dell (`git pull` → `docker compose up -d --build`), boot both.
7. **Genesis transfer-capability gate — run FIRST, before treating Center↔Genesis as the transfer
   proof.** Attempt a real upload+download in BOTH directions (Center→Genesis and Genesis→Center) with
   a character + a dino + an item, then confirm they arrive. **On Genesis, use a Mission Terminal — NOT
   an obelisk (Genesis Part 1 has none; see Research Findings).** Community sources place a Mission
   Terminal around **~85, 63 in the Bog biome** — use `cheat TP` / the map marker to reach it for the
   test (the terminal is transfer-only, like an Extinction City Terminal; no Tek-tier grind, unlike a
   Tek Transmitter). On The Center, the standard obelisk/transmitter is fine. This is a **Patrick
   in-game** step (mirrors the plan's other in-game verification steps). Web research has already
   confirmed the map *design* supports bidirectional transfer via these terminals; this step confirms
   THIS server's live behavior. **If the live test unexpectedly blocks a direction, STOP and surface a
   blocking deviation to the conductor for a FRAGO** rather than force-passing/failing the transfer ACs
   on an assumption. If both directions work, proceed to the validation ACs below.
**Acceptance criteria**:
- [ ] Both map servers boot on dell and each advertises for join on its own port (Center 7777 / Genesis 7779)
  - Evidence: (filled at phase completion — dell logs per service)
- [ ] **Genesis Part 1 transfer confirmed BIDIRECTIONAL in live behavior via the Mission Terminal** (step 7 gate): a real Center→Genesis AND Genesis→Center upload/download each succeed, using a Genesis **Mission Terminal** (~85,63 Bog biome) — NOT an obelisk (Genesis has none). The map design is already web-confirmed to support this; this AC confirms THIS server's live behavior. If the live test unexpectedly blocks a direction, this AC is met by *documenting the observed limitation* + the FRAGO that adapted the transfer proof — NOT by silently passing the transfer ACs below on an untested assumption.
  - Evidence: (filled at phase completion)
- [ ] Cross-map transfer works with a CHECKABLE artifact, not just eyeballing: after a player uploads a character (+ a dino + an item) on map A, a cluster transfer file appears under `${CLUSTER_DIR}/${ARK_CLUSTER_ID}/` on the shared `ark-cluster` volume (`docker compose exec the-center ls -la ${CLUSTER_DIR}/${ARK_CLUSTER_ID}/` shows it from a DIFFERENT service — proving the volume is genuinely shared, not per-container) — Patrick in-game upload + Claude verifies the file. (Uses whichever transfer direction step 7 confirmed works.)
  - Evidence: (filled at phase completion)
- [ ] Transfer is a MOVE not a DUPE: after downloading on map B, the character/dino/item arrives on B with correct identity AND is gone from A (guards the silent-dupe failure mode flagged in Risks) — Patrick in-game
  - Evidence: (filled at phase completion)
- [ ] Concurrent-shutdown GUS integrity: `docker compose stop` both servers together, then `docker compose up` — each server's `GameUserSettings.ini` retains its OWN `SessionName` and identical tuning (proves per-server volumes make GUS structurally clobber-proof, the Phase 2 invariant under N servers)
  - Evidence: (filled at phase completion)
- [ ] Points are shared: `SetPoints <eosid> <n>` via one server's RCON, then `GetPoints <eosid>` via a DIFFERENT server's RCON returns the same value (same MariaDB)
  - Evidence: (filled at phase completion)
- [ ] Config consistency: pop the same-tier **standard/shared** beacon crate on both maps → identical contents (class-keyed global override per `loot-crates.md` Rule 1); `/shop` catalog identical across maps (one canonical source); editing the repo config once + restart changes both maps. **Known exception:** Genesis-Part-1-EXCLUSIVE crate classes serve ASA vanilla loot (Beacon has no Genesis-P1 rows yet) — this is the documented deferral (Risks + Future Requirements), NOT a phase failure; verify it is the vanilla default, not a broken/empty table.
  - Evidence: (filled at phase completion)
- [ ] README cluster section documents the loop, ports, clusterid, and transfer flow (doc-type: how-to + reference)
  - Evidence: (filled at phase completion)
- [ ] `ENABLE_ASAAPI=0` on a service still produces the vanilla rollback for that map
  - Evidence: (filled at phase completion)
**Quality gate**:
- [ ] YAML anchor shares the bulk; per-service overrides are only map/ports/session/volume/container_name
- [ ] Both services use the SAME `ARK_CLUSTER_ID` + the SAME `ark-cluster` mount path
- [ ] No port collisions (2 distinct game + 2 distinct RCON ports), documented in `.env.*.example`
- [ ] Each map has its own game volume (saves isolated); cluster + DB volumes shared
- [ ] No secret committed (clusterid stays in `.env`)
- [ ] clusterid actually gates (optional adversarial check): temporarily set one service's `ARK_CLUSTER_ID` to a different value → it does NOT see the others' transfers → revert. Proves the clusterid is the gate, not just the shared dir.
**Verification**: dell `docker compose up -d` → `docker compose logs` shows 2× "successfully
started" + advertising; in-game transfer Center↔Genesis (Mission Terminal on the Genesis side — no obelisk there); `SetPoints` on The Center
RCON visible via `GetPoints` on Genesis RCON; pop a standard/shared beacon crate on each map to
confirm identical tables (shared classes; Genesis-exclusive crates are the documented vanilla-loot
exception); toggle `ENABLE_ASAAPI=0` on one service → vanilla boot.

**Phase Review Gates**:
- [ ] code-reviewer: <verdict + ISO timestamp>
- [ ] rules-compliance-reviewer: <verdict + ISO timestamp>
- [ ] plan-adherence-verifier: <verdict + ISO timestamp>
- [ ] acceptance-verifier: <verdict + ISO timestamp>
- [ ] design-compliance-reviewer: <verdict + ISO timestamp>
- [ ] Committed: <commit SHA>

**Exit Sequence** — final phase: run the cumulative reviewer-and-judge sweep with `model:
"opus"` against the cumulative diff (`git merge-base HEAD main` → BASE); on all-PASS flip
`status: active` → `status: done`.

## Quality Checklist (verify at completion)
- [ ] All inputs validated (N/A — no user input surface; env vars are operator-controlled, `:?` guards on required ones)
- [ ] Auth/authz enforced (N/A — no new endpoints; RCON already password-gated; clusterid is the transfer secret)
- [ ] Error handling: entrypoint fails loud on missing required env (`:?` in compose); cluster-dir creation idempotent
- [ ] No SQL injection, XSS, path traversal, or secret exposure (clusterid in `.env`, never committed)
- [ ] Performance: N/A (infra) — dell capacity checked (2× ASA ≈ 20 GB of 64)
- [ ] Tests: validation is boot + in-game behavior (game-server infra has no unit-test surface); each phase has a dell boot check
- [ ] Existing single-server `docker compose up` still works (Phase 2 regression check)
- [ ] Types complete (N/A — bash/yaml)
- [ ] Follows existing entrypoint/compose conventions (seed idiom, env-default block, flags construction)
- [ ] Every phase received all-reviewer + all-judge PASS before committing (Step 9a)
- [ ] Final cumulative reviewer sweep passed (Step 10f)
- [ ] Plan-file acceptance-criteria checkboxes accurate across all phases (Step 9b)

## Anti-Pattern Callouts

- **Splitting into commits instead of PRs**: each of the 3 phases is its own PR via `/pr` with a self-contained, reviewable scope (wiring / config / multi-map).
- **Shadow main branches**: each phase branches from main, ships a PR, merges back — no long-lived parallel branch.
- **Building the engine before shipping value**: a compose generator is explicitly deferred to M4; M3 hand-writes 2 anchored services. Each phase leaves the single server bootable, so value isn't gated behind the full cluster.
- **Hotfix that isn't**: N/A — this is planned milestone work, not a hotfix.
- **Abandoned branches**: 3 phases, each merged on PASS before the next starts; no branch left dangling.
- **Flag graveyards**: no new feature flags introduced (the existing `ENABLE_ASAAPI` per-server kill-switch is reused, not added).

## Future Requirements / Revisit

Durable punt-list (per REF-risk-engine: recorded MEDIUM residuals and named deferrals land here with
their trigger, never as a checkbox that evaporates at session end).

- **Genesis Part 1 custom supply-crate loot (Beacon-gap deferral).**
  - **WHAT:** custom crate tuning for supply-crate classes **exclusive** to Genesis Part 1. (Genesis
    crates that reuse standard/shared beacon classes already present in `config/Game.ini` are already
    custom-tuned — loot overrides are class-keyed and global per `loot-crates.md` Locked Rule 1 — so
    only Genesis-exclusive classes are affected.)
  - **WHY deferred:** the local Beacon snapshot (`docs/internal/reference/beacon-asa/`, dated
    2026-06-21) has **zero** Genesis-Part-1 `loot_containers.tsv` rows — Beacon (a third-party
    community DB) has not yet ingested the same-day release. `tools/gen-loot.ts` resolves every class
    string from that snapshot, and `.claude/rules/documentation.md` forbids guessing class strings (a
    wrong/guessed crate class is a silent no-op — WORSE than transparent vanilla, and it would look
    configured while doing nothing). So hand-authoring interim Genesis-exclusive tables is rejected on
    the project's own standards; the durable fix is the real data landing in Beacon.
  - **COST to fix later:** ~minutes, no structural work. Re-pull the Beacon snapshot
    (`beacon-asa/README.md` "Re-pulling"), then `cd tools && bun run gen-loot.ts --write` (it reads
    the snapshot, so the new Genesis rows flow through automatically) → commit `config/Game.ini` →
    restart the cluster.
  - **TRIGGER:** the Beacon snapshot refresh adds Genesis Part 1 rows (a `Genesis_WP` row in
    `maps.tsv` and Genesis-P1 rows in `loot_containers.tsv`).
  - **Risk-engine record:** prob **B (Likely)** × sev **III (Marginal)** → initial **MEDIUM**; no B1/B2
    control available (the data genuinely does not exist; documenting the state is a B3 human-vigilance
    control = 0 axis-shift, gate-only), so residual stays **MEDIUM — recorded, no signature**. Live
    exposure between now and the trigger is closed by the cheap in-scope mitigation (README + Phase 3
    AC document the vanilla-exclusive-crate state as a known limitation).

- **Genesis Part 1 cross-ARK transfer compatibility — RESOLVED at plan time (no longer a deferral).**
  Originally raised as a contingency (Genesis might not support transfer at all → no fallback partner
  on a 2-map set). **Web-confirmed 2026-07-05 (conductor):** Genesis has no obelisks but DOES support
  bidirectional transfer via Mission Terminals (~85,63 Bog) + Tek Transmitters. Now a residual-**L**
  Risks-table row (was M) verified in-plan by the Phase 3 step-7 terminal test — no post-plan trigger
  remains, so it is closed out here rather than carried as a punt.

- **Dupe-on-crash mid-transfer (accepted engine-behavior residual).**
  - **WHAT:** ASA can duplicate a dino/item if a server crashes during the upload/download window — an
    engine behavior, not an M3 code path.
  - **WHY deferred:** out of M3's control (WildCard engine); low probability (crash inside the narrow
    transfer window); mitigated operationally by `SAVE_ON_STOP` + clean shutdowns + a documented ADR
    caveat. No money/irreversible floor fires (in-game items, admin-cleanable, "not money").
  - **COST to fix later:** if observed, add transfer-window safeguards / more frequent autosaves — ~1
    session; largely bounded by what the engine exposes.
  - **TRIGGER:** dupes observed in practice, or ASA patches the transfer-crash behavior.
  - **Risk-engine record:** prob **D** × sev **II** → **MEDIUM** (recorded); no score-moving control
    available (operational mitigation is B3, 0).

- **Shared read-only game-INSTALL volume (M4 optimization, pre-existing).** Per Decision Ledger #13:
  each map gets its own full ~13 GB game volume in M3; the shared read-only install is deferred to M4.
  **TRIGGER:** disk pressure or >4 maps.
