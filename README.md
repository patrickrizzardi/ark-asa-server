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

First boot installs ~30GB of game + builds the Proton prefix (slow, one-time). Every boot
after skips Steam entirely and is fast — the only cost is ARK's ~60–120s map load.

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

## Joining from the Windows ARK client (WSL)

Enable `networkingMode=mirrored` in `.wslconfig`, restart WSL, then in-game console:
`open localhost:7777`. Logs + RCON work without any of this.

## Roadmap

M1 lean image (this) → **M2** AsaApi + ArkShop + MySQL shared store → **M3** cluster (one
economy across maps) → **M4** config tooling / backups / CLI → VPS deploy.

Design decisions live in `.claude/state.md`; build-vs-runtime split in
`.claude/rules/build-time-vs-runtime.md`.
