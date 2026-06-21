# ark-asa

Lean self-hosted **ARK: Survival Ascended** dedicated server. Runs the Windows server
binary on Linux via GloriousEggroll's Proton-GE, in Docker. Built for **fast boot** so you
can iterate config locally instead of waiting on a managed host's 5–10 min restarts.

Same image runs your **local config sandbox** (WSL) and your **prod server** (a VPS).

## Host kernel setting (handled automatically)

ASA needs `vm.max_map_count >= 262144` or it crash-loops with **exit code 21** ~1s after
launch. The compose stack sets this for you via a tiny privileged `sysctl` init service that
runs before the server on every `up` — on any Linux host (WSL or VPS), no manual step.

Fallback, if your host blocks privileged containers (e.g. rootless Docker):

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
```

## Run

```bash
cp .env.test.example .env.test     # set ARK_ADMIN_PASSWORD
docker compose --env-file .env.test up --build
```

First boot installs ~13GB of game + builds the Proton prefix (slow, one-time). Every boot
after skips Steam entirely and is fast — full startup is ~20s. Verified on bare-metal Ubuntu
22.04: `Server has successfully started!` → advertising for join, port 7777/udp bound.

### Fast config loop

1. First boot generates `./config/GameUserSettings.ini` on the host.
2. Edit it.
3. `docker compose restart the-island` → relaunch, no Steam, just the map load.

## Profiles

| | `.env.test` | `.env.prod` |
|---|---|---|
| Boot | fast (skip update) | update-on-boot |
| Stop | instant kill | SaveWorld first |
| BattlEye | off | **on** (PvP anti-cheat) |

```bash
docker compose --env-file .env.prod up -d --build   # VPS
```

Real secrets live in `.env.test` / `.env.prod` (gitignored). Only the `.example` files are tracked.

## Troubleshooting: exit code 21

ASA aborts early with exit 21 for several distinct reasons — too-low `vm.max_map_count`
(handled above), a missing native `steamclient.so` for Proton (baked into the image + symlinked
at boot), or a partial Steam install. The default `WINEDEBUG=-all` hides the real fault; to see
it, boot with `WINEDEBUG=+err,+seh docker compose up` and look for the first non-Sentry `err:` line.

## Joining from the Windows ARK client (WSL)

The server itself runs fine under WSL2 (the old exit-21 crash was the missing `steamclient.so`,
not WSL) — but the verified test box is bare-metal Linux (`dell`). To join from the Windows ARK
client when running under WSL2, set `networkingMode=mirrored` in `.wslconfig`, or use the console
`open localhost:7777`.

## Database

The compose stack includes **MariaDB 11.4** (M2+). It starts automatically alongside the game
server and the game service waits for it to be healthy before launching. ArkShop connects to it
via the compose-internal service name `mariadb:3306` — no host port is published.

DB creds live in `.env.test` / `.env.prod` (gitignored). See `.env.test.example` for the
required `MARIADB_*` vars.

## Shared store (ArkShop + points economy)

The server runs **ArkShop** (a server-side economy plugin) backed by MariaDB. Players earn
points via playtime; operators stock a shop with items, dinos, and commands.

### Plugin config edit loop

Plugin configs live in `./plugins-config/<PluginName>/config.json` on the host. The first boot
seeds them from the plugin's image defaults; subsequent boots never overwrite your edits.

```
./plugins-config/
  ArkShop/config.json        ← item prices, shop layout, point rates
  Permissions/config.json    ← group definitions, permission grants
```

Edit on the host → `docker compose restart the-island` → plugin reloads the config on the next
server start. No image rebuild needed.

### DB credentials

ArkShop's DB connection is injected at boot from the `MARIADB_*` env vars (or the
`ARKSHOP_DB_*` overrides if you use a separate ArkShop DB user). The password is written into
`ArkShop/config.json` at runtime and never committed to git.

### Where economy data lives

All points balances, shop transactions, and player records are stored in the `arkshop` MariaDB
database on the `ark-db` named volume. Query it directly:

```bash
docker compose exec mariadb mariadb -u arkshop -p arkshop -e 'SHOW TABLES;' arkshop
```

### Required mod

**ASA API Utils** (CurseForge mod ID `955333`) is a server-side mod required by ArkShop — it
provides the singleton hooks ArkShop registers into. The entrypoint adds it to the mod list
automatically when `ENABLE_ASAAPI=1`; you do not need to list it in `MODS` yourself.

## Roadmap

M1 lean image → **M2 (current)** AsaApi + ArkShop + MariaDB shared store → **M3** cluster (one
economy across maps) → **M4** config tooling / backups / CLI → VPS deploy.

Design decisions live in `.claude/state.md`; build-vs-runtime split in
`.claude/rules/build-time-vs-runtime.md`; DB engine rationale in
`docs/internal/decisions/0001-db-engine-mariadb.md`.
