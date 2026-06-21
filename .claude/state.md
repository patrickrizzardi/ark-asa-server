# Session State: ark-asa

**Last Updated**: 2026-06-20

---

## Radar — Roadmaps & Active Workstreams

*(auto-rebuilt by SessionStart hook from `.claude/plans/active/**` plan front-matter — each plan's `{slug}/plan.md` and each initiative's `roadmap.md` — do not edit by hand)*

<!-- RADAR-START -->
### Active Roadmaps
- ark-asa-server (Patrick) — 1 plans — 2026-06-20

### Active Workstreams
- [ark-asa-server] initiative
  - m2-shared-economy-store (Patrick) — 9 files touched — 72/102 done — roadmap: ark-asa-server — 2026-06-21
<!-- RADAR-END -->

---

## Environment & Commands (CRITICAL — survives compaction)

**Project**: ark-asa — lean self-hosted ARK: Survival Ascended server (Docker + GE-Proton)
**Package Manager**: n/a (Docker)
**Container**: yes — `docker compose --env-file .env.test up` (test) / `.env.prod` (prod/VPS)
**Database**: none yet (MySQL arrives in M2 for the shared store)

**Test box**: `dell` (10.1.4.4, bare-metal Ubuntu 22.04, 8 cores, 64GB) at `~/ark-asa-server`.
SSH in to operate; the repo is a clone of this one (push to GitHub to sync both ways).

```bash
# Boot (reads ./.env — currently the test profile). First boot installs ~13GB once.
docker compose up --build
# Config loop: edit ./config/GameUserSettings.ini, then (fast boot, ~20s, no re-download)
docker compose restart the-island
# Debug a crash: surface the real Wine fault instead of -all
WINEDEBUG=+err,+seh docker compose up
# Stop
docker compose down
```

**VERIFIED WORKING on dell (2026-06-20)**: `Server "ARK-Test" has successfully started!` →
`Full Startup: ~20s` → `advertising for join (10.33GB Mem)`, port 7777/udp bound. Restart loop
confirmed fast-boot (skips Steam).

**HOST PREREQ**: `vm.max_map_count >= 262144` — auto-applied by the compose `sysctl` service.

---

## Active Decisions (append with WHY)

