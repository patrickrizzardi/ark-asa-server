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
created: 2026-06-22
last_updated: 2026-06-22
plan_base: main
depends_on: [m2-shared-economy-store]
---

# Plan: M3 — Cluster (one economy + one config across maps)

Created: 2026-06-22
Status: pending_approval

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
- Single `the-island` service in `docker-compose.yml` (hardcoded ports 7777/udp + 27020/tcp),
  one `ark-game` volume, one shared `mariadb` service, host-bound `./config` + `./plugins-config`.
- `entrypoint.sh` builds the launch query string at line 461 — **no `-clusterid` / no
  `-ClusterDirOverride` today** (single server never needed them).
- The engine reads its INIs via a symlink: `ShooterGame/Saved/Config/WindowsServer` →
  `/home/container/config` (the host bind `./config`) — entrypoint.sh:425-428.
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
1. 3 map servers (`TheIsland_WP`, `TheCenter_WP`, `Aberration_WP`) boot together on dell, each
   advertising for join on its own port.
2. A player can **transfer** a character (and a dino + an item) from one map to another via the
   in-game obelisk/transmitter "Travel to another ARK" flow — proving `-clusterid` +
   `-ClusterDirOverride` + the shared cluster volume work.
3. Points are **shared**: `SetPoints` on one server's RCON is visible on another server (same
   MariaDB) — confirms the M2 economy spans the cluster.
4. Config is **consistent** across all 3 maps via ONE uniform model — every config is a fresh
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
  Transmitter / drops "upload" → "Travel to another ARK" → "download" on the destination map.
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
model), all N would `cp` + `jq`-inject the SAME file at once — the `cp` (entrypoint.sh:308) is not
atomic, so a server can read a half-written file mid-copy → `jq` parse error → loud boot failure.
Per-server copies eliminate every cross-server write. The repo canonicals are mounted read-only
via the `./config` bind (shared, never written at runtime → safe to share); only the per-server
*copies* are writable, and they live on each map's own volume.

