---
slug: m2-shared-economy-store
type: execution
owner: Patrick
status: active
roadmap: ark-asa-server
milestone: m2-shared-economy-store
depends_on: [m1-lean-image]
files:
  - Dockerfile
  - entrypoint.sh
  - docker-compose.yml
  - .env.test.example
  - .env.prod.example
  - config/**
  - .claude/rules/build-time-vs-runtime.md
  - docs/**
  - README.md
created: 2026-06-20
last_updated: 2026-06-20
---

# Plan: M2 — Shared Economy Store (AsaApi + ArkShop + MariaDB)

Created: 2026-06-20
Status: pending_approval

## Context & Why

**Goal**: Turn the M1 lean single-server ASA image into a *modded* server with a working in-game
shop and points economy backed by a real shared database (MariaDB). After M2, the operator can
sell items/dinos/commands and players earn points by playtime — the "shared store" foundation
proven end-to-end on ONE map server. M3 later replicates this across a cluster.

**Why**: The shared economy is the project's differentiator — the thing managed hosts (Nitrado)
can't do. M1 (fast-boot single-server image) is done and proven on bare-metal `dell`, so this is
the right next investment. The economy is intentionally sequenced before clustering (M3): you
replicate a *working* unit, not an unproven one.

**Background (what exists today — M1)**:
- `Dockerfile` builds on `ghcr.io/parkervcp/steamcmd:proton`; bakes SteamCMD + `steamclient.so`
  into the image; the ~13GB game installs at **runtime** onto the `ark-game` named volume.
- `entrypoint.sh` (runs as non-root `container`) installs/updates the game, symlinks the config
  dir + `steamclient.so`, then launches `ArkAscendedServer.exe` via `proton run`.
- `docker-compose.yml` has a privileged `sysctl` init service (sets `vm.max_map_count`) and the
  `the-island` game service with the `ark-game` volume + a shallow `./config` host bind.
- **No database, no plugins, no AsaApi.** Launch is vanilla `ArkAscendedServer.exe`.

**Constraints** (from roadmap, all confirmed with Patrick):
- DB engine **must be MariaDB** — ArkShop rejects MySQL ≥ 8.0.28; MariaDB any version works.
- AsaApi + ArkShop + Permissions are community plugins → **pinned versions, rebuild-to-update**
  (no auto-latest; a bad upstream release must not silently brick the server on restart).
- Build-vs-runtime split is a hard project rule (`.claude/rules/build-time-vs-runtime.md`).
- Single test box: `dell` (bare-metal Ubuntu 22.04). Prod deploy = operator's VPS (out of scope).
- Single map only (`TheIsland_WP`). Multi-server / cluster transfer = M3 (designed seams).

**Success criteria**: On `dell`, `docker compose up` brings up MariaDB + the modded server;
`ArkApi.log` shows AsaApi initialized; ArkShop connects to MariaDB with no `Singleton not found`
and no DB error; an in-game/RCON shop action persists a row to MariaDB; the M1 fast-boot config
loop still works; the whole thing is revertible to vanilla via an env toggle (no rebuild needed).

## Research Findings

(Web research 2026-06-20 — sources cited inline; AsaApi/ArkShop are fast-moving community plugins,
so versions are pinned and the distribution channel is a Phase-2 verification step.)

1. **AsaApi (ASA Server API) — current stable v1.21 (2026-04-05)**. Unzips into
   `ShooterGame/Binaries/Win64`; plugins go in `Win64/ArkApi/Plugins/<name>/` where the plugin's
   **DLL filename must match its containing folder name** or it won't load. Framework log:
   `ShooterGame/Binaries/Win64/logs/ArkApi.log`. You launch **`AsaApiLoader.exe`** with the *same*
   params as `ArkAscendedServer.exe`. **Requires the MS Visual C++ 2019 Redistributable.**
   (ark-server-api.com/resources/asa-server-api.31)
2. **ArkShop ASA** config has a `Mysql` block: `UseMysql` (bool), `MysqlHost`, `MysqlUser`,
   `MysqlPass`, `MysqlDB`, `MysqlPort`. Depends on the **Permissions** plugin (also baked) AND on
   the **ASA API Utils** CurseForge *mod* — missing it throws `Singleton not found`. ArkShop is
   the Michidu/Ark-Server-Plugins project. (ark-server-api.com/resources/asa-arkshop.34;
   github.com/Michidu/Ark-Server-Plugins)
3. **ASA API Utils** is a CurseForge *mod* (server-side, `windowsserver` zip), NOT a plugin — it
   rides ASA's native `-mods` mechanism, which the entrypoint already supports (`MODS=` →
   `-mods=` at entrypoint.sh:91). Need its numeric CurseForge mod ID at execution.
   (curseforge.com/ark-survival-ascended/mods/asa-api-utils)
4. **MariaDB**: all versions supported by ArkShop. Reference Docker-on-Proton projects install the
   VC++ redist into the Proton environment **at runtime** and launch via `AsaApiLoader.exe`.
   (Acekorneya/Ark-Survival-Ascended-Server)

**Two architectural findings that shape the phases** (both = the same build-vs-runtime tension the
rule already governs; resolved by the rule's own 3-question test, since both targets live on the
`ark-game` volume → at least one "yes" → entrypoint):

- **(A) The Proton prefix is on the volume** (`STEAM_COMPAT_DATA_PATH=…/arkserver/steamapps/compatdata/2430930`,
  Dockerfile:34) and is created at runtime on first boot. The VC++ redist therefore CANNOT be baked
  into a prefix at image-build time — it must be installed into the volume prefix at runtime
  (marker-guarded, idempotent). The rule's example table says "VC++ → Dockerfile" but that assumed
  a prefix-in-image; the table is stale for the volume-backed-prefix case and gets **amended in
  Phase 3**.
- **(B) The game's `Binaries/Win64` is on the volume** (the whole game installs at runtime,
  Dockerfile:28-34; volume mounts at `/home/container/arkserver`). Plugins live *under* that path,
  so they can't be `COPY`-ed there in the image (the volume overlays it). Resolution mirrors the
  `steamclient.so` pattern: **bake the pinned plugin binaries into the image at a neutral `/opt`
  path, and the entrypoint syncs them onto the volume's `Win64` each boot** (image = version
  source-of-truth, satisfies roadmap's "baked at pinned versions"; deployed at runtime where the
  game expects them).

## Decision Ledger

| # | Decision / claim | Class | Citation / recorded answer |
|---|---|---|---|
| 1 | Proton prefix lives on the `ark-game` volume (created at runtime) → VC++ redist must install at runtime, not build | verified | `Dockerfile:34` (`STEAM_COMPAT_DATA_PATH=/home/container/arkserver/steamapps/compatdata/2430930`) + `docker-compose.yml:40` (`ark-game:/home/container/arkserver`) |
| 2 | Game `Binaries/Win64` lives on the volume (installed at runtime) → plugins can't be `COPY`-ed there in the image; bake to `/opt` + entrypoint-sync | verified | `Dockerfile:28-34` (pre-create empty `arkserver`, game installs at runtime) + `entrypoint.sh:33-34` (steamcmd `+force_install_dir "${ARK_DIR}"`) |
| 3 | Entrypoint already has the `MODS=` → `-mods=` mechanism for CurseForge mods → ASA API Utils rides it | verified | `entrypoint.sh:17` (`MODS` default), `entrypoint.sh:91` (`-mods=${MODS}`) |
| 4 | Config-on-host symlink pattern exists → reuse it for plugin config | verified | `entrypoint.sh:62-69` (mkdir chain + `ln -sfn /home/container/config`) |
| 5 | Launch target is `ArkAscendedServer.exe`, set in one place + launched in one place → single flip point | verified | `entrypoint.sh:24` (`SERVER_EXE=…/ArkAscendedServer.exe`), `entrypoint.sh:95` (`proton run "${SERVER_EXE}"`) |
| 6 | `steamclient.so` is baked in `/opt/steamcmd` and linked onto the volume at boot → precedent for the bake-to-/opt + runtime-deploy pattern | verified | `Dockerfile:20-24`, `entrypoint.sh:74-77` |
| 7 | VC++ redist installs **in the container at runtime**, as its **own phase** | needs-Patrick | Patrick, 2026-06-20: "so make it in the container… as a phase… i'd want us to follow the rules." |
| 8 | 5-phase shape (MariaDB · bake plugins · VC++ in container · flip launcher · ArkShop↔MariaDB), VC++ standalone | needs-Patrick | Patrick, 2026-06-20: "it should be good" (approving the proposed table) |
| 9 | MariaDB pinned tag = `mariadb:11.4` (LTS) | needs-Patrick | Proposed; low-stakes — Patrick to confirm/override at approval |
| 10 | AsaApi pinned = v1.21; ArkShop/Permissions pinned to current stable at execution | needs-Patrick | AsaApi 1.21 fixed (research); plugin versions resolved at Phase-2 execution and recorded |
| 11 | MariaDB is internal to the compose network (no host port) — server connects via service name `mariadb:3306` | verified-design | Reduces attack surface; ArkShop `MysqlHost=mariadb` |
| 12 | Plugin sync uses clean-replace (stash configs → rm AsaApi-owned paths → cp fresh → restore configs), NOT rsync --delete | verified-design | rsync not guaranteed in parkervcp/steamcmd:proton base; under `set -euo pipefail` a missing rsync aborts with a confusing error; POSIX cp/rm always present (Phase-2 execution) |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AsaApi won't load under GE-Proton even with VC++ (the core unknown) | Med | High (M2 blocked) | Phase 4 is the explicit gate; `WINEDEBUG=+err,+seh` to surface the real fault; `ENABLE_ASAAPI=0` env toggle reverts to vanilla launch with no rebuild |
| Compiled ArkShop/Permissions DLLs only available behind an auth-gated site (ark-server-api.com), not a scriptable URL | Med | High (can't bake in Dockerfile non-interactively) | Phase 2 step 1 = resolve the distribution channel FIRST (GitHub releases vs. mirror vs. build-from-source); record the pinned URL/version. If auth-gated only, fall back to a committed vendored binary or a build stage — decide at Phase 2, don't assume |
| VC++ redist silent-install fails or installs to the wrong prefix | Med | High (AsaApi won't load) | Verify the three runtime DLLs land in the prefix `system32` (Phase 3 AC); marker only written after that check passes (same "trust the artifact, not the exit code" lesson as the `.installed` marker) |
| ASA API Utils mod ID wrong / mod won't download → `Singleton not found` | Med | Med | Phase 5 AC checks `ArkApi.log` has no `Singleton not found`; verify the mod actually downloaded under the game's mods dir before declaring done |
| Wrong MariaDB ↔ ArkShop client-lib pairing | Low | Med | Pin `mariadb:11.4`; ArkShop ships its own MySQL client lib — verify connection in Phase 5; bump tag if the handshake fails |
| DB password leaks into git or container logs | Low | High | Creds in gitignored `.env` only (`.gitignore:2`); entrypoint writes `config.json` at boot and never echoes the password; `WINEDEBUG=-all` in normal runs |
| Entrypoint plugin-sync clobbers operator's edited `config.json` on every boot | Med | Med | Sync **binaries** only; treat plugin **config** as host-owned (symlink/seed-once, never overwrite) — Phase 2 syncs binaries, Phase 5 handles config separately with a seed-if-absent rule |
| Economy DB unbacked between M2 ship and M4 | Med | Med | Accepted (roadmap decision — backups are M4); data is in a standard MariaDB volume we own, survivable |

## Questions

- **MariaDB tag**: `mariadb:11.4` (LTS) unless you prefer a specific tag. (Decision Ledger #9.)
- **ASA API Utils CurseForge mod ID**: needed at Phase 5 execution — I'll look it up then and
  record it; flag if you already know it.
- Everything else is decided (roadmap locked the engine/pinning/config-on-volume calls; you
  confirmed VC++-in-container-as-own-phase and the 5-phase shape).

## Risk Assessment & Rollout Strategy

**Risk level: MEDIUM**

| Criteria | Applies? | Notes |
|---|---|---|
| Touches payments/billing | No | In-game points only, no real money |
| Touches auth/permissions | No (new DB creds, not user auth) | DB creds are infra secrets in `.env`, not a user-auth surface |
| Raw SQL / literals | No | ArkShop owns 100% of its SQL; we never write queries |
| Modifies existing data | No | New DB + new volume; game saves untouched |
| Third-party integration | Yes | AsaApi + ArkShop + Permissions + MariaDB → MEDIUM |
| Changes existing behavior | Yes | Launch flips `ArkAscendedServer.exe` → `AsaApiLoader.exe` → MEDIUM |

**Mitigations applied:**
- **`ENABLE_ASAAPI` env toggle (kill switch)** → Any → one level lower. `0` = vanilla M1 launch
  (no rebuild), `1` = modded launch. Revert is an env edit + restart.
- **Backward compatible** (old vanilla launch path preserved behind the toggle) → safe rollback.
- **Idempotent, marker-guarded entrypoint** steps → re-runnable, no first-boot assumptions.

**Rollout plan:**
1. Internal: build + boot on `dell` (the only test box), `.env.test` profile, `ENABLE_ASAAPI=1`.
   Verify AsaApi loads, ArkShop connects, points persist. 3-5 days of restart-loop + shop testing.
2. Prod: operator's VPS with `.env.prod` (BattlEye on, update-on-boot) — operator-owned, out of
   roadmap scope. No staged % rollout (single-tenant self-hosted server).

## Design Divergences

_(Divergences from a `[locked]` design doc. The `build-time-vs-runtime.md` rule's example **table**
is amended in Phase 3 to match the volume-backed-prefix reality — this is a doc *correction* made
in-change, not a divergence from the rule's actual logic (the 3-question procedure already yields
"entrypoint" for volume-backed targets). No `[locked]` design doc is contradicted. Empty.)_

| Doc | What it says | What we do instead | Approved rationale (named cost + reversal path) |
|-----|-------------|-------------------|------------------------------------------------|
| — | — | — | _(empty — no divergences; the rule table is corrected in-change, see Phase 3)_ |

## Documentation Deliverables

| Deliverable | Phase | Notes |
|---|---|---|
| ADR: DB engine = MariaDB (graduate roadmap decision) | 1 | `docs/internal/decisions/0001-db-engine-mariadb.md` — context, MySQL-8.0.28 rejection, rejected alternatives |
| ADR: image-baked artifacts deployed onto the volume at runtime (VC++ + plugins pattern) | 3 | `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — the build-vs-runtime resolution for volume-backed prefix + Win64 |
| Create `.claude/design-sources.md` registry | 3 | Register `build-time-vs-runtime.md` `[locked]` + the two ADRs `[locked]`; bootstrap (none exists today) |
| README: roadmap line bump (M2 in progress → traits) + "Database" note | 1 / 5 | Replace the M1-era "MySQL" wording with MariaDB; document the shared-store usage + plugin-config loop |

_(Per-phase doc-ACs live in their phases' Acceptance criteria — e.g. the `build-time-vs-runtime.md`
table amendment is a Phase 3 AC. This section is only the cross-cutting deliverables.)_

## Planned RED Repros

_(Not a bug-fix plan — no intentional RED breaks. Empty.)_

| What's intentionally broken | Locking RED test | Asserted contract | Fixing phase | Prod-exposure note |
|---|---|---|---|---|
| — | — | — | — | _(empty — no planned RED repros)_ |

## Behavioral Contract

_(No gate-shaped work. The entrypoint's install/sync markers (`.installed`, `.vcredist-installed`)
and the `ENABLE_ASAAPI` toggle are idempotency guards / a simple config switch, not predicates that
classify variable input to decide whether a user-observable behavior fires — the rule explicitly
excludes idempotency/validation passthroughs. Empty.)_

| Gate (file/function or phase) | Input shape / fixture | Outcome (FIRE/DECLINE) | Why (spec/doc citation) |
|---|---|---|---|
| — | — | — | _(empty — no gate-shaped work)_ |

## Phase Execution Protocol

Each phase ends with an **Exit Sequence** (persist plan state → persist deviation scratch →
fan out all reviewers + N deviation-judges in parallel → coordinator writes Evidence + Phase
Review Gates → handle verdicts → prompt commit). The canonical fan-out spec is
`~/.claude/commands/execute-plan.md` Step 3.d–3.h; this file references it rather than duplicating.

**Final phase additionally**: verify all phases' AC/quality checkboxes; fan out the full reviewer
+ cumulative-judge set against the cumulative diff (Opus overrides); flip `status: active → done`
only after all PASS.

**Shipping**: per-phase → commit on branch `feat/m2-<n>-<name>`; open a draft PR via `/pr` against
`main` (or merge to `master` directly — solo infra repo, Patrick's call). Milestone wrap → merge to
`master`; VPS deploy is operator-owned (out of scope).

## Phases

### Phase 1: Self-contained MariaDB service + secrets
**PR scope**: Add a `mariadb` service + `ark-db` volume + healthcheck to compose; wire DB creds via `.env`; game service waits for DB healthy.
**Branch**: `feat/m2-1-mariadb`
**Flag**: N/A (additive service; no game-behavior change yet)
**Est. lines**: ~50
**Executor tier**: standard
**Ships via**: commit + `/pr` draft (or direct to `master`)
**Objective**: A MariaDB instance comes up with `docker compose up`, is reachable on the compose
network as `mariadb:3306` with the ArkShop app user/db created, persists across restart, and the
game service only starts once the DB is healthy. No plugins yet — this phase delivers the DB alone.
**Why this phase exists**: The shared store needs a real DB before any plugin can use it. Bringing
it up + verifying it independently isolates DB problems from plugin problems.
**Current-state anchors**:
- `docker-compose.yml:8` — `services:` block (add `mariadb` here)
- `docker-compose.yml:19-25` — `the-island` service + its `depends_on: sysctl` (extend with DB)
- `docker-compose.yml:53-55` — `volumes:` (add `ark-db`)
- `.gitignore:2-4` — `.env*` ignored except the `.example` templates (new creds go in `.env*`)
**Files (expected scope)**: `docker-compose.yml`, `.env.test.example`, `.env.prod.example`, `README.md`, `docs/internal/decisions/0001-db-engine-mariadb.md`
**Scope Boundary**:
- **In scope**: "Self-contained MariaDB service in compose" (ledger), "DB secrets via `.env`" (the secrets half of "DB secrets via `.env`; entrypoint writes ArkShop config at boot" — config-writing is Phase 5).
- **Explicitly NOT delivered (deferred)**: "ArkShop configured against MariaDB (shared store)" → Phase 5 of this milestone; "Multi-server (2+ maps) pointing at the shared MariaDB economy" → m3-cluster.
**Deviation rule**: May touch adjacent compose/env lines if needed; document each deviation with a one-line reason. Unrelated changes → split out.
**Steps**:
1. Add a `mariadb` service to `docker-compose.yml`: `image: mariadb:11.4`, env `MARIADB_ROOT_PASSWORD`, `MARIADB_DATABASE` (e.g. `arkshop`), `MARIADB_USER` (e.g. `arkshop`), `MARIADB_PASSWORD` (all from `.env`); volume `ark-db:/var/lib/mysql`; `network_mode` default (NOT `none` — must be reachable by the game service); no host port published (internal only); `restart: unless-stopped`.
2. Add a healthcheck: `healthcheck: test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]` (or `mariadb-admin ping`), with interval/retries.
3. Extend `the-island.depends_on` to also require `mariadb: { condition: service_healthy }` (keep the existing `sysctl: service_completed_successfully`).
4. Add `ark-db` to the `volumes:` block.
5. Add the four `MARIADB_*` vars to both `.env.test.example` and `.env.prod.example` with placeholder values + a comment that real values live in the gitignored `.env*`.
6. README: update the "Database" wording (M1 said "none yet / MySQL") to MariaDB; note the DB comes up with the stack.
7. Write ADR `0001-db-engine-mariadb.md` (context, the MySQL ≥8.0.28 rejection, rejected alternatives: pinned MySQL 8.0.27 / SQLite-only).
**Acceptance criteria**:
- [x] `docker compose --env-file .env.test up` starts `mariadb` and it reaches `healthy` before `the-island` starts
  - Evidence: `phase1-runtime-evidence.md` §AC1 — `poll 3: health=healthy` + `docker compose ps` shows `Up 15 seconds (healthy)` (local WSL-docker boot; host-agnostic for stock `mariadb:11.4`, no Proton). Ordering guaranteed by `docker-compose.yml` `the-island.depends_on.mariadb: condition: service_healthy` (Compose v2 hard guarantee); full-stack ordering empirically confirmed on dell in Phase 4/5. acceptance-verifier round 2: MET.
- [x] The app user can connect to the `arkshop` DB on `mariadb:3306` from within the compose network (verify via `docker compose exec`)
  - Evidence: `phase1-runtime-evidence.md` §AC2 — `docker compose exec -T mariadb mariadb -u arkshop -p… arkshop -e 'SELECT 1 AS app_user_connects;'` → `1` (exit 0), run inside the compose network. acceptance-verifier round 2: MET.
- [x] DB data persists across `docker compose restart mariadb` (a test table/row survives)
  - Evidence: `phase1-runtime-evidence.md` §AC3 — INSERT `42` into `_phase1_persist` → `docker compose restart mariadb` → poll healthy → `SELECT * FROM _phase1_persist` returns `42` (exit 0). Backed by `ark-db:/var/lib/mysql` named volume (`docker-compose.yml`). acceptance-verifier round 2: MET.
- [x] No host port is published for MariaDB (internal-only); `docker compose ps` shows no `0.0.0.0:3306`
  - Evidence: `docker-compose.yml` — `mariadb` service has no `ports:` key (structural guarantee); `phase1-runtime-evidence.md` §AC1 `docker compose ps` PORTS column shows `3306/tcp` with no `0.0.0.0:` prefix. acceptance-verifier round 2: MET.
- [x] `docs/internal/decisions/0001-db-engine-mariadb.md` exists with context + rejected alternatives; README "Database" wording updated to MariaDB
  - Evidence: `docs/internal/decisions/0001-db-engine-mariadb.md` created (+77 lines) — Context (ArkShop client lib constraint), Decision (`mariadb:11.4`), Rationale (MySQL ≥8.0.28 rejection), Rejected alternatives (MySQL 8.0.27 EOL; SQLite-only build-twice), + 4-field backup deferral anchored to `capability-ledger.md` `m4-ops-tooling` row. `README.md` `## Database` section added + roadmap line MySQL→MariaDB. acceptance-verifier round 2: MET.
**Quality gate**:
- [ ] Creds only in `.env*` (gitignored) + placeholders in `.example`; no secret committed
- [ ] DB not exposed to the host network
- [ ] Healthcheck gates the game service (no race on first boot)
- [ ] Follows existing compose patterns (service shape, volume naming)
**Verification**: `docker compose --env-file .env.test up -d mariadb` → `docker compose ps` shows healthy → `docker compose exec mariadb mariadb -u arkshop -p arkshop -e 'SELECT 1;'` succeeds.

**Phase Review Gates**:
- [x] code-reviewer: PASS 2026-06-20T20:42 (round 2)
- [x] rules-compliance-reviewer: PASS 2026-06-20T20:42 (round 2; round 1 BLOCK on 3 comment/doc fixes resolved)
- [x] plan-adherence-verifier: PASS 2026-06-20T20:42 (round 2; Scope-escape CLEAR, 7/7 Steps MET)
- [x] acceptance-verifier: PASS 2026-06-20T20:42 (round 2; 5/5 ACs MET with runtime receipts; round 1 BLOCK on AC1/2/3 WEAK resolved)
- [x] design-compliance-reviewer: PASS 2026-06-20T20:42 (round 2; loud-fallback — registry created in Phase 3)
- [x] deviation-judge #1 (scope: phase1-runtime-evidence.md evidence receipt): PASS 2026-06-20T20:42
- [x] Committed: 21fe5a8

### Phase 2: Bake AsaApi + ArkShop + Permissions into the image (pinned) + entrypoint deploy
**PR scope**: Dockerfile downloads pinned plugin binaries to `/opt/asaapi/`; entrypoint syncs them onto the volume's `Win64` each boot. No launch change yet.
**Branch**: `feat/m2-2-bake-plugins`
**Flag**: N/A (binaries staged; not launched until Phase 4)
**Est. lines**: ~60
**Executor tier**: standard
**Ships via**: commit + `/pr` draft (or direct to `master`)
**Objective**: After a boot, the volume's `ShooterGame/Binaries/Win64` contains `AsaApiLoader.exe`
+ the AsaApi runtime + `ArkApi/Plugins/{ArkShop,Permissions}/` at the pinned versions, deployed
from image-baked copies. The image is the version source-of-truth; the deploy is idempotent.
**Why this phase exists**: AsaApi + plugins must physically exist on the volume where the game
expects them before we can flip the launcher (Phase 4) or configure ArkShop (Phase 5). Separating
"get the bits in place" from "launch them" isolates packaging problems from runtime-load problems.
**Current-state anchors**:
- `Dockerfile:20-24` — the `steamclient.so` bake (precedent: download to `/opt`, `chown container`)
- `Dockerfile:26-29` — pre-create `arkserver` owned by `container`
- `entrypoint.sh:74-77` — the `steamclient.so` boot-time link (precedent for runtime-deploy)
- `entrypoint.sh:79` — `install_or_update` call (sync runs AFTER game install, BEFORE launch)
**Files (expected scope)**: `Dockerfile`, `entrypoint.sh`
**Scope Boundary**:
- **In scope**: "AsaApi loader baked into image at pinned version", "ArkShop plugin baked into image at pinned version", "Permissions plugin baked into image (ArkShop dependency)", "Pinned plugin versions (rebuild-to-update)" (ledger).
- **Explicitly NOT delivered (deferred)**: "Launch flips to `AsaApiLoader.exe`" → Phase 4; "VC++ 2019 redist installed in the Proton prefix" → Phase 3; "ArkShop configured against MariaDB" → Phase 5.
**Deviation rule**: May adjust adjacent Dockerfile/entrypoint lines; document deviations. Unrelated changes → split.
**Steps**:
1. **Resolve the distribution channel FIRST** (see Risks): find a scriptable, non-interactive
   download URL for the pinned AsaApi v1.21, ArkShop, and Permissions binaries (GitHub releases
   preferred). If only an auth-gated site exists, decide between a vendored committed binary or a
   build stage — record the choice + pinned versions in this plan's notes before proceeding.
2. Dockerfile: add `ARG` pins (`ASAAPI_VERSION=1.21`, `ARKSHOP_VERSION=…`, `PERMISSIONS_VERSION=…`)
   and `RUN` steps (as root) to download + unzip into `/opt/asaapi/` with the AsaApi tree at the
   root and plugins under `/opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/` (DLL name == folder
   name). `chown -R container:container /opt/asaapi`.
3. entrypoint: after `install_or_update` (entrypoint.sh:79) and before launch, add a
   `deploy_plugins()` that syncs `/opt/asaapi/*` into `${ARK_DIR}/ShooterGame/Binaries/Win64/`
   (binaries only; idempotent so the pinned image version always wins). The sync must **cleanly
   replace** the AsaApi/plugin tree on a version bump — stale files from a prior version must not
   linger (e.g. `rsync --delete` scoped to the AsaApi-owned subdirs, or remove-then-copy the
   `ArkApi/` + loader paths). Do NOT touch the rest of `Win64` (game files) or plugin `config.json`
   (config handled in Phase 5 — deploy the default config only on first boot if absent).
4. Keep launch as `ArkAscendedServer.exe` (unchanged this phase).
**Acceptance criteria**:
- [x] Image contains `/opt/asaapi/AsaApiLoader.exe` + `/opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/` at pinned versions (verify in the built image)
  - Evidence: `Dockerfile:32-54` — `ARG ASAAPI_VERSION=1.21`/`ARKSHOP_VERSION=1.4`; `curl …asa-server-api.31/download?version=${ASAAPI_VERSION}` → `cp -r ArkApi /opt/asaapi/` (carries `Plugins/Permissions/Permissions.dll`) + explicit root-file cp; `curl …asa-arkshop.34/download?version=${ARKSHOP_VERSION}` → `cp -r ArkShop/. /opt/asaapi/ArkApi/Plugins/ArkShop/`; `find /opt/asaapi -name '*.pdb' -delete` then `chown`. Coordinator pre-gate probe (notes.md §coordinator probes): live `curl`+`unzip -l` confirmed HTTP 200 / PK-ZIP magic / all six root files present / `ArkApi/Plugins/Permissions/Permissions.dll` + `ArkShop/ArkShop.dll` (folder==DLL-name). Static-evidence ceiling — real `docker build` deferred to Phase 4 (dell). acceptance-verifier round 2: MET.
- [x] After a boot, the volume's `…/Binaries/Win64/` contains `AsaApiLoader.exe` + `ArkApi/Plugins/{ArkShop,Permissions}/` with each plugin's DLL name matching its folder
  - Evidence: `entrypoint.sh:55-126` `deploy_plugins()` — `cp -r "${src}/ArkApi" "${win64}/"` propagates the full `Plugins/` tree (Permissions + ArkShop with their DLLs) + explicit `cp` of `AsaApiLoader.exe`. Folder==DLL-name preserved verbatim by `cp -r` (probe-confirmed in the source ZIPs). Runtime boot receipt deferred to Phase 4 (dell). acceptance-verifier round 2: MET.
- [x] The deploy step is idempotent — a second boot re-syncs without error and without duplicating/clobbering game files
  - Evidence: `entrypoint.sh:85-94` — stash plugin configs → `rm -rf` AsaApi-owned paths (no-op on absent paths under `set -euo pipefail`) → `cp -r` fresh → restore configs. Rm list scoped to AsaApi-owned paths only; game files outside it untouched (negative-scope guarantee). deviation-judge #1 (round 2) traced first-boot-absent / warm-boot / zero-plugin cases: no break. acceptance-verifier round 2: MET.
- [x] A version bump (changed `ASAAPI_VERSION`/plugin `ARG`) cleanly REPLACES the deployed tree — no stale files from the prior version remain in `ArkApi/`/loader paths
  - Evidence: `entrypoint.sh:85` `rm -rf "${win64}/ArkApi"` wipes the whole subtree before `cp -r` fresh → no file from a prior `ArkApi/` can survive; root loader/DLLs individually in the rm list; build-time `.pdb` strip means no stale debug blobs either. (Judge-noted future-version undershoot: a root-level DLL *added then dropped* across versions isn't on the static rm list — flagged for a later hardening, outside Phase-2 v1.21-pinned scope.) acceptance-verifier round 2: MET.
- [x] Pinned versions are recorded (Dockerfile `ARG`s + plan notes); no auto-latest fetch
  - Evidence: `Dockerfile:32-34` — three `ARG`s pinned; both download URLs use `?version=${ARG}` (not `latest`). `PERMISSIONS_VERSION` carries an explicit doc-pin comment (drives no download — Permissions ships bundled in the AsaApi zip). notes.md §distribution-channel records the resolved versions + anti-latest rationale. acceptance-verifier round 2: MET.
**Quality gate**:
- [ ] `/opt/asaapi` owned by `container` (non-root can read at runtime)
- [ ] Deploy runs after game install, before launch; safe to re-run
- [ ] Binaries baked at pinned versions (rebuild-to-update); distribution URL pinned
- [ ] No plugin config overwritten if already present on the volume
**Verification**: build image → `docker run --rm ark-asa:latest ls /opt/asaapi` shows the tree; boot → `docker compose exec the-island ls …/Binaries/Win64/ArkApi/Plugins` shows ArkShop + Permissions.

**Phase Review Gates**:
- [x] code-reviewer: PASS 2026-06-20T22:30 (round 3 final; R1 BLOCK on .pdb bloat + dead PERMISSIONS_VERSION pin resolved R2; R3 polish comment-only, no regression)
- [x] rules-compliance-reviewer: PASS 2026-06-20T22:30 (round 3 final; R1 BLOCK on phase-ref comment + unexplained ARG resolved R2; R2 Big-O concern resolved R3 — Hard Rule 7 satisfied)
- [x] plan-adherence-verifier: PASS 2026-06-20T22:30 (round 3 final; Scope-escape CLEAR, 4/4 Steps MET)
- [x] acceptance-verifier: PASS 2026-06-20T22:30 (round 3 final; 5/5 ACs MET at static-evidence ceiling — runtime boot receipts deferred to Phase 4/dell)
- [x] design-compliance-reviewer: PASS 2026-06-20T22:30 (round 2 PASS, carried R3 — no [locked] globs under absent registry, comment-only delta; loud-fallback, registry created in Phase 3; .pdb strip-at-build honors 3-question split)
- [x] deviation-judge #1 (scope: clean-replace decision re-homed to plan.md Decision Ledger row #12): PASS 2026-06-20T22:30 (round 2 PASS, carried R3 — plan.md/notes.md untouched; R1 decision-in-churn BLOCK resolved)
- [x] deviation-judge #2 (approach: stash-rm-cp clean-replace, not rsync --delete): PASS 2026-06-20T22:30 (round 3 final; sound; dual-static-list coupling fails loud, deferred to Phase 5)
- [x] deviation-judge #3 (approach: versioned URLs + PERMISSIONS_VERSION doc-pin): PASS 2026-06-20T22:30 (round 3 final; R1 dead-pin BLOCK resolved via doc-pin comment R2; R2 stale-literal residual de-hardcoded R3)
- [ ] Committed: <commit SHA>

### Phase 3: Install VC++ 2019 redist — in the container, at runtime
**PR scope**: Bake the VC++ 2019 redist installer in the image; entrypoint installs it into the volume Proton prefix (marker-guarded, idempotent). Amend `build-time-vs-runtime.md` to match the volume-backed-prefix reality.
**Branch**: `feat/m2-3-vcredist`
**Flag**: N/A
**Est. lines**: ~40 (+ doc edits)
**Executor tier**: standard
**Ships via**: commit + `/pr` draft (or direct to `master`)
**Objective**: After a boot, the Proton prefix on the volume has the VC++ 2019 runtime DLLs
installed, so AsaApi can load (Phase 4). The install runs once (marker-guarded) and is a no-op on
subsequent boots. This is the build-vs-runtime fix you asked for, done by the rule's own logic.
**Why this phase exists**: AsaApi requires the VC++ 2019 redist. The prefix is on the volume
(created at runtime), so the redist can't be baked at build — it installs at runtime. Isolating it
as its own phase makes the "redist landed" fact independently verifiable before the launcher flip.
**Current-state anchors**:
- `Dockerfile:31-37` — `ENV` block incl. `STEAM_COMPAT_DATA_PATH` (the prefix path; `…/pfx` is the WINEPREFIX)
- `entrypoint.sh:71-77` — the `steamclient.so` link (precedent: bake in `/opt`, act at boot)
- `entrypoint.sh:79` — `install_or_update`; VC++ install runs after game install, before deploy/launch
- `.claude/rules/build-time-vs-runtime.md` — "The Split" table row "Wine prefix + VC++ redist install → Dockerfile" (the stale row to amend)
**Files (expected scope)**: `Dockerfile`, `entrypoint.sh`, `.claude/rules/build-time-vs-runtime.md`, `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`, `.claude/design-sources.md`
**Scope Boundary**:
- **In scope**: "VC++ 2019 redist installed in the Proton prefix" (ledger).
- **Explicitly NOT delivered (deferred)**: "Launch flips to `AsaApiLoader.exe`" → Phase 4 (this phase only makes the redist present; nothing launches it yet).
**Deviation rule**: May touch adjacent entrypoint/Dockerfile lines; document deviations. Unrelated → split.
**Steps**:
1. Dockerfile: download the VC++ 2019 (14.2x) redist `VC_redist.x64.exe` to `/opt/vcredist/` (as root), `chown container`.
2. entrypoint: add `install_vcredist()`. **Gate the skip on the actual DLLs**, not a bare marker — check for the three runtime DLLs in the prefix system32; if all present, skip. This survives a `pfx/` reset (a marker on the volume would falsely skip after someone nukes the prefix, and AsaApi would silently fail to load). When the DLLs are absent, run `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` (HOME/prefix env already set in `main`). Call it after `install_or_update`, before launch.
3. After install, verify the three runtime DLLs landed (`${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/{msvcp140.dll,vcruntime140.dll,vcruntime140_1.dll}`) — fail fast with a clear message if not (same "verify the artifact, not the exit code" discipline as the `.installed` gate at entrypoint.sh:38). A `.vcredist-installed` marker may be written as a fast-path hint, but the DLL presence check is the source of truth.
4. Amend `build-time-vs-runtime.md`: correct the "Wine prefix + VC++ redist install" table row — when the prefix is volume-backed (this project's design), VC++ install is **entrypoint** (the 3-question test: depends on a mounted volume → yes → entrypoint). Add a one-line note explaining the table previously assumed a prefix-in-image.
5. Write ADR `0002-runtime-deploy-of-image-baked-artifacts.md` (the pattern: bake immutable artifacts in `/opt`, deploy/install onto the volume at runtime — covers VC++ AND plugins; cites the 3-question test).
6. Bootstrap `.claude/design-sources.md`: register `build-time-vs-runtime.md` `[locked]` + ADR 0001/0002 `[locked]`.
**Acceptance criteria**:
- [ ] After first boot, `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` contains `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`
  - Evidence: (filled at phase completion)
- [ ] The install-skip is gated on actual DLL presence (not a bare marker); a second boot skips the install (log shows the skip), and a `pfx/` reset correctly RE-triggers the install rather than falsely skipping
  - Evidence: (filled at phase completion)
- [ ] `build-time-vs-runtime.md` table row for VC++/prefix amended to reflect volume-backed-prefix → entrypoint, with the rationale note
  - Evidence: (filled at phase completion)
- [ ] ADR `0002` exists (pattern + 3-question-test rationale); `.claude/design-sources.md` created registering the rule + both ADRs `[locked]`
  - Evidence: (filled at phase completion)
**Quality gate**:
- [ ] Marker-guarded + idempotent (no re-install on warm boot)
- [ ] Redist installer baked in image (immutable); install acts on the volume prefix (runtime)
- [ ] Rule doc no longer contradicts the code (Rule 00 — one consistent home)
- [ ] No secret/log leakage introduced
**Verification**: fresh volume boot → check the three DLLs exist in the prefix; restart → log shows "VC++ already installed, skipping".

**Phase Review Gates**:
- [ ] code-reviewer: <verdict + ISO timestamp>
- [ ] rules-compliance-reviewer: <verdict + ISO timestamp>
- [ ] plan-adherence-verifier: <verdict + ISO timestamp>
- [ ] acceptance-verifier: <verdict + ISO timestamp>
- [ ] design-compliance-reviewer: <verdict + ISO timestamp>
- [ ] Committed: <commit SHA>

### Phase 4: Flip launch to AsaApiLoader.exe (AsaApi loads)
**PR scope**: Entrypoint launches `AsaApiLoader.exe` (behind an `ENABLE_ASAAPI` toggle) instead of `ArkAscendedServer.exe`; AsaApi initializes under Proton.
**Branch**: `feat/m2-4-asaapi-loader`
**Flag**: `ENABLE_ASAAPI` (env toggle; `1`=modded loader, `0`=vanilla M1 launch — kill switch)
**Est. lines**: ~30
**Executor tier**: standard
**Ships via**: commit + `/pr` draft (or direct to `master`)
**Objective**: With `ENABLE_ASAAPI=1`, the server launches via `AsaApiLoader.exe` with the same
map/query/flags, AsaApi initializes (proven by `ArkApi.log`), and the server still advertises for
join. With `ENABLE_ASAAPI=0`, behavior is identical to M1 (vanilla launch) — the rollback path.
**Why this phase exists**: This is the core unknown — does AsaApi load under GE-Proton at all?
Everything prior (bits in place, VC++ present) exists to make this gate pass. ArkShop config
(Phase 5) is pointless until AsaApi loads.
**Current-state anchors**:
- `entrypoint.sh:24` — `SERVER_EXE=…/ArkAscendedServer.exe` (add the loader path + toggle)
- `entrypoint.sh:86-91` — query string + flags (reused verbatim; loader takes the same args)
- `entrypoint.sh:95` — `proton run "${SERVER_EXE}" "${query}" ${flags}` (the launch line)
- `entrypoint.sh:20` — env-default block (add `ENABLE_ASAAPI` default here)
- `docker-compose.yml:29-38` — `environment:` (plumb `ENABLE_ASAAPI`)
**Files (expected scope)**: `entrypoint.sh`, `docker-compose.yml`, `.env.test.example`, `.env.prod.example`
**Scope Boundary**:
- **In scope**: "Launch flips to `AsaApiLoader.exe` (not `ArkAscendedServer.exe`)" (ledger).
- **Explicitly NOT delivered (deferred)**: "ArkShop configured against MariaDB" → Phase 5 (ArkShop may log a DB/Singleton error this phase — acceptable; this phase only proves AsaApi itself loads).
**Deviation rule**: May touch adjacent env/launch lines; document deviations. Unrelated → split.
**Steps**:
1. entrypoint: add `ENABLE_ASAAPI` default (`:= 1`) to the env block (~entrypoint.sh:20); define `LOADER_EXE=…/Binaries/Win64/AsaApiLoader.exe`.
2. At launch (entrypoint.sh:95): if `ENABLE_ASAAPI == 1`, `proton run "${LOADER_EXE}" "${query}" ${flags}`; else keep the vanilla `${SERVER_EXE}` path. Same `${query}`/`${flags}`.
3. compose: add `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` to `the-island.environment`; add the var to both `.env.*.example`.
4. Boot on `dell` with `ENABLE_ASAAPI=1` and confirm AsaApi init in `ArkApi.log`; if it faults, debug with `WINEDEBUG=+err,+seh`.
**Acceptance criteria**:
- [ ] With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / "loaded" lines), no fatal load error
  - Evidence: (filled at phase completion)
- [ ] The server still reaches "has successfully started" / advertises for join (the M1 success signal) under the loader
  - Evidence: (filled at phase completion)
- [ ] With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild
  - Evidence: (filled at phase completion)
**Quality gate**:
- [ ] Toggle defaults documented in `.env.*.example`
- [ ] Same query/flags reused (no drift between vanilla and loader launch)
- [ ] Rollback path (toggle `0`) verified, not just asserted
- [ ] `WINEDEBUG=-all` remains the default (no secret/noise leak)
**Verification**: `ENABLE_ASAAPI=1 docker compose up` on dell → `ArkApi.log` shows init + server advertises; flip to `0` → vanilla launch.

**Phase Review Gates**:
- [ ] code-reviewer: <verdict + ISO timestamp>
- [ ] rules-compliance-reviewer: <verdict + ISO timestamp>
- [ ] plan-adherence-verifier: <verdict + ISO timestamp>
- [ ] acceptance-verifier: <verdict + ISO timestamp>
- [ ] design-compliance-reviewer: <verdict + ISO timestamp>
- [ ] Committed: <commit SHA>

### Phase 5: ArkShop configured against MariaDB (shared store, end-to-end)
**PR scope**: Plugin config on the host volume; entrypoint injects DB secrets into ArkShop/Permissions `config.json` at boot; add ASA API Utils to `MODS`; prove points persist to MariaDB.
**Branch**: `feat/m2-5-arkshop-mariadb`
**Flag**: `ENABLE_ASAAPI` (same toggle gates the whole modded stack)
**Est. lines**: ~70
**Executor tier**: standard
**Ships via**: commit + `/pr` draft (or direct to `master`)
**Objective**: ArkShop + Permissions connect to MariaDB using creds from `.env` (injected at boot,
never committed), config is edit-on-host, the ASA API Utils mod loads, and a shop/points action
persists a row to MariaDB — the shared store proven end-to-end on one server.
**Why this phase exists**: This is the milestone's actual value — a working shared-DB economy.
It's last because it needs AsaApi loading (Phase 4) and the DB (Phase 1).
**Current-state anchors**:
- `entrypoint.sh:62-69` — the config-on-host symlink pattern (reuse for plugin config dirs)
- `entrypoint.sh:17,91` — `MODS=` → `-mods=` (add ASA API Utils mod ID here)
- `docker-compose.yml:39-44` — volume/bind block (add a plugin-config host bind if separate from `./config`)
- Phase 1's `MARIADB_*` env + Phase 2's deployed `ArkApi/Plugins/{ArkShop,Permissions}/`
**Files (expected scope)**: `entrypoint.sh`, `docker-compose.yml`, `config/**` (or a new `plugins-config/` bind), `.env.test.example`, `.env.prod.example`, `README.md`
**Scope Boundary**:
- **In scope**: "ArkShop configured against MariaDB (shared store)", "Edit-on-host plugin config (ArkShop `config.json`, etc.)", "DB secrets via `.env`; entrypoint writes ArkShop config at boot" (ledger).
- **Explicitly NOT delivered (deferred)**: "Multi-server (2+ maps) pointing at the shared MariaDB economy", "Shared plugin configs across cluster" → m3-cluster; "Custom economy layer" → NEEDS-PLANNED future milestone.
**Deviation rule**: May touch adjacent config/entrypoint lines; document deviations. Unrelated → split.
**Steps**:
1. Decide the plugin-config host home: a host-bound dir (reuse `./config` or add `./plugins-config`) symlinked into `…/ArkApi/Plugins/<name>/` per the entrypoint.sh:62-69 pattern. Seed the default `config.json` on first boot if absent; never overwrite an existing one.
2. entrypoint: inject DB secrets into ArkShop + Permissions `config.json` at boot from the `MARIADB_*`/dedicated `ARKSHOP_DB_*` env (set `UseMysql=true`, `MysqlHost=mariadb`, `MysqlUser`, `MysqlPass`, `MysqlDB`, `MysqlPort=3306`). Use a placeholder-substitution or `jq` approach; never echo the password.
3. Look up + add the **ASA API Utils** CurseForge mod ID to `MODS` (entrypoint already passes `-mods`). Record the ID in plan notes.
4. compose/env: add the plugin-config bind + any `ARKSHOP_DB_*` vars to `.env.*.example`.
5. Boot on dell; verify `ArkApi.log` has no `Singleton not found` and no DB connection error; run a points/shop action (RCON or in-game) and confirm a row appears in MariaDB.
6. README: add a "Shared store" section — plugin-config edit loop, how points/shop work, where the data lives.
**Acceptance criteria**:
- [ ] `ArkApi.log` shows ArkShop + Permissions loaded with NO `Singleton not found` and NO MySQL connection error
  - Evidence: (filled at phase completion)
- [ ] ArkShop/Permissions `config.json` on the volume has `UseMysql=true` + `MysqlHost=mariadb` + creds, written at boot from `.env` (password NOT present in git or container logs)
  - Evidence: (filled at phase completion)
- [ ] A points/shop action (e.g. RCON `AddPoints` or playtime accrual) persists a row to MariaDB — verified by querying the DB
  - Evidence: (filled at phase completion)
- [ ] Plugin `config.json` is edit-on-host (edit → restart → change takes effect) and is NOT clobbered by the boot sync
  - Evidence: (filled at phase completion)
- [ ] ASA API Utils mod ID recorded + the mod downloaded under the game's mods dir
  - Evidence: (filled at phase completion)
- [ ] README "Shared store" section added (config loop + data location)
  - Evidence: (filled at phase completion)
**Quality gate**:
- [ ] DB password injected at boot, never logged, never committed (placeholders in `.example`)
- [ ] Plugin config host-owned + seed-if-absent (no overwrite of operator edits)
- [ ] MariaDB reached via service name (internal network), not a host port
- [ ] Idempotent boot (re-run safe; config not duplicated)
- [ ] Handles missing/empty creds explicitly (fail fast, clear message — no half-configured shop)
**Verification**: `ENABLE_ASAAPI=1 docker compose --env-file .env.test up` on dell → `ArkApi.log` clean → RCON a points command → `docker compose exec mariadb mariadb -u arkshop -p arkshop -e 'SELECT * FROM <points table> LIMIT 5;'` shows the row.

**Phase Review Gates**:
- [ ] code-reviewer: <verdict + ISO timestamp>
- [ ] rules-compliance-reviewer: <verdict + ISO timestamp>
- [ ] plan-adherence-verifier: <verdict + ISO timestamp>
- [ ] acceptance-verifier: <verdict + ISO timestamp>
- [ ] design-compliance-reviewer: <verdict + ISO timestamp>
- [ ] Committed: <commit SHA>

## Quality Checklist (verify at completion)
- [ ] DB creds validated/handled at boot (fail fast on missing); no `any`-equivalent silent defaults
- [ ] Secrets only in gitignored `.env*`; entrypoint never logs the password; `.example` has placeholders
- [ ] MariaDB internal-only (no host port); reached via service name
- [ ] Error handling: entrypoint `set -euo pipefail` honored; markers gated on verified artifacts, not exit codes
- [ ] Idempotent entrypoint (plugin sync, VC++ install, config seed all re-runnable)
- [ ] No N/A — backups (world + DB) are explicitly M4 (accepted roadmap deferral)
- [ ] Existing M1 behavior preserved behind `ENABLE_ASAAPI=0` (rollback verified)
- [ ] Pinned plugin versions recorded; no auto-latest
- [ ] `build-time-vs-runtime.md` consistent with the code after Phase 3 (no rule/code contradiction)
- [ ] Every phase received all-reviewer + all-judge PASS before committing (Step 9a)
- [ ] Final cumulative reviewer sweep passed (Step 10f)
- [ ] Plan-file acceptance-criteria checkboxes accurate across all phases (Step 9b)
- [ ] ADRs 0001/0002 written; design-sources registry created

## Anti-Pattern Callouts

- **Splitting into commits instead of PRs**: each phase is a self-contained branch + commit/PR delivering one reviewable unit (DB / bake / VC++ / launch flip / ArkShop wiring) — not arbitrary commit slices of one giant change.
- **Shadow main branches**: phase branches are short-lived `feat/m2-<n>-*`, merged to `master` per phase; no long-running parallel main.
- **Building the engine before shipping value**: the milestone stops at a single working shop (no custom economy layer, no cluster); ArkShop-as-is IS the economy. The earliest shippable value (a working shop on one server) is exactly the milestone scope.
- **Hotfix that isn't**: no rushed launch flip without the prerequisites — VC++ (Phase 3) precedes the loader flip (Phase 4), each independently verified.
- **Abandoned branches**: 5 sequenced phases, each merged before the next starts (execute-plan gates commit on reviewer PASS); no orphan branches.
- **Flag graveyards**: `ENABLE_ASAAPI` is a deliberate, documented kill switch (not a temporary rollout flag); it's a permanent operational toggle (vanilla vs modded), so it has no cleanup deadline — its purpose is stated in `.env.*.example`.
