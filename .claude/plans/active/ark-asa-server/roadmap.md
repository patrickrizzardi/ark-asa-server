---
slug: ark-asa-server
type: roadmap
owner: Patrick
status: active
created: 2026-06-20
last_updated: 2026-06-20
milestones:
  - m1-lean-image
  - m2-shared-economy-store
  - m3-cluster
  - m4-ops-tooling
---

# Roadmap: ARK ASA Self-Hosted Server

## Vision
A lean, self-hosted ARK: Survival Ascended server platform that does the thing managed hosts
(Nitrado) can't: a **shared economy across a multi-map cluster**. Players keep one points
balance and shop wherever they play. The whole stack is reproducible Docker — fast to boot,
controlled versions, edit-config-and-restart simplicity — so the operator spends time running a
community, not fighting a control panel.

## Why Now
M1 (lean fast-boot single-server image) is done and proven on bare-metal Linux. The exit-21
gremlin that blocked it turned out to be a missing `steamclient.so`, not the environment — so the
image is portable and the foundation is solid. The next differentiator (the shop/economy) is what
makes this worth self-hosting over a managed host, so it's the right next investment.

## Constraints
- **ArkShop ASA does not support MySQL 8.0.28+** — only MySQL ≤8.0.27 or *any* MariaDB. This
  forces **MariaDB** as the DB engine (locked decision below).
- **AsaApi + ArkShop are community plugins** — they can lag game patches or change behavior. The
  cluster depends on them, so versions must be a controlled, tested bump (pinned), never a surprise.
- **Single test box**: the `dell` server (bare-metal Ubuntu 22.04) is the dev/test environment,
  same as M1. Production deploy is the operator's own VPS.
- **Build-vs-runtime split** is a hard rule for this project (`.claude/rules/build-time-vs-runtime.md`):
  immutable/version-pinned → image; mutable/volume-backed/per-boot → entrypoint.

## Architectural Decisions Made
*(All confirmed with Patrick during M2 requirements gathering, 2026-06-20.)*

- **DB engine = MariaDB**: ArkShop refuses MySQL 8.0.28+; MariaDB is supported at any version, is
  the same SQL/wire-protocol/tooling, and is actively maintained. — Rejected: MySQL 8.0.27 pinned
  (frozen on an unpatched 2021 release for no upside); SQLite-only (defeats the shared-store goal).
- **Economy = ArkShop's native system, as-is**: ArkShop's points/shop/kits backed by a shared
  MariaDB *is* the shared-cluster economy. — Rejected (for now): a custom economy schema/layer.
  It's purely additive later — a future website/Discord/dashboard milestone connects to the SAME
  MariaDB and reads ArkShop's tables; nothing built in M2/M3 needs teardown. Building it now is
  "build the engine before shipping value."
- **Plugins baked into the image at pinned versions**: AsaApi + ArkShop + Permissions are built
  into the Docker image (like `steamclient.so` in M1) → faster boot, cluster-wide identical
  versions, operator chooses when to bump. — Rejected: drop-in volume / auto-latest (version
  drift + a bad upstream release silently bricks the cluster on restart). Named cost: updating a
  plugin requires a rebuild. Benefit: no surprise breakage.
- **Plugin/server CONFIG lives on the host volume (edit-on-host, like M1)**: ArkShop `config.json`,
  plugin configs, and `GameUserSettings.ini` are host files — edit, restart, done. Clean split:
  binaries in the image (fixed), config on the volume (mutable).
- **MariaDB is self-contained in the compose stack**: a service in the same `docker-compose`, so
  one `docker compose up` brings DB + server up together. In M3 the cluster servers all point at
  this one DB.