- [2026-06-21] **M2 shared-economy store — DONE pending final flip; modded ArkShop economy verified LIVE on dell**: `ENABLE_ASAAPI=1` launches AsaApiLoader → AsaApi 1.21 + ArkShop V1.4 + Permissions V1.1 load; ArkShop connects to MariaDB (`mariadb:11.4`, `mariadb:3306` service name, `mysql_native_password`) and creates its schema; RCON `SetPoints <eosid> <amount>` persists a row (verified Points 0→250 + in-game); edit-on-host plugin config survives restart; `ENABLE_ASAAPI=0` = byte-for-byte M1 vanilla rollback. All 6 Phase-5 ACs + 22/22 cumulative ACs MET; full cumulative sweep all-green. Plugin config = host bind `./plugins-config/<Plugin>/config.json` (entrypoint symlinks the FILE only, re-injects the `.Mysql` block from `.env` each boot). ASA API Utils mod **955333** auto-appended to `-mods` when modded.
- [2026-06-21] **Two runtime bugs the dell gate caught (not the static reviewers)**: (1) `setup_plugin_configs` symlinked the whole plugin dir → deleted `ArkShop.dll` ("Plugin does not exist"); fix = symlink only `config.json`. (2) Modded server crash-looped on `docker compose restart` — stale `/tmp` Xvfb lock+socket raced `kill -0` into a false-pass → loader launched against a dead display; fix = `rm -f /tmp/.X0-lock /tmp/.X11-unix/X0` before Xvfb. Lesson: the config-loop `restart` path MUST be runtime-tested, not just `up -d`.
- [2026-06-21] **deploy_plugins derives its root-artifact set from `/opt/asaapi/*`** (not hand-listed rm+cp): a version bump that adds/drops a root DLL is picked up automatically; entrypoint can't drift from the Dockerfile bake. (Closed M2 cumulative code-review concern #1.)
- [2026-06-21] **dell operational facts**: DataGrip → ark-asa DB via gitignored `docker-compose.override.yml` publishing `mariadb` on host port **3307** (3306 is taken by an unrelated `mifi-mysql` MySQL-8.4 container — THAT was the source of the `sha256_password` DataGrip error, not the ark-asa DB). Use the **MariaDB** driver. ArkShop UI = MX-E Ark Shop UI / "official ArkShopUI Ascended" = CurseForge mod **942249**; `MODS=942249` in dell `.env` → `-mods=942249,955333`. Committed compose stays internal-only (no host port) for prod.
- [2026-06-20] **Image = immutable stack only; game installs at runtime onto a volume**: per `.claude/rules/build-time-vs-runtime.md`. Baking the ~30GB game into the image would force a rebuild every ASA patch. Image holds SteamCMD/GE-Proton/rcon/tini; game + Proton prefix live on the `ark-game` volume, installed by the entrypoint (skip-validate after first install = fast boot).
- [2026-06-20] **Prod/test env profiles; BattlEye is a toggle**: `.env.test` = fast boot + instant kill + anti-cheat OFF; `.env.prod` = update-on-boot + SaveWorld + BattlEye ON. Splitting them caught that the entrypoint had `-NoBattlEye` hardcoded — prod would otherwise have shipped a cheatable PvP server. (This is the env note Patrick asked to record.)
- [2026-06-20] **M1 single-server: no shared volumes yet**: sharing only earns its keep with a 2nd consumer. `steam` / cluster / MySQL / shared-config sharing arrives additively in M2/M3 (per-server game volume + shared steam + shared cluster + MySQL) — no teardown. Avoids speculative single-consumer "shared" volumes.
- [2026-06-20] **Host requires `vm.max_map_count >= 262144`**: ASA exceeds the Linux default (65530) → exit-code-21 crash-loop ~1s after launch, before map load. Non-namespaced kernel param, can't be set in-container — so a privileged `sysctl` init service in compose writes it to the HOST kernel before the server boots, automatically on every host (WSL + VPS). Manual `/etc/sysctl.conf` is the fallback if a host blocks privileged containers.
- [2026-06-20] **THE exit-21 root cause was missing `steamclient.so`, NOT WSL2**: Proton's `lsteamclient` loads the native Steam client from `~/.steam/sdk{64,32}/steamclient.so` at launch; without it the server asserts in `steamclient_main.c:375` and aborts (exit 21), right after Sentry init. The `parkervcp/steamcmd:proton` base does NOT bundle it. Fix: Dockerfile runs `steamcmd +login anonymous +quit` at build to bake `linux{32,64}/steamclient.so` into the image; entrypoint symlinks `~/.steam/sdk{64,32}/steamclient.so` to them each boot (`~/.steam` is ephemeral, not on the volume). **WSL2 was exonerated** — the crash reproduced identically on bare-metal dell with a complete install + correct max_map_count. (`WINEDEBUG=+err,+seh` surfaced the assertion; `-all` hid it.)
- [2026-06-20] **Config bind is SHALLOW + symlinked, not a deep bind**: binding `./config` directly into `…/ShooterGame/Saved/Config/WindowsServer` made Docker root-create the volume's intermediate dirs, blocking the non-root `container` user from writing `Logs`/saves (silent first-boot crash on a fresh volume). Now: bind `./config` → `/home/container/config` (shallow), entrypoint creates the dir chain as the container user and symlinks `WindowsServer` → the host mount. Edit-on-host loop preserved; ASA writes `GameUserSettings.ini` back through the link (verified).
- [2026-06-20] **ASA needs the Windows depot + a trustworthy install marker**: app 2430930 ships Windows-only, so steamcmd on Linux needs `+@sSteamCmdForcePlatformType windows` before `+login` or it fails with "Missing configuration". And steamcmd exits 0 even when `app_update` fails, so the `.installed` marker is gated on the server exe actually existing — otherwise a partial download falsely marks "installed", fast-boot skips repair, and the server crashes.
- [2026-06-21] **AsaApi loads under GE-Proton — M2 core unknown ANSWERED (Phase 4, commit 4f19274)**: launch flips `ArkAscendedServer.exe` → `AsaApiLoader.exe` behind `ENABLE_ASAAPI` (1=modded default, 0=byte-for-byte vanilla rollback, no rebuild). Proven on dell: AsaApi 1.21 + ArkShop V1.4 + Permissions V1.1 load, server advertises for join. THREE non-obvious requirements found only by the first real build/boot — (1) the `steamcmd:proton` base lacks `unzip` (added apt layer; Phase 2's static probe ran unzip on the host, not in-image — graveyard candidate); (2) `AsaApiLoader.exe` creates a Win32 window so it needs a real X display (Xvfb in the loader branch, socket+`kill -0` liveness guarded) — vanilla stays headless via SDL dummy; (3) **AsaApi requires `ArkAscendedServer.pdb`** (SHA-256'd to key its symbol-offset cache) — the M1 pdb-shed optimization broke it → keep pdb when modded + self-healing `ensure_modded_pdb()` (steamcmd-validate restore, size-floored). `WINEDEBUG=+err,+seh` surfaced the Xvfb fault.
- [2026-06-21] **ASA API Utils CurseForge mod ID = 955333**: discovered via ArkShop's optional-mod warning during Phase 4. Needed for Phase 5 (`MODS=` → `-mods=`); without it ArkShop logs "AsaApiUtils singleton not found" and falls back to default messaging.

---

## Superseded / Archived

- (none)

---

## Project-Wide Notes

*(cross-workstream context, gotchas, user preferences not tied to one plan)*

