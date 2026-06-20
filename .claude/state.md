# Session State: ark-asa

**Last Updated**: 2026-06-20

---

## Radar — Roadmaps & Active Workstreams

*(auto-rebuilt by SessionStart hook from `.claude/plans/active/**` plan front-matter — each plan's `{slug}/plan.md` and each initiative's `roadmap.md` — do not edit by hand)*

<!-- RADAR-START -->
### Active Roadmaps
*(no active roadmaps)*

### Active Workstreams
*(no active workstreams)*
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

- [2026-06-20] **Image = immutable stack only; game installs at runtime onto a volume**: per `.claude/rules/build-time-vs-runtime.md`. Baking the ~30GB game into the image would force a rebuild every ASA patch. Image holds SteamCMD/GE-Proton/rcon/tini; game + Proton prefix live on the `ark-game` volume, installed by the entrypoint (skip-validate after first install = fast boot).
- [2026-06-20] **Prod/test env profiles; BattlEye is a toggle**: `.env.test` = fast boot + instant kill + anti-cheat OFF; `.env.prod` = update-on-boot + SaveWorld + BattlEye ON. Splitting them caught that the entrypoint had `-NoBattlEye` hardcoded — prod would otherwise have shipped a cheatable PvP server. (This is the env note Patrick asked to record.)
- [2026-06-20] **M1 single-server: no shared volumes yet**: sharing only earns its keep with a 2nd consumer. `steam` / cluster / MySQL / shared-config sharing arrives additively in M2/M3 (per-server game volume + shared steam + shared cluster + MySQL) — no teardown. Avoids speculative single-consumer "shared" volumes.
- [2026-06-20] **Host requires `vm.max_map_count >= 262144`**: ASA exceeds the Linux default (65530) → exit-code-21 crash-loop ~1s after launch, before map load. Non-namespaced kernel param, can't be set in-container — so a privileged `sysctl` init service in compose writes it to the HOST kernel before the server boots, automatically on every host (WSL + VPS). Manual `/etc/sysctl.conf` is the fallback if a host blocks privileged containers.
- [2026-06-20] **THE exit-21 root cause was missing `steamclient.so`, NOT WSL2**: Proton's `lsteamclient` loads the native Steam client from `~/.steam/sdk{64,32}/steamclient.so` at launch; without it the server asserts in `steamclient_main.c:375` and aborts (exit 21), right after Sentry init. The `parkervcp/steamcmd:proton` base does NOT bundle it. Fix: Dockerfile runs `steamcmd +login anonymous +quit` at build to bake `linux{32,64}/steamclient.so` into the image; entrypoint symlinks `~/.steam/sdk{64,32}/steamclient.so` to them each boot (`~/.steam` is ephemeral, not on the volume). **WSL2 was exonerated** — the crash reproduced identically on bare-metal dell with a complete install + correct max_map_count. (`WINEDEBUG=+err,+seh` surfaced the assertion; `-all` hid it.)
- [2026-06-20] **Config bind is SHALLOW + symlinked, not a deep bind**: binding `./config` directly into `…/ShooterGame/Saved/Config/WindowsServer` made Docker root-create the volume's intermediate dirs, blocking the non-root `container` user from writing `Logs`/saves (silent first-boot crash on a fresh volume). Now: bind `./config` → `/home/container/config` (shallow), entrypoint creates the dir chain as the container user and symlinks `WindowsServer` → the host mount. Edit-on-host loop preserved; ASA writes `GameUserSettings.ini` back through the link (verified).
- [2026-06-20] **ASA needs the Windows depot + a trustworthy install marker**: app 2430930 ships Windows-only, so steamcmd on Linux needs `+@sSteamCmdForcePlatformType windows` before `+login` or it fails with "Missing configuration". And steamcmd exits 0 even when `app_update` fails, so the `.installed` marker is gated on the server exe actually existing — otherwise a partial download falsely marks "installed", fast-boot skips repair, and the server crashes.

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

- **WHERE WE LEFT OFF (2026-06-20)**: **M1 DONE — server boots and advertises on `dell`.** The exit-21 blocker was NOT WSL2 (exonerated): it was missing `steamclient.so` for Proton's lsteamclient (see Active Decisions). Four real bugs fixed this session: (1) missing steamclient.so → bake at build + symlink at boot; (2) deep config bind root-owning the volume → shallow bind + symlink; (3) missing `+@sSteamCmdForcePlatformType windows` → "Missing configuration"; (4) install marker trusting steamcmd's lying exit code → gate on the exe existing. All four are in Dockerfile/entrypoint/compose. Verified: full startup ~20s, advertising, port bound, fast-boot restart loop works, config writes through to host `./config`.
  - **Image ownership / leanness (RESOLVED)**: keeping `FROM parkervcp/steamcmd:proton` as-is. Patrick cares about RAM/CPU, not image MB — a bookworm-slim/from-scratch base only trims disk, not runtime RAM/CPU (the cost is GE-Proton + Wine + the game, identical regardless of base). Not worth the rebuild.
  - **NEXT (M2)**: AsaApi + ArkShop + MySQL shared store — run full `/plan` + ADR before building (multi-service, hard-to-reverse schema). When AsaApi lands, launch `AsaApiLoader.exe` (not `ArkAscendedServer.exe`) per `build-time-vs-runtime.md`.
  - **Not yet committed**: the 4 fixes are in the working tree on both boxes (uncommitted). Commit when ready. README still has the old "30GB" figure (real install ~13GB) — refresh on next pass.