- **Secrets via `.env` (same as M1)**: DB user/root passwords join `ARK_ADMIN_PASSWORD` in the
  gitignored `.env`; the entrypoint passes them to MariaDB and writes them into ArkShop's config
  at boot. — Rejected: docker secrets (heavier, inconsistent with M1's loop).
- **Updates = pinned, rebuild-to-update**: AsaApi/ArkShop versions set in the Dockerfile; game
  updates stay on the M1 `UPDATE_ON_BOOT` toggle.

## Open Architectural Questions
- **ASA cluster transfer mechanism (blocks M3)**: how ASA shares character/dino/item transfer
  across map servers (`-clusterid`, `-ClusterDirOverride`, shared cluster save dir) needs research
  at M3 plan time — needs Patrick sign-off on the cluster layout (one host, N map containers,
  shared cluster dir + shared MariaDB). Not needed for M2.
- **Shared-config merge/override mechanism (blocks M3)**: INI files don't "point at one source"
  the way the DB does — so how to share one canonical `Game.ini`/`GameUserSettings.ini`/plugin
  config across servers while overriding the per-server keys (map, ports, `SessionName`) is an M3
  design decision. Candidates to research at M3 plan time: a shared read-only config volume +
  entrypoint applies per-server overrides from env; or a base-config + generated-overlay approach.
  M2 keeps config on a host volume specifically so this is additive. Not needed for M2.
- **ArkShop MariaDB connector specifics (resolve at M2 plan time)**: exact ArkShop config keys,
  whether ArkShop auto-creates its schema on first connect, and the MariaDB version that pairs
  cleanly with ArkShop's bundled MySQL client lib — research in the M2 execution plan.

## Milestones

### Milestone 1: Lean fast-boot single-server image — ✅ DONE (2026-06-20)
**Value delivered**: A reproducible ASA server that boots fast (skip-validate after first install),
runs the Windows binary on Linux via GE-Proton, and supports an edit-config→restart loop (~20s).
**Execution plan**: `m1-lean-image` (status: shipped — built before the folder-plan convention; its
record lives in `state.md` Active Decisions + the git history of `91cf0d4`/`f9f9923`/`29ee19d`).
**Depends on**: nothing.
**Rough scope**: Dockerfile on `parkervcp/steamcmd:proton`, non-root container user, runtime game
install onto a volume, `vm.max_map_count` sysctl service, prod/test env profiles, baked
`steamclient.so`. Verified booting + advertising on dell.
**Ordering Rationale**: Foundation — everything else runs inside this image. Deliberately left
incomplete as designed seams: no plugins (M2 capability "AsaApi loader baked + launched"), no DB
(M2 "self-contained MariaDB service"), no cluster (M3). Launches `ArkAscendedServer.exe`; M2 flips
that to `AsaApiLoader.exe`.

### Milestone 2: Shared economy store (AsaApi + ArkShop + MariaDB) — ✅ DONE (2026-06-21)
**Value delivered**: A single modded server with a working in-game shop and points economy backed
by a real shared database — the operator can sell items/dinos/commands and players earn points by
playtime. The "shared store" foundation is proven end-to-end on one server; M3 adds more maps.
**Execution plan**: `m2-shared-economy-store` (status: shipped)
**Depends on**: Milestone 1.
**Rough scope**: Bake AsaApi + ArkShop + Permissions into the image at pinned versions; install
VC++ 2019 redist into the Proton prefix; flip the launch to `AsaApiLoader.exe`; add a
self-contained MariaDB service to compose; configure ArkShop against MariaDB (shared store) with
config on the host volume; DB password via `.env`. Single map server (`TheIsland_WP`).
**Ordering Rationale**: The economy is the project's differentiator, so it comes before clustering.
Deliberately delivers a SINGLE-server shop on the shared DB and stops there — the multi-server /
cluster-transfer capabilities are designed seams owned by M3 (ledger rows "Multi-server shared
economy", "ASA cluster transfer", "Shared cluster save dir"). Building the DB as a real MariaDB
service now (not SQLite) is what lets M3 add servers with zero teardown — re-sequencing the DB
later would force a migration, so it's correctly here.

### Milestone 3: Cluster (one economy + one config across maps) — NEXT
**Value delivered**: Two or more map servers (e.g. The Island + Scorched Earth) sharing the one
MariaDB economy AND ASA's native cluster transfer AND a single shared configuration, so players
move characters/dinos/items between maps, keep one points balance, and every map runs identical
rules without the operator editing N copies of the config. This is the full "thing Nitrado can't do."
**Execution plan**: `m3-cluster` (status: planned)
**Depends on**: Milestone 2.
**Rough scope**: Per-map server containers off the M2 image, all pointing at the shared MariaDB;
ASA cluster config (`-clusterid` + shared cluster save dir); per-server game/config volumes +
shared cluster volume; **shared config layer** — one canonical `Game.ini`, `GameUserSettings.ini`,
and plugin configs (ArkShop `config.json`, Permissions) used by every cluster server, with a small
set of **per-server overrides** for the map-specific bits (map name, ports, `SessionName`); verify
points + transfer + config consistency persist across maps.
**Ordering Rationale**: Needs M2's working single-server-with-shared-DB as the unit to replicate.
Builds directly on M2's config-on-a-volume seam — M3 makes that volume shared and adds the
override mechanism (additive, no teardown). Completes the M2 seams (multi-server economy, cluster
transfer, shared config). Pulling it earlier was rejected — clustering an unproven server just
multiplies debugging surface.

### Milestone 4: Operational tooling (CLI + backups)
**Value delivered**: Day-to-day operation is easy: an interactive ops CLI and a real backup system
for both world saves and the economy DB. The operator stops memorizing docker/RCON incantations.
**Execution plan**: `m4-ops-tooling` (status: planned)
**Depends on**: Milestone 2 (backups need the DB); fuller value after Milestone 3 (manages the cluster).
**Rough scope**: A **TypeScript interactive, menu-driven CLI** — run one command, it asks "what are
you here for?" and you pick (reboot / SaveWorld / custom RCON command / backup / restore / …), it
auto-routes, **no flags**. Backups covering BOTH world saves (`.ark`) AND the economy DB
(mysqldump) on a schedule/on-stop. Optionally a DB admin web UI (Adminer) for browsing balances.
**Ordering Rationale**: Tooling polishes an already-working system, so it's last. Backups are here
(not M2) to cover world saves + economy DB in one consistent system — accepted risk: the economy DB
is unbacked between M2 ship and M4 (fine for a non-production early server). The interactive CLI
manages the cluster, so it's most valuable after M3 exists.

## Out of Scope
- **VPS / production deploy**: Patrick owns this end-to-end (provision, DNS, firewall, secrets on
  the box). The roadmap targets the reproducible stack; where it runs in prod is the operator's call.
- **Custom economy layer (website / Discord bot / web dashboard / player trading)**: explicitly
  deferred. ArkShop-as-is is the M2/M3 economy. If wanted, it's a clean FUTURE milestone that
  connects to the same MariaDB — additive, no teardown. Tracked as a `NEEDS-PLANNED` ledger row.
- **Cross-game economy** (sharing points with non-ARK games): not a goal.
- **Auto-latest plugin updates**: rejected by decision (pinned-only).

## Deviations

_(Roadmap-level scope changes — capability moves between milestones or milestone-scope changes.
Empty at creation.)_

| Capability (verbatim from ledger Capability cell) | Originally assigned to | Now assigned to | Approved rationale (named cost + decision date) |
|---|---|---|---|
| — | — | — | _(empty — no milestone-scope deviations)_ |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AsaApi/ArkShop lag a game patch → server won't load after an ASA update | Med | High (cluster down) | Pinned versions + `UPDATE_ON_BOOT=0` by default; bump game only when AsaApi confirms compat; test on dell before prod |
| AsaApi or ArkShop abandoned/breaks long-term | Low | High | Economy data is in a standard MariaDB we own — survives ArkShop; could swap shop plugin or build custom layer on the same DB |
| VC++ 2019 redist won't install cleanly in the GE-Proton prefix | Med | High (AsaApi won't load) | Research exact install path in M2; GE-Proton bundles some redists already — verify what's actually needed; prefix lives on volume so it persists once working |
| Wrong MariaDB version vs ArkShop's bundled MySQL client lib | Low | Med | Resolve exact compatible MariaDB tag at M2 plan time; pin it |
| ArkShop auto-creates schema in a way we don't control | Med | Low | Let ArkShop own its schema (decided); we don't migrate its tables. A future custom layer adds its OWN tables alongside |
| Plugin config secrets (DB pass) leak into git or logs | Low | High | `.env` is gitignored; entrypoint writes config at boot, never logs the password; `WINEDEBUG` stays `-all` in normal runs |

## Open Questions for Patrick
- None blocking — all M2 foundational decisions are made. M3 cluster-layout and the
  custom-economy-layer "do we want it" question are deferred to their own plan time.