- **exit-21 is a generic ASA early-abort** — it has *multiple* causes (too-low `vm.max_map_count`, missing `steamclient.so`, partial install). Both the map_count and steamclient causes are now handled in-image/compose. When it recurs, `WINEDEBUG=+err,+seh` is the move — it names the real Wine fault that `-all` hides.
- **WSL2 client join**: enable `networkingMode=mirrored` in `.wslconfig` to join from the Windows ARK client; logs/RCON work regardless. Direct-connect via console `open localhost:7777`.
- **Informal roadmap**: M1 lean fast image (current) → M2 AsaApi + ArkShop + MySQL **shared store** (the thing Nitrado can't do — needs a real `/plan` + an ADR for the shared-economy schema) → M3 cluster (store shared across maps) → M4 config tooling / backups / TS CLI → VPS deploy. Real PvP server lives on a VPS; WSL stays the config sandbox.
- **Process note**: M1 was built as a fast casual slice (no formal `/plan`), so the plan's Documentation-Impact step was skipped — acceptable at M1's "small tool → README" doc tier. M2 is multi-service + has hard-to-reverse schema decisions → run full `/plan` (incl. docs step + ADR) before building it.

- **PLANNING IN PROGRESS (2026-06-20): M2 `m2-shared-economy-store`** (initiative child of `ark-asa-server`). Research done; awaiting Patrick's OK on a 5-phase shape, then writing `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md` + plan-reviewer. Key research findings:
  - **AsaApi pinned = v1.21** (Apr 2026). Installs to `ShooterGame/Binaries/Win64`; plugins → `Win64/ArkApi/Plugins/<name>/` (DLL name must match folder); log at `ShooterGame/Win64/logs/ArkApi.log`. Launch `AsaApiLoader.exe` w/ same params as `ArkAscendedServer.exe`. **Requires MS VC++ 2019 redist.**
  - **Two build-vs-runtime tensions, both resolved the same rule-faithful way** (prefix AND `Win64` live on the `ark-game` volume, so by the rule's 3-question test → runtime/entrypoint, not Dockerfile): (a) **VC++ redist** installs in the container at runtime (bake the `.exe` in `/opt`, entrypoint runs it into the volume prefix, marker-guarded) — Patrick's explicit call, own phase; (b) **plugins** bake to `/opt/asaapi/` in the image (pinned) and the entrypoint syncs them onto the volume's `Win64` each boot (same pattern as `steamclient.so`). Phase 3 also **amends `build-time-vs-runtime.md`** so its table matches the volume-backed-prefix reality.
  - **ArkShop** deps: **Permissions** plugin (baked) + **ASA API Utils** CurseForge *mod* (rides existing `MODS=` → needs its mod ID at exec; absence = `Singleton not found`). Config `Mysql` block: `UseMysql/MysqlHost/User/Pass/DB/Port`. **MySQL 8.0.28+ rejected; MariaDB any version** → propose `mariadb:11.4` LTS.
  - Proposed phases: 1 MariaDB svc+secrets · 2 bake plugins (/opt + sync) · 3 VC++ in container (+rule amend) · 4 flip→AsaApiLoader (AsaApi loads = HIGH-risk gate) · 5 ArkShop↔MariaDB end-to-end (HIGH). Plugin-binary distribution channel (GitHub releases vs auth-gated ark-server-api.com) = open exec risk for Phase 2.
- **WHERE WE LEFT OFF (2026-06-20)**: **M1 DONE — server boots and advertises on `dell`.** The exit-21 blocker was NOT WSL2 (exonerated): it was missing `steamclient.so` for Proton's lsteamclient (see Active Decisions). Four real bugs fixed this session: (1) missing steamclient.so → bake at build + symlink at boot; (2) deep config bind root-owning the volume → shallow bind + symlink; (3) missing `+@sSteamCmdForcePlatformType windows` → "Missing configuration"; (4) install marker trusting steamcmd's lying exit code → gate on the exe existing. All four are in Dockerfile/entrypoint/compose. Verified: full startup ~20s, advertising, port bound, fast-boot restart loop works, config writes through to host `./config`.
  - **Image ownership / leanness (RESOLVED)**: keeping `FROM parkervcp/steamcmd:proton` as-is. Patrick cares about RAM/CPU, not image MB — a bookworm-slim/from-scratch base only trims disk, not runtime RAM/CPU (the cost is GE-Proton + Wine + the game, identical regardless of base). Not worth the rebuild.
  - **NEXT (M2)**: AsaApi + ArkShop + MySQL shared store — run full `/plan` + ADR before building (multi-service, hard-to-reverse schema). When AsaApi lands, launch `AsaApiLoader.exe` (not `ArkAscendedServer.exe`) per `build-time-vs-runtime.md`.
  - **Not yet committed**: the 4 fixes are in the working tree on both boxes (uncommitted). Commit when ready. README still has the old "30GB" figure (real install ~13GB) — refresh on next pass.
