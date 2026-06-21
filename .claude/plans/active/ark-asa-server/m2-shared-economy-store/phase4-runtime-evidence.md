````markdown
# Phase 4 runtime evidence — 2026-06-21T02:44Z

Captured on **dell** (bare-metal Ubuntu 22.04.5, Docker 24.0.7, compose v2.21.0) — the only box
that can boot the real ASA-under-Proton stack. This is the milestone's core gate: it is the FIRST
real `docker build` + boot of the full modded stack (Phase 2 plugins + Phase 3 VC++ + this phase's
loader flip), so it also collected the runtime receipts the prior phases deferred to "Phase 4/dell".

Branch tested: `feat/m2-4-asaapi-loader`. The behavior-affecting files (`entrypoint.sh`,
`docker-compose.yml`, `Dockerfile`) were verified byte-identical (`git hash-object`) between the
local working tree and dell at capture time.

Image: `ark-asa:latest` (sha `5a83628ac1df`). Game volume `ark-game` pre-populated from M1.

---

## Integration-gate defects found + fixed (all surfaced ONLY by a real build/boot)

Three issues blocked AsaApi from loading; none were visible to the prior phases' static-evidence
ceiling. Each fix + its proof is below, then the three ACs.

### Defect 1 — base image lacks `unzip` (Phase 2 Dockerfile, fixed here)
`docker build` failed at the plugin-download step:
```
#7 1.890 /bin/sh: 1: unzip: not found
#7 ERROR: process "/bin/sh -c ... unzip -q /tmp/asaapi.zip ..." did not complete successfully: exit code: 127
```
The `ghcr.io/parkervcp/steamcmd:proton` base ships curl/tar but not unzip; Phase 2's "coordinator
probe" ran `unzip -l` on a host that HAD unzip, never inside the image build. **Fix:** added an
`apt-get install -y --no-install-recommends unzip` layer after `USER root` (Dockerfile). Build then
succeeded — AsaApi 1.21 + ArkShop 1.4 baked, VC++ redist baked.

### Defect 2 — AsaApiLoader needs an X display (Phase 4 entrypoint, fixed here)
With the build fixed, the container restart-looped. `WINEDEBUG=+err,+seh` surfaced the fault:
```
err:winediag:nodrv_CreateWindow Application tried to create a window, but no driver could be loaded.
err:winediag:nodrv_CreateWindow L"The explorer process failed to start."
err:winediag:nodrv_CreateWindow L"Make sure that your display server is running..."
→ EXCEPTION_WINE_CXX_EXCEPTION → raise(22)   [abort]
```
The vanilla server runs headless via `SDL_VIDEODRIVER=dummy`, but `AsaApiLoader.exe` creates a real
Win32 window (Wine x11 driver) during init → with no `DISPLAY`, Wine aborts. **Fix:** the loader
branch starts `Xvfb :0` + exports `DISPLAY=:0` (with an X-socket readiness wait) before `proton run`;
the vanilla branch is untouched (stays byte-for-byte M1). Both `Xvfb`/`xvfb-run` are already in the
base image.

### Defect 3 — AsaApi requires `ArkAscendedServer.pdb` (M1 optimization conflict, fixed here)
With Xvfb the server started, but the AsaApi log showed it loading ZERO plugins:
```
[API][info] ARK:SA Api V1.21 ... Loading...
[API][error] Error opening file for SHA-256 calculation: ...\ArkAscendedServer.pdb
[API][warning] Ooops you are early, the cache has not finished cooking yet! ...
[API][critical] Failed to read pdb - Failed to open pdb file
```
AsaApi SHA-256's `ArkAscendedServer.pdb` to derive its offset-cache key, then loads/validates the
cached server symbol offsets it needs to hook the server. The M1 entrypoint deleted the pdb at
install (entrypoint.sh:43) to shed disk → AsaApi couldn't compute the key → couldn't fetch/process
the cache → `[critical]` → no plugins. (The pdb IS in the depot; a steamcmd `validate` restored it
at ~2.0 GB. A first attempt bailed on a transient `Update state (0x0): Timed out waiting for update
to start` — a retry loop cleared it.) **Fix:** entrypoint no longer sheds the pdb when
`ENABLE_ASAAPI=1`; vanilla still sheds it. One-time data restore done on dell's existing volume.

---

## AC1 — With ENABLE_ASAAPI=1, AsaApi initializes (no fatal load error)

