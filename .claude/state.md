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

```bash
# Local fast-test boot
docker compose --env-file .env.test up --build
# Config loop: edit ./config/GameUserSettings.ini, then
docker compose restart the-island
# Stop
docker compose down
```

**HOST PREREQ (or the server crash-loops with exit code 21):** `vm.max_map_count >= 262144`
must be set on the host kernel (see Active Decisions).

---

## Active Decisions (append with WHY)

- [2026-06-20] **Image = immutable stack only; game installs at runtime onto a volume**: per `.claude/rules/build-time-vs-runtime.md`. Baking the ~30GB game into the image would force a rebuild every ASA patch. Image holds SteamCMD/GE-Proton/rcon/tini; game + Proton prefix live on the `ark-game` volume, installed by the entrypoint (skip-validate after first install = fast boot).
- [2026-06-20] **Prod/test env profiles; BattlEye is a toggle**: `.env.test` = fast boot + instant kill + anti-cheat OFF; `.env.prod` = update-on-boot + SaveWorld + BattlEye ON. Splitting them caught that the entrypoint had `-NoBattlEye` hardcoded — prod would otherwise have shipped a cheatable PvP server. (This is the env note Patrick asked to record.)
- [2026-06-20] **M1 single-server: no shared volumes yet**: sharing only earns its keep with a 2nd consumer. `steam` / cluster / MySQL / shared-config sharing arrives additively in M2/M3 (per-server game volume + shared steam + shared cluster + MySQL) — no teardown. Avoids speculative single-consumer "shared" volumes.
- [2026-06-20] **Host requires `vm.max_map_count >= 262144`**: ASA exceeds the Linux default (65530) → exit-code-21 crash-loop ~1s after launch, before map load. Non-namespaced kernel param, can't be set in-container — so a privileged `sysctl` init service in compose writes it to the HOST kernel before the server boots, automatically on every host (WSL + VPS). Manual `/etc/sysctl.conf` is the fallback if a host blocks privileged containers.

---

## Superseded / Archived

- (none)

---

## Project-Wide Notes

*(cross-workstream context, gotchas, user preferences not tied to one plan)*

- **#1 startup gotcha**: `vm.max_map_count >= 262144` — now auto-applied by the `sysctl` init service in compose (see Active Decisions), so WSL + VPS are both covered without a manual step.
- **WSL2 client join**: enable `networkingMode=mirrored` in `.wslconfig` to join from the Windows ARK client; logs/RCON work regardless. Direct-connect via console `open localhost:7777`.
- **Informal roadmap**: M1 lean fast image (current) → M2 AsaApi + ArkShop + MySQL **shared store** (the thing Nitrado can't do — needs a real `/plan` + an ADR for the shared-economy schema) → M3 cluster (store shared across maps) → M4 config tooling / backups / TS CLI → VPS deploy. Real PvP server lives on a VPS; WSL stays the config sandbox.
- **Process note**: M1 was built as a fast casual slice (no formal `/plan`), so the plan's Documentation-Impact step was skipped — acceptable at M1's "small tool → README" doc tier. M2 is multi-service + has hard-to-reverse schema decisions → run full `/plan` (incl. docs step + ADR) before building it.
