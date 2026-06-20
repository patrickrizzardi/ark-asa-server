# Capability Ledger: ARK ASA Self-Hosted Server

| Capability | Owning milestone | Status | Notes |
|---|---|---|---|
| Lean fast-boot ASA image (GE-Proton, non-root, runtime game install) | m1-lean-image | done | Shipped 2026-06-20 |
| `vm.max_map_count` sysctl init service | m1-lean-image | done | |
| Baked `steamclient.so` + SDK symlinks (Proton lsteamclient) | m1-lean-image | done | Was the exit-21 root cause |
| Edit-on-host server config loop (`GameUserSettings.ini`) | m1-lean-image | done | Shallow `./config` bind + symlink |
| Prod/test env profiles; BattlEye toggle | m1-lean-image | done | |
| AsaApi loader baked into image at pinned version | m2-shared-economy-store | planned | |
| Launch flips to `AsaApiLoader.exe` (not `ArkAscendedServer.exe`) | m2-shared-economy-store | planned | |
| VC++ 2019 redist installed in the Proton prefix | m2-shared-economy-store | planned | AsaApi dependency |
| ArkShop plugin baked into image at pinned version | m2-shared-economy-store | planned | |
| Permissions plugin baked into image (ArkShop dependency) | m2-shared-economy-store | planned | |
| Self-contained MariaDB service in compose | m2-shared-economy-store | planned | Engine locked = MariaDB (ArkShop rejects MySQL 8.0.28+) |
| ArkShop configured against MariaDB (shared store) | m2-shared-economy-store | planned | `UseMysql=true`, host/user/pass/db/port |
| Edit-on-host plugin config (ArkShop `config.json`, etc.) | m2-shared-economy-store | planned | Binaries in image, config on volume |
| DB secrets via `.env`; entrypoint writes ArkShop config at boot | m2-shared-economy-store | planned | |
| Pinned plugin versions (rebuild-to-update) | m2-shared-economy-store | planned | Named tradeoff |
| Multi-server (2+ maps) pointing at the shared MariaDB economy | m3-cluster | planned | Designed seam left open by M2 |
| ASA native cluster transfer (characters/dinos/items between maps) | m3-cluster | planned | `-clusterid` + shared cluster save dir |
| Shared cluster save directory volume | m3-cluster | planned | |
| Per-map game/config volumes + shared cluster volume layout | m3-cluster | planned | |
| Shared config across cluster (`Game.ini`, `GameUserSettings.ini`) | m3-cluster | planned | One canonical copy used by every server; builds on M2's config-on-volume seam |
| Shared plugin configs across cluster (ArkShop `config.json`, Permissions) | m3-cluster | planned | Identical shop catalog/permissions on every map |
| Per-server config overrides (map, ports, `SessionName`) | m3-cluster | planned | The few keys that must differ per map; merge/override mechanism = M3 open question |
| TypeScript interactive menu-driven ops CLI (no flags, auto-routes) | m4-ops-tooling | planned | reboot/save/RCON/backup/restore via a "what are you here for?" wizard |
| Backups: world saves (`.ark`) | m4-ops-tooling | planned | |
| Backups: economy DB (mysqldump) | m4-ops-tooling | planned | DB unbacked between M2 ship and M4 — accepted |
| DB admin web UI (Adminer) for browsing balances | m4-ops-tooling | planned | Optional polish |
| Custom economy layer (website / Discord bot / dashboard / trading) | unscoped — needs a milestone | NEEDS-PLANNED | Additive on the same MariaDB; only if Patrick wants it. Not in M2/M3/M4 |