After the pdb restore, the AsaApi framework log (`Win64/logs/ArkApi_<pid>_<ts>.log` — note v1.21
names it `ArkApi_<pid>_<date>.log`, not a fixed `ArkApi.log`) shows a clean load:
```
[API][info] Cache files downloaded and processed successfully
[API][info] Reading cached offsets
[API][info] Initialized hooks
[API][info] API was successfully loaded
[API][info] Loading plugins..
[API][info] Loaded plugin Ark:SA ArkShop V1.4 (Shop, Currency & Kits)
[API][info] Loaded plugin Ark:SA Permissions V1.1 (Manage permissions groups)
[API][info] Loaded all plugins
```
Offset cache populated on the volume: `ArkApi/Cache/cached_offsets.cache` (47 MB),
`cached_bitfields.cache` (941 KB), `cached_key.cache`.

The only warning is the **explicitly Phase-5-deferred** optional mod:
```
[API][warning] [OPTIONAL MOD MISSING] 'AsaApiUtils' (Mod ID: 955333) not available for 'ArkShop.dll'.
               Falling back to default messaging system. Reason: The 'AsaApiUtils' singleton could not be found.
```
Per Phase 4 Scope Boundary, ArkShop's Singleton/DB error is acceptable this phase (Phase 5 wires
ASA API Utils + MariaDB). **Bonus:** this revealed the ASA API Utils CurseForge **mod ID = 955333**
that Phase 5 needs.

**Predicate met:** YES — `API was successfully loaded`, both plugins loaded, no critical/fatal error.

## AC2 — Server reaches "successfully started" / advertises for join (under the loader)

ENABLE_ASAAPI=1 boot, container `Up` (not restarting):
```
[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [AsaApiLoader — modded, Xvfb :0]
[2026.06.21-02.39...] Server: "ARK-Test" has successfully started!
[2026.06.21-02.39...] Server has completed startup and is now advertising for join. (10.29GB Mem)
```
(An earlier modded boot logged `Full Startup: 47.73 seconds`.)

**Predicate met:** YES — started + advertising for join, under `AsaApiLoader.exe`.

## AC3 — With ENABLE_ASAAPI=0, launch is the M1 vanilla path (rollback, no rebuild)

`ENABLE_ASAAPI=0 docker compose up -d` (same image, no rebuild):
```
[entrypoint] Launching TheIsland_WP on :7777 (rcon :27020) [vanilla]
[2026.06.21-02.42.16:666][ 5]Server: "ARK-Test" has successfully started!
[2026.06.21-02.42.20:195][ 5]Full Startup: 48.05 seconds
[2026.06.21-02.42.33:280][210]Server has completed startup and is now advertising for join. (10.35GB Mem)
```
AsaApi-loaded count this boot: `0` (grep `"API was successfully loaded"` → 0). Vanilla branch sets
`launch_exe="${SERVER_EXE}"` (`ArkAscendedServer.exe`), skips Xvfb, reuses identical `${query}`/`${flags}`.

**Predicate met:** YES — vanilla launch via env flip only, server starts, AsaApi absent.

---

## Reproduce
```
# modded (default):  ENABLE_ASAAPI=1 (default in .env / compose / entrypoint)
docker compose up -d
docker run --rm -v ark-game:/g busybox sh -c 'cat /g/ShooterGame/Binaries/Win64/logs/ArkApi_*.log'
# vanilla rollback:
ENABLE_ASAAPI=0 docker compose up -d   # → [vanilla] launch, no AsaApi
```
````

---

## Round-2 fix verification (2026-06-21T03:01Z) — pdb self-heal + Xvfb fail-fast

Round-1 gate BLOCKed three items (pdb gated at install-marker not launch gate; Xvfb readiness loop
was a timing-only guard; main() missing Big-O). Fixes landed in `entrypoint.sh` and were re-verified
on dell.

**pdb self-heal (the milestone-critical fix) — tested by deleting the pdb to simulate a
vanilla-shed volume, then booting modded:**
```
[entrypoint] ENABLE_ASAAPI=1 but pdb is absent — restoring via steamcmd validate…
[entrypoint] steamcmd validate attempt 1/3…
[entrypoint] pdb restored on attempt 1.
...
[API][info] API was successfully loaded
[API][info] Loaded plugin Ark:SA ArkShop V1.4 (Shop, Currency & Kits)
[API][info] Loaded plugin Ark:SA Permissions V1.1 (Manage permissions groups)
[API][info] Loaded all plugins
[2026.06.21-03.01.21] Server: "ARK-Test" has successfully started!
```
`ensure_modded_pdb()` detected the absent pdb, restored it via steamcmd validate (1 attempt), and
AsaApi then loaded cleanly — no manual intervention. The manual `steamcmd validate` step the
original evidence noted is now automated and removed.

**Xvfb fail-fast:** post-readiness-loop socket check added; the happy path still boots (proven by the
self-heal boot above reaching "successfully started" under the loader). A failed Xvfb bind now exits 1
with a clear message instead of launching into a silent nodrv_CreateWindow abort.