**Consequence**: the shared `./plugins-config` host bind is **removed** — its only purpose was the
edit-on-host loop, now replaced by deploy-from-repo (edit `config/*.json` → push → restart).
Permissions flips from edit-on-host (seed-if-absent) to deploy-from-repo; safe because live
permission-group data lives in the shared MariaDB, not in `config.json` (Patrick's call).

The per-server identity that genuinely differs (map name, game port, RCON port, SessionName,
the shared clusterid) is **already env/launch-arg-driven** (entrypoint.sh:461) and does NOT live
in the shared canonicals — that's what makes the read-only `./config` bind safe to share.

**Multi-server in compose**: Docker Compose has no native loop. For 3 services the right tool is
YAML anchors (`&ark-common` / `<<: *ark-common`) to share the bulk of each service definition and
override only map/ports/volumes/container_name. A compose generator is explicitly **out of scope**
(that's M4 ops-tooling territory — building it now is "build the engine before shipping value").

## Decision Ledger

| # | Decision / claim | Class | Citation / recorded answer |
|---|---|---|---|
| 1 | Launch string has no `-clusterid`/`-ClusterDirOverride` today; both must be added | verified | `entrypoint.sh:461` (query string) + `:464-466` (flags) — neither token present |
| 2 | Engine reads INIs via `WindowsServer` symlink → host `./config` bind | verified | `entrypoint.sh:425-428` (`ln -sfn /home/container/config "$config_link"`) |
| 3 | `Game.ini` is never rewritten by the server (safe to share read-only) | verified | state.md loot-deploy note: dell `git status` clean post-boot; Game.ini retains comments |
| 4 | `GameUserSettings.ini` IS rewritten by the server on shutdown (cannot be a shared writable file) | verified | state.md loot/shop notes ("ARK rewrites GameUserSettings.ini & nukes comments"); `;METADATA=` header at config/GameUserSettings.ini:1 |
| 5 | ArkShop `config.json` already deploys from a repo seed each boot (deploy-from-repo pattern) | verified | `entrypoint.sh:307-309` (`cp "${shop_seed}" "${host_dir}/config.json"`) |
| 5b | Permissions `config.json` is currently seed-if-absent from the image default (today's behavior, being changed) | verified | `entrypoint.sh:310-312` (`[[ ! -f host config ]] && cp image-default`) |
| 5c | Concurrent-boot race: N servers sharing ONE plugin-config file would `cp`(non-atomic)+`jq` it simultaneously → torn read → loud boot fail. `docker compose up` starts services in parallel | verified | `entrypoint.sh:308` (plain `cp`, not atomic) + Compose default parallel start (services share no inter-dependency) |
| 5d | UNIFIED config model = repo canonical → fresh per-server copy each boot, repo wins, for ALL 4 configs (Game.ini, GUS, ArkShop, Permissions) | needs-Patrick | Patrick: "do both as a fresh copy on boot… less conditionals, same result" + chose "Deploy-from-repo (full uniformity)" for Permissions |
| 5e | Permissions live group data lives in the shared MariaDB (not config.json) → flipping Permissions to deploy-from-repo is safe | design | ArkShop Permissions plugin stores groups in its DB tables (shared `mariadb` from M2); config.json is bootstrap only |
| 6 | Transfer flags already permit transfers; must stay uniform cluster-wide | verified | `config/GameUserSettings.ini` `PreventUpload/Download*=false`, `Tribute*ExpirationSeconds=3600` |
| 7 | Single `the-island` service, hardcoded host ports 7777/udp + 27020/tcp | verified | `docker-compose.yml:50-61` |
| 8 | MariaDB economy is already shareable; a 2nd server at `mariadb:3306` shares points with no new work | verified | `docker-compose.yml:26-48` (mariadb svc) + `:79-83` (server → `mariadb:3306`) |
| 9 | Aberration map class string = `Aberration_WP` | verified | `docs/internal/reference/beacon-asa/maps.tsv` row "Aberration\tAberration_WP" |
| 10 | Maps for M3 cluster = Island + The Center + Aberration (3 maps) | needs-Patrick | Patrick: "add aberration as well" on the recommended Island+Center base → 3 maps |
| 11 | GUS config model = deploy-from-repo seed (canonical in repo → entrypoint copies to per-server writable path + injects SessionName) | needs-Patrick | Patrick selected "Deploy-from-repo seed" |
| 12 | M3 gate validated by running the full cluster on dell (all maps up simultaneously) | needs-Patrick | Patrick: "yyea you can test 2 on dell" (confirmed multi-server local test) |
| 13 | Per-server game volumes (each map gets its own `ark-game-<map>` volume; ~13GB install each) | design (named tradeoff) | See Risks + Phase 1; shared-install optimization deferred to M4 with trigger |
| 14 | clusterid stored as a secret in `.env` (`ARK_CLUSTER_ID`), not committed | design | Mirrors `ARK_ADMIN_PASSWORD` / DB secrets handling (`docker-compose.yml:66`) |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| GUS deploy-from-repo flip discards an in-game admin's runtime GUS edits | Med | Low | Documented + intended (repo is source of truth, same as shop). README note: edit `config/GameUserSettings.ini` → push → restart. The in-game GUS edit path was never the supported loop. |
| Shared cluster dir wrong → players see transfer list but downloads silently fail | Med | High (transfers broken, no error) | Single named volume mounted at the SAME path in every service; verified by an actual cross-map transfer in Phase 3 (not just "advertises"). The silent-fail mode is exactly why the AC requires a real transfer, not a parse check. |
| clusterid mismatch across services → no cross-server visibility | Low | High | One `ARK_CLUSTER_ID` in `.env` consumed by every service via the shared YAML anchor; never per-service. |
| 3× ASA on dell (8 cores / 64 GB) — CPU contention | Med | Med | RAM fits (~30 GB of 64). 8 cores across 3 servers is tight but fine for a no-player transfer test. Real player load is a VPS concern (out of scope). |
| Per-server first boot re-downloads ~13 GB × 3 (slow first cluster boot) | High | Low | One-time cost; subsequent boots are fast (skip-validate). Disk is not a stated constraint (Patrick cares about RAM/CPU). Shared read-only install is a named M4 optimization, not M3. |
| Aberration's different loot system / radiation map quirks break loot or boot | Low | Med | `gen-loot`/`gen-shop` already resolve all 8 maps incl. Aberration zone-crates; Aberration boot-tested as part of Phase 3. If a map-specific class fails, it's a silent no-op (vanilla loot), caught at the in-game check. |
| Port collision on dell (3 game + 3 RCON ports) | Low | Med | Distinct host ports per service (7777/7779/7781 udp; 27020/27021/27022 tcp); documented in compose + `.env` examples. |
| Changing the `WindowsServer` symlink model breaks the M1/M2 single-server config loop | Med | High | Phase 2 keeps single-server behavior working (the entrypoint logic is map-count-agnostic — one server just reads the same shared Game.ini + seeds its own GUS); regression-checked by booting `the-island` alone before the multi-service compose lands. |
| ASA upload/download can DUPE dinos/items if a server crashes mid-transfer | Low | High (economy/items) | Out of M3's control (engine behavior); mitigated operationally by `SAVE_ON_STOP` + clean shutdowns. Documented as a known ASA caveat in the ADR; not a code fix. |

## Questions

Open assumption to confirm at approval (not blocking the draft):
- **Map set** = Island + The Center + Aberration (Decision Ledger #10). If "add aberration as
  well" meant a different base pair (e.g. Island + Scorched + Aberration), say so and I'll swap
  the map name + ports in Phase 3 — it's a one-line-per-map change.

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
1. dell: boot `the-island` alone (Phase 2 regression) → confirm M1/M2 single-server loop intact.
2. dell: boot the full 3-map cluster (Phase 3) → confirm advertise + transfer + shared points + config consistency.
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
**Objective**: After this phase, the existing `the-island` service launches with
`-clusterid=$ARK_CLUSTER_ID -ClusterDirOverride=<shared-path>`, a named `ark-cluster` volume is
mounted at that path, and all per-server identity (map, ports, session, clusterid) is env-driven.
The single server still boots and advertises exactly as before — the cluster args are inert with
one server but prove the wiring.
**Why this phase exists**: The transfer mechanism is the load-bearing unknown. Wiring + proving it
on the existing single server (which still boots) de-risks before multiplying services. It also
keeps the diff reviewable — cluster args + volume, no compose explosion yet.
**Current-state anchors**:
- `entrypoint.sh:461` — launch query string (where map?listen?... is built; cluster args go on the `-flags` side at :464)
- `entrypoint.sh:464-466` — `-flags` construction (`-log`, BattlEye, `-mods`); append cluster flags here
- `entrypoint.sh:12-16` — env default block (`SERVER_PORT`, `RCON_PORT`); add `ARK_CLUSTER_ID`, `CLUSTER_DIR`
- `docker-compose.yml:84-91` — `the-island` volumes (where `ark-cluster` mount is added)
- `docker-compose.yml:99-103` — `volumes:` block (declare `ark-cluster`)
- `docker-compose.yml:62-83` — `the-island` environment (add `ARK_CLUSTER_ID`)
- `.claude/rules/build-time-vs-runtime.md` — table to amend (cluster-dir row)
**Files (expected scope)**: `entrypoint.sh`, `docker-compose.yml`, `.env.test.example`,
`.env.prod.example`, `.claude/rules/build-time-vs-runtime.md`, `docs/internal/decisions/0003-cluster-architecture.md`
**Scope Boundary**:
- **In scope (this phase delivers)**: "ASA native cluster transfer (characters/dinos/items between maps)" (ledger); "Shared cluster save directory volume" (ledger).
- **Explicitly NOT delivered (deferred to later milestone)**: none (all M3 ledger rows land within M3's phases; nothing deferred to M4+).
- **Out of scope (NOT a deferral — never this phase's job)**: the multi-map compose services (Phase 3 — keep the diff to one service + wiring); the GUS/config-sharing rework (Phase 2 — separate concern); a compose generator (M4 ops-tooling — building it now is build-the-engine).
**Deviation rule**: Executor MAY touch adjacent lines if the change serves the wiring (e.g. a comment fix near the launch string). Document each deviation with a one-line reason. Unrelated refactors → STOP, split.
**Steps**:
1. In `entrypoint.sh:12-16` env block, add `: "${ARK_CLUSTER_ID:=}"` and
   `: "${CLUSTER_DIR:=${ARK_DIR}/ShooterGame/Saved/clusters}"` (default keeps single-server
   behavior identical when no cluster dir is mounted).
2. In `entrypoint.sh` `-flags` construction (~:464-466), append cluster args **only when
   `ARK_CLUSTER_ID` is non-empty**: `[[ -n "$ARK_CLUSTER_ID" ]] && flags="${flags}
   -clusterid=${ARK_CLUSTER_ID} -ClusterDirOverride=${CLUSTER_DIR}"`. (Empty clusterid → no
   cluster args → byte-for-byte M2 launch. This preserves the vanilla/single-server invariant.)
3. `mkdir -p "${CLUSTER_DIR}"` in the boot prep (idempotent, same style as existing dir creation
   ~entrypoint.sh:423-428) so the override path exists before launch.
4. In `docker-compose.yml`, declare a named `ark-cluster` volume (:99-103 block) and mount it into
   `the-island` at `${CLUSTER_DIR}` (default `/home/container/arkserver/ShooterGame/Saved/clusters`).
   Add `ARK_CLUSTER_ID: ${ARK_CLUSTER_ID:?set ARK_CLUSTER_ID in your env file}` to the env block.
5. Add `ARK_CLUSTER_ID=<example-non-obvious-id>` + a one-line comment ("treat like a password,
   identical on every cluster server") to both `.env.test.example` and `.env.prod.example`.
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
- [ ] `the-island` boots on dell and advertises for join with `ARK_CLUSTER_ID` set (cluster args present in the launch log line)
  - Evidence: (filled at phase completion)
- [ ] With `ARK_CLUSTER_ID` empty, the launch string is byte-for-byte identical to the current M2 launch (no `-clusterid`/`-ClusterDirOverride`)
  - Evidence: (filled at phase completion)
- [ ] `ark-cluster` named volume is declared and mounted at `${CLUSTER_DIR}`; the dir exists in-container after boot
  - Evidence: (filled at phase completion)
- [ ] ADR `0003-cluster-architecture.md` exists and documents the cluster model + per-server-volume tradeoff + rejected alternatives (doc-type: adr — must carry rejected alternatives + cost-to-reverse)
  - Evidence: (filled at phase completion)
- [ ] `build-time-vs-runtime.md` has the cluster-dir row
  - Evidence: (filled at phase completion)
**Quality gate**:
- [ ] Cluster args only appended when clusterid is non-empty (single-server invariant)
- [ ] `mkdir -p` cluster dir is idempotent (safe on every boot)
- [ ] No secret (clusterid) committed — only the `.env.*.example` placeholders
- [ ] Follows existing entrypoint env-default + flags-construction patterns
**Verification**: On dell, `docker compose up` with `ARK_CLUSTER_ID` set → grep the launch log for
`-clusterid=` and `-ClusterDirOverride=`; `docker compose exec the-island ls ${CLUSTER_DIR}` shows
the dir. Then unset `ARK_CLUSTER_ID`, reboot, confirm the launch line has no cluster args.

**Phase Review Gates**:
- [ ] code-reviewer: <verdict + ISO timestamp>
- [ ] rules-compliance-reviewer: <verdict + ISO timestamp>
- [ ] plan-adherence-verifier: <verdict + ISO timestamp>
- [ ] acceptance-verifier: <verdict + ISO timestamp>
- [ ] design-compliance-reviewer: <verdict + ISO timestamp>
- [ ] Committed: <commit SHA>

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
+ the NEW `config/permissions.config.json` (+ injected `Mysql`). The single `the-island` server
boots and behaves exactly as M2 (regression-safe).
**Why this phase exists**: This is the precondition for N servers sharing config without
corruption. Two problems with today's model: (1) `WindowsServer` is a whole-dir symlink →
`/home/container/config` (entrypoint.sh:427-428), so the server-rewritten GUS lives in the shared
bind — N servers clobber it on shutdown. (2) Plugin configs deploy to ONE shared `./plugins-config`
bind via non-atomic `cp` (entrypoint.sh:308) — N servers booting in parallel race a torn read →
loud boot fail (Decision Ledger #5c). The fix for BOTH is the same: fresh per-server copies. Tagged
**complex** because it reworks the load-bearing `WindowsServer` symlink + the plugin-config deploy
path that M1/M2 depend on. **The race-safety is structural**: once every config is a per-server file
on each map's own volume, the files are physically distinct and CANNOT contend regardless of timing.
This phase establishes the structure on one server; Phase 3 proves it under simultaneous boot +
shutdown of N.
**Current-state anchors**:
- `entrypoint.sh:423-428` — config dir creation + `WindowsServer` **whole-dir** symlink → `/home/container/config` (replace `ln -sfn /home/container/config "$config_link"`)
- `entrypoint.sh:85-144` — `deploy_plugins()` stash/restore of plugin config.json across the /opt→Win64 sync (:92-101 stash, :132-144 restore) — becomes redundant for repo-deployed plugins (setup_plugin_configs overwrites from repo anyway); confirm it's not broken, simplify if clean
- `entrypoint.sh:286-319` — `setup_plugin_configs()`: the `cp` seed (:308), the seed-if-absent branch (:310-312), the file-symlink to the shared bind (:316), and `host_root=/home/container/plugins-config` (:287) — all reworked to per-server deploy-from-repo
- `entrypoint.sh:322-356` — `_inject_mysql_block()`: **has symlink-resolution logic** (`dest="$(readlink -f "${cfg}")"` at :341, comment :335-337, `mv "${tmp}" "${dest}"` at :356) that BREAKS when the target is now a real file. Must become a plain atomic `mv "${tmp}" "${cfg}"` onto the real per-server config; drop the `dest`/readlink resolution; update the comment.
- `entrypoint.sh:359-410` — `inject_plugin_db_config()` (the CALLER): hardcoded paths `${win64}/ArkApi/Plugins/{ArkShop,Permissions}/config.json` (:392,:405) are already per-server-correct, BUT its comments (:369-375) describe "host-bound path via the symlink"/"plugins-config host bind" — STALE after the rework, must be updated
- `docker-compose.yml:90` — the `./plugins-config:/home/container/plugins-config` bind to remove
- `.gitignore:7` — `plugins-config/**` (orphaned after the bind removal — remove) + the tracked `plugins-config/.gitkeep`
- `docs/internal/design/economy/shop.md:253-270` — §11 "Build & deploy" describes the OLD deploy model (copy → `plugins-config/ArkShop/config.json` host bind) — stale, must update to per-server deploy
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
1. Replace the whole-dir symlink at entrypoint.sh:427-428. Make `WindowsServer` a **real
   directory** on the per-server game volume: `mkdir -p
   "${ARK_DIR}/ShooterGame/Saved/Config/WindowsServer"` (no longer `ln -sfn … /home/container/config`).
   **Note for the executor**: the deep-bind warning at `docker-compose.yml:86-89` is about a Docker
   *bind-mount* root-creating intermediate dirs and blocking the non-root user. It does NOT apply
   here — `WindowsServer` becomes a real dir on the `ark-game` volume the container user already
   owns. Do not revert to the whole-dir symlink out of fear of that comment.
2. **Copy** (not symlink — Patrick's call for uniformity + defense-in-depth) `Game.ini` into it
   each boot: `cp /home/container/config/Game.ini "${WindowsServer}/Game.ini"`. A per-server copy
   absorbs any defensive engine write without touching the shared canonical.
3. Add a `seed_gus()` step (mirror the :308 `cp` idiom): each boot, copy
   `/home/container/config/GameUserSettings.ini` → `${WindowsServer}/GameUserSettings.ini` (real
   writable file), then inject `SessionName=${SESSION_NAME}`. Injection must be **line-oriented**:
   if a `SessionName=` line exists under `[SessionSettings]`, replace its value; if the key is
   absent, append it under `[SessionSettings]`; if the section itself is absent, append section +
   key. (Seed comes from the canonical each boot — comments intact — so inject always operates on a
   known-good file.)
4. Capture the image-default Permissions config into a NEW tracked repo seed
   `config/permissions.config.json`: grab `Win64/ArkApi/Plugins/Permissions/config.json` from the
   built image (or dell's deployed copy), strip any `Mysql` secret block (the entrypoint injects it,
   same as the ArkShop seed), commit it secret-free.
5. Rework `setup_plugin_configs()` to **per-server deploy-from-repo for BOTH plugins**: deploy
   `config/arkshop.config.json` → the per-server ArkShop plugin dir's `config.json`, and
   `config/permissions.config.json` → the per-server Permissions plugin dir's `config.json` — each a
   real file written directly into the plugin dir on the per-server game volume (NOT a symlink to a
   shared bind). Drop the seed-if-absent branch (:310-312) and the shared-bind file-symlink (:316),
   and the now-unused `host_root=/home/container/plugins-config` (:287).
6. Update the mysql-injection path (BOTH functions — this is the silent-DB-less-boot risk):
   - `_inject_mysql_block()` (:322-356): remove the symlink-resolution logic (`dest="$(readlink -f
     "${cfg}")"` at :341 + the comment :335-337 + `mv "${tmp}" "${dest}"` at :356). The plugin config
     is now a REAL file, so this becomes a plain atomic `mv "${tmp}" "${cfg}"`. Update the comment
     (no more symlink).
   - `inject_plugin_db_config()` (:359-410): the hardcoded paths (:392,:405) already point at the
     per-server plugin-dir config.json — KEEP them. Update the stale comments (:369-375) that
     describe "host-bound path via the symlink" / "plugins-config host bind" → now a real per-server
     file. The `has("Mysql")` guard for Permissions (:406) still applies (the new Permissions seed
     must carry a `Mysql` block for it to be injected — ensure the captured seed has one, or
     Permissions connects DB-less; verify at boot).
7. `deploy_plugins()` stash/restore (:92-101 + :132-144): confirm it's not broken by the model
   change (it stashes/restores whatever config.json exists across the /opt→Win64 sync; setup then
   overwrites from the repo seed anyway, so the stash is now redundant for ArkShop/Permissions). If
   it's cleanly removable without affecting a non-repo-deployed plugin, simplify; otherwise leave it
   (redundant but harmless) and note why in the PR.
8. Remove the `./plugins-config:/home/container/plugins-config` bind from `docker-compose.yml:90`,
   the `plugins-config/**` line from `.gitignore:7`, and **`git rm`** the tracked
   `plugins-config/.gitkeep` (it's tracked, not just gitignored — a plain `rm -rf` would leave it in
   the index) then delete the now-empty `plugins-config/` dir (no longer used — plugin configs now
   deploy from the `./config` repo seeds to per-server plugin dirs). Grep-confirm nothing else
   references `plugins-config` before removing.
9. Update `docs/internal/design/economy/shop.md` §11 (Build & deploy, :253-270): the deploy model
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
12. Regression-guard: boot `the-island` ALONE on dell, confirm loot (Game.ini) + shop catalog +
    Permissions + GUS tuning all apply and the server advertises (proves the rework didn't break
    single-server); confirm `WindowsServer` is a real dir with copied `Game.ini` + writable `GUS`,
    the plugin dirs hold real per-server config.json (not symlinks), and **`jq .Mysql` on each
    plugin config shows the injected DB block** (proves the inject-path rework didn't silently
    DB-less the plugins).
**Acceptance criteria**:
- [ ] `the-island` boots alone on dell with loot (Game.ini), shop catalog, Permissions, and GUS tuning all applied (single-server regression intact)
  - Evidence: (filled at phase completion)
- [ ] `${WindowsServer}` is a real directory (NOT a symlink); both `Game.ini` and `GameUserSettings.ini` inside it are real regular files (`stat`/`readlink` evidence), copied from `config/` each boot
  - Evidence: (filled at phase completion)
- [ ] `GameUserSettings.ini` `SessionName` matches `${SESSION_NAME}` (injected, not the canonical's value)
  - Evidence: (filled at phase completion)
- [ ] ArkShop + Permissions `config.json` are real per-server files in their plugin dirs (NOT symlinks); `config/permissions.config.json` exists as a secret-free tracked seed
  - Evidence: (filled at phase completion)
- [ ] **DB inject still works on the real-file path**: `jq .Mysql` on the ArkShop config AND the Permissions config shows the injected host/user/db — proves `_inject_mysql_block`'s symlink-resolution removal didn't break the write (the silent-DB-less-boot risk)
  - Evidence: (filled at phase completion)
- [ ] **The committed `config/permissions.config.json` seed contains a `Mysql` key** so the `has("Mysql")` guard at entrypoint.sh:406 fires — otherwise Permissions silently boots DB-less and the inject-check above is vacuously skipped
  - Evidence: (filled at phase completion)
- [ ] `./plugins-config` bind removed from `docker-compose.yml`, `plugins-config/**` removed from `.gitignore`, orphaned `plugins-config/` dir deleted; grep confirms no remaining `plugins-config` reference in entrypoint/compose
  - Evidence: (filled at phase completion)
- [ ] `docs/internal/design/economy/shop.md` §11 updated to the per-server deploy model (no stale `plugins-config` host-bind description)
  - Evidence: (filled at phase completion)
- [ ] ADR `0004-shared-config-model.md` exists with the unified model + the two races it solves + rejected alternatives (doc-type: adr); registered `[locked]`
  - Evidence: (filled at phase completion)
**Quality gate**:
- [ ] Every config copy/seed is idempotent (safe every boot)
- [ ] No shared writable config file remains (no whole-dir `WindowsServer` symlink; no plugin-config symlink to a shared bind)
- [ ] `_inject_mysql_block` no longer resolves a symlink (operates on a real file via atomic `mv`); its comment matches
- [ ] Dirty-volume transition is clean: booting Phase 2 on a volume that still holds the OLD symlinked `config.json` (from a pre-Phase-2 boot) correctly replaces it with a real file (not a dangling symlink) — verify on dell's existing `ark-game` volume, not just a fresh one
- [ ] `inject_plugin_db_config` comments updated (no "host bind"/"symlink" language)
- [ ] SessionName injection handles the `[SessionSettings]` block whether present or absent
- [ ] Permissions seed committed is secret-free (Mysql injected at runtime, like ArkShop); seed carries a `Mysql` block so the inject guard fires
- [ ] `ENABLE_ASAAPI=0` vanilla path still copies Game.ini + seeds GUS (plugins skipped when disabled — confirm the vanilla path is unaffected)
- [ ] No stale doc left: shop.md §11 + any README plugins-config mention reflect the new model
**Verification**: dell single-server boot → `docker compose exec the-island sh -c 'ls -la
<WindowsServer> && ls -la <ArkShop plugin dir>/config.json <Permissions plugin dir>/config.json'`
shows real files (no symlinks); `grep SessionName <WindowsServer>/GameUserSettings.ini` shows the
env value; `jq .Mysql <plugin>/config.json` shows the injected block; `git status` shows
`config/permissions.config.json` tracked + secret-free and `plugins-config/` gone;
`grep -rn plugins-config entrypoint.sh docker-compose.yml` returns nothing.

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
**PR scope**: Replicate the parameterized server into 3 map services (Island, Center, Aberration)
via YAML anchors, sharing mariadb + ark-cluster + read-only config, with distinct ports + per-map
game volumes. Deploy to dell, validate the full cluster end-to-end.
**Branch**: `feat/m3-multi-map-cluster`
**Flag**: N/A
**Est. lines**: ~160 (mostly compose)
**Executor tier**: standard
**Ships via**: `/pr`
**Objective**: After this phase, `docker compose up` on dell brings up MariaDB + 3 ASA map servers
sharing one economy + one cluster transfer dir + one canonical config. A player can transfer
between maps, points are shared, and loot/shop are identical across maps.
**Why this phase exists**: This is the milestone payoff — the actual multi-map cluster. It comes
last because it needs Phase 1's wiring and Phase 2's shareable config as the unit to replicate.
**Current-state anchors**:
- `docker-compose.yml:50-97` — the single `the-island` service (the template to anchor + replicate)
- `docker-compose.yml:99-103` — volumes block (add per-map game volumes)
- `docs/internal/reference/beacon-asa/maps.tsv` — map class strings (`TheIsland_WP`, `TheCenter_WP`, `Aberration_WP`)
- `README.md` — add the cluster section
**Files (expected scope)**: `docker-compose.yml`, `.env.test.example`, `.env.prod.example`, `README.md`
**Scope Boundary**:
- **In scope (this phase delivers)**: "Multi-server (2+ maps) pointing at the shared MariaDB economy" (ledger); "Per-map game/config volumes + shared cluster volume layout" (ledger).
- **Explicitly NOT delivered (deferred to later milestone)**: shared read-only game-INSTALL volume (M4 optimization — each map gets a full game volume in M3, per Decision Ledger #13); ops CLI / backups (M4).
- **Out of scope (NOT a deferral — never this phase's job)**: a compose generator (M4); changing loot/shop content; VPS provisioning (operator owns prod per roadmap Out of Scope).
**Deviation rule**: MAY adjust ports/volume names if a collision is found on dell. Document each.
Adding a 4th map or any generator → STOP, that's scope creep / M4.
**Steps**:
1. Refactor `the-island` into a YAML anchor `&ark-server` capturing the shared bulk (build/image,
   depends_on, the shared env block, the shared volume mounts — the read-only `./config` repo-seed
   bind + `ark-cluster`; NOTE the `./plugins-config` bind was removed in Phase 2 — do not re-add it,
   stop_grace, restart, logging).
2. Define 3 services using `<<: *ark-server`, each overriding: `container_name`, `SERVER_MAP`
   (`TheIsland_WP` / `TheCenter_WP` / `Aberration_WP`), `SESSION_NAME`, the published game port
   (7777 / 7779 / 7781 udp) + `SERVER_PORT`, the published RCON port (27020 / 27021 / 27022 tcp) +
   `RCON_PORT`, and its own per-map game volume (`ark-game-island` / `ark-game-center` /
   `ark-game-aberration`). All three inherit the SAME `ARK_CLUSTER_ID` + `ark-cluster` mount + DB env.
3. Declare the 3 per-map game volumes + keep the shared `ark-cluster`, `ark-db` in the volumes block.
4. Update `.env.test.example` / `.env.prod.example` with the per-map port variables + the single
   `ARK_CLUSTER_ID` + a comment on the 3-map layout.
5. Add a README "Cluster" section: the edit→push→restart config loop (one canonical config, all
   maps), per-map ports, the clusterid secret, how a player transfers between maps. Also scrub any
   stale M2 README mention of the `./plugins-config` edit-on-host loop (removed in Phase 2 — config
   is now edit-`config/`-in-repo → restart).
6. Deploy to dell (`git pull` → `docker compose up -d --build`), boot all 3, run the validation
   below.
**Acceptance criteria**:
- [ ] All 3 map servers boot on dell and each advertises for join on its own port (Island 7777 / Center 7779 / Aberration 7781)
  - Evidence: (filled at phase completion — dell logs per service)
- [ ] Cross-map transfer works with a CHECKABLE artifact, not just eyeballing: after a player uploads a character (+ a dino + an item) on map A, a cluster transfer file appears under `${CLUSTER_DIR}/${ARK_CLUSTER_ID}/` on the shared `ark-cluster` volume (`docker compose exec the-center ls -la ${CLUSTER_DIR}/${ARK_CLUSTER_ID}/` shows it from a DIFFERENT service — proving the volume is genuinely shared, not per-container) — Patrick in-game upload + Claude verifies the file
  - Evidence: (filled at phase completion)
- [ ] Transfer is a MOVE not a DUPE: after downloading on map B, the character/dino/item arrives on B with correct identity AND is gone from A (guards the silent-dupe failure mode flagged in Risks) — Patrick in-game
  - Evidence: (filled at phase completion)
- [ ] Concurrent-shutdown GUS integrity: `docker compose stop` all 3 servers together, then `docker compose up` — each server's `GameUserSettings.ini` retains its OWN `SessionName` and identical tuning (proves per-server volumes make GUS structurally clobber-proof, the Phase 2 invariant under N servers)
  - Evidence: (filled at phase completion)
- [ ] Points are shared: `SetPoints <eosid> <n>` via one server's RCON, then `GetPoints <eosid>` via a DIFFERENT server's RCON returns the same value (same MariaDB)
  - Evidence: (filled at phase completion)
- [ ] Config consistency: pop the same-tier loot crate on all 3 maps → identical contents; `/shop` catalog identical across maps (one canonical source); editing the repo config once + restart changes all maps
  - Evidence: (filled at phase completion)
- [ ] README cluster section documents the loop, ports, clusterid, and transfer flow (doc-type: how-to + reference)
  - Evidence: (filled at phase completion)
- [ ] `ENABLE_ASAAPI=0` on a service still produces the vanilla rollback for that map
  - Evidence: (filled at phase completion)
**Quality gate**:
- [ ] YAML anchor shares the bulk; per-service overrides are only map/ports/session/volume/container_name
- [ ] All 3 services use the SAME `ARK_CLUSTER_ID` + the SAME `ark-cluster` mount path
- [ ] No port collisions (3 distinct game + 3 distinct RCON ports), documented in `.env.*.example`
- [ ] Each map has its own game volume (saves isolated); cluster + DB volumes shared
- [ ] No secret committed (clusterid stays in `.env`)
- [ ] clusterid actually gates (optional adversarial check): temporarily set one service's `ARK_CLUSTER_ID` to a different value → it does NOT see the others' transfers → revert. Proves the clusterid is the gate, not just the shared dir.
**Verification**: dell `docker compose up -d` → `docker compose logs` shows 3× "successfully
started" + advertising; in-game obelisk transfer Island→Center→Aberration; `SetPoints` on Island
RCON visible via `GetPoints` on Center RCON; pop a loot crate on each map to confirm identical
tables; toggle `ENABLE_ASAAPI=0` on one service → vanilla boot.

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
- [ ] Performance: N/A (infra) — dell capacity checked (3× ASA ≈ 30 GB of 64)
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
- **Building the engine before shipping value**: a compose generator is explicitly deferred to M4; M3 hand-writes 3 anchored services. Each phase leaves the single server bootable, so value isn't gated behind the full cluster.
- **Hotfix that isn't**: N/A — this is planned milestone work, not a hotfix.
- **Abandoned branches**: 3 phases, each merged on PASS before the next starts; no branch left dangling.
- **Flag graveyards**: no new feature flags introduced (the existing `ENABLE_ASAAPI` per-server kill-switch is reused, not added).
