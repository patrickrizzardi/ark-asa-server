# Phase 5 runtime evidence — dell modded boot (2026-06-21)

Captured by driving the live stack on `dell` (10.1.4.4) over SSH: `ENABLE_ASAAPI=1`,
`mariadb:11.4` + `ark-asa:latest` (AsaApi 1.21 + ArkShop V1.4 + Permissions V1.1), map
`TheCenter_WP`. Two runtime bugs were found and fixed during this verification (commits
`042bef4` config-symlink DLL delete; `96e3813` Xvfb restart crash) — receipts below are post-fix.

## AC1 — ArkApi.log shows ArkShop + Permissions loaded, NO `Singleton not found`, NO MySQL error

**Command:** `grep -iE "loaded plugin|does not exist|singleton|loaded all|mysql|sql error" ArkApi_*.log`
**Output:**
```
[API][info] Loaded plugin Ark:SA ArkShop V1.4 (Shop, Currency & Kits)
[API][info] Loaded plugin Ark:SA Permissions V1.1 (Manage permissions groups)
[API][info] Loaded all plugins
```
No `does not exist`, no `Singleton not found`, no MySQL/sql error line present.
**Corroboration (DB connect):** ArkShop created its schema in MariaDB — `SHOW TABLES` in `arkshop` →
`ArkShopLogTransactions`, `ArkShopPlayers`. A plugin that didn't connect can't create tables.
**DLL present at the symlinked plugin dir:** `ArkApi/Plugins/ArkShop/ArkShop.dll` + `config.json`.
**Predicate met:** YES

## AC2 — config.json has UseMysql=true + MysqlHost=mariadb + creds, written at boot from .env, password not in git/logs

**Command:** `cat ArkApi/Plugins/ArkShop/config.json | python3 -m json.tool` (Mysql block, password redacted)
**Output:**
```
"UseMysql": true,
"MysqlHost": "mariadb",
"MysqlUser": "arkshop",
"MysqlPass": "***",
"MysqlDB": "arkshop",
"MysqlPort": 3306
```
Boot log: `[entrypoint] ArkShop DB config injected (host=mariadb, db=arkshop, user=arkshop).` — password
deliberately omitted from the log line. `.gitignore` excludes `plugins-config/**` (the injected file).
`git grep` over the repo finds no DB password. `MysqlPort` is an integer (jq `tonumber`).
**Predicate met:** YES

## AC3 — a points/shop action persists a row to MariaDB (verified by querying the DB)

**Before:** `SELECT Id,EosId,Points FROM ArkShopPlayers` -> `1, 00023ac1..., 0`
**Command:** `rcon -a 127.0.0.1:27020 -p *** "SetPoints 00023ac106e145b09e48d64ccd13f7d9 250"`
**RCON reply:** `Successfully set points`  (also `AddPoints <eosid> 100` -> `Successfully added points`)
**After:** `SELECT Id,EosId,Points FROM ArkShopPlayers` -> `1, 00023ac1..., 250`
The connected player (Patrick) confirmed the points in-game (in-game display refreshes on ArkShop's own
interval; the DB write was immediate). **Arg order is `<eosid> <amount>`** — `<amount> <eosid>` returns
"Couldn't add points".
**Predicate met:** YES

## AC4 — plugin config.json is edit-on-host (edit -> restart -> takes effect) AND not clobbered by the boot sync

**Command:** add a marker on the host (`plugins-config/ArkShop/config.json` <- `_phase5_edit_test`) ->
`docker compose restart the-island` -> re-read the host file.
**Output:** `_phase5_edit_test = survives-reboot` (marker intact after restart); `grep -c "Loaded plugin"` = 2
(both plugins still loaded). Seed-if-absent never overwrites an existing host config; `inject` only rewrites
the `.Mysql.*` keys (creds from `.env`), so operator edits to other keys persist. Takes-effect is also proven
by the injected `UseMysql=true` being read by ArkShop (it connected). Marker removed after the check.
**Predicate met:** YES

## AC5 — ASA API Utils mod ID recorded + the mod loaded

**Recorded:** `955333` in `notes.md`, `README.md`, and `entrypoint.sh` (auto-appended to `MODS` when
`ENABLE_ASAAPI=1`, de-duped).
**Launch line:** `... -NoBattlEye -mods=955333` (from container logs).
**Loaded:** the absence of `Singleton not found` in ArkApi.log (AC1) is ASA API Utils being present — that
warning is exactly what fires when the mod is missing.
**Predicate met:** YES

## AC6 — README "Shared store" section (config loop + data location)

**Command:** `grep -n "^## Shared store" README.md` -> present (config-edit loop + DB data location documented).
**Predicate met:** YES (static)

## Bonus — restart resilience (config-loop requirement, fixed in `96e3813`)

`docker compose restart the-island` (the config-edit loop) on the modded server: clean boot OK ~72s ->
**restart survived, started ~66s, "Up", still Up after settle** (was a crash loop before the Xvfb stale-lock fix).
