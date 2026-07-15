---
doc-type: runbook
title: AsaApi modded stack won't load (ArkShop / Permissions missing)
status: active
date: 2026-07-14
---

# Runbook — AsaApi modded stack won't load

Symptom: the server boots, but ArkShop / ArkShopUI / Permissions never appear in-game, or the
AsaApi log loops instead of loading plugins. This runbook covers the **offset-cache dependency**
that gates the whole modded stack, plus the three distinct failure modes seen in production.

Related: [build-time-vs-runtime](../../../.claude/rules/build-time-vs-runtime.md),
[ADR 0002 — runtime deploy of image-baked artifacts](../decisions/0002-runtime-deploy-of-image-baked-artifacts.md),
[ADR 0001 — MariaDB engine](../decisions/0001-db-engine-mariadb.md), and `entrypoint.sh`.

## Mental model — the offset cache is the real dependency, NOT the plugin versions

AsaApi V2.x resolves ARK's function offsets from a **cache archive keyed to the game server
executable's sha256**. On boot it computes `sha256(ArkAscendedServer.exe)` and downloads
`https://cdn.pelayori.com/cache/<hash>.zip` (the `DownloadCacheURL` in the AsaApi `config.json`).
No cache → no offsets → **zero plugins load**, even though the server itself starts fine.

The cache is published **per game build, by an upstream maintainer (pelayori), on their own
schedule** — there is a lag after every ARK patch before a new build's cache appears. This is the
key, counter-intuitive consequence:

> **"Update the game" is not the lever. "Land on a build that has a published cache" is.**
> Updating onto a brand-new build that pelayori hasn't cached yet fails *identically* to not
> updating at all — same 404, same loop. The same update command can work one day and fail the
> next purely because of upstream cache timing.

**Corollary: the next ARK patch can re-break the entire modded cluster** until pelayori catches
up. This is expected, not a regression in our setup.

## The 5-second oracle — check BEFORE booting or updating

Do not boot-and-pray. Ask the CDN whether your build is loadable first:

```bash
# From inside a container (or any host with the exe on a mounted volume):
hash=$(sha256sum /home/container/arkserver/ShooterGame/Binaries/Win64/ArkAscendedServer.exe | awk '{print $1}')
curl -sI "https://cdn.pelayori.com/cache/${hash}.zip" | head -1
#   HTTP/2 200  → the modded stack WILL load on this build. Proceed.
#   HTTP/2 404  → it will NOT. Wait for pelayori, or move to a build that has a cache. Don't boot.
```

To find the latest available build id: `steamcmd +login anonymous +app_info_update 1 +app_info_print 2430930 +quit` (public branch buildid).

## Failure mode 1 — no published cache for the installed build (upstream)

**Log:** `[API][warning] Cache archive <hash>.zip is unavailable or invalid. Retrying in N seconds.`
(loops forever).

**Cause:** pelayori has not published an offset cache for the currently-installed game build. The
oracle above returns 404.

**Fix:** update the game to a build that *does* have a cache (verify with the oracle first), then
reboot. If no recent build has a cache yet, you are waiting on upstream — nothing local fixes it.

## Failure mode 2 — cache download disabled in a stale config (local drift)

**Log:** `[API][critical] Automatic cache download is disabled and no verified cache matches this
executable.`

**Cause:** the AsaApi framework `config.json` on that map's volume has
`settings.AutomaticCacheDownload.Enable = false`. The entrypoint seeds this file **only if absent
and never overwrites it**, so a stale config from an older deploy survives and silently blocks the
cache path — even on a build that has a valid cache. This is invisible on a config diff unless you
check each volume.

**Fix:**

```bash
C=/home/container/arkserver/ShooterGame/Binaries/Win64/config.json
docker exec <container> bash -lc "jq '.settings.AutomaticCacheDownload.Enable=true' $C > /tmp/c.json && mv /tmp/c.json $C"
docker compose restart <service>
```

Audit all volumes at once:

```bash
for v in ark-game-center ark-game-genesis ark-game-island ark-game-ragnarok; do
  echo -n "$v: "; docker run --rm --user container -v ${v}:/g --entrypoint bash ark-asa:latest \
    -lc 'grep -A2 AutomaticCacheDownload /g/ShooterGame/Binaries/Win64/config.json | grep Enable'
done
```

## Failure mode 3 — Permissions can't reach MariaDB (old connector vs TLS)

**Log:** `[Permission][critical] Failed to open connection!` (ArkShop loads fine; only Permissions
fails). MariaDB server log shows: `Aborted connection ... user: 'unauthenticated' ... (This
connection closed normally without authentication)` — i.e. the client aborted the handshake
*before* sending credentials.

**Cause:** the bundled Permissions plugin (v1.1) links an old libmysqlclient that cannot complete
MariaDB 11.4's TLS handshake. MariaDB 11.4 auto-generates certs and advertises TLS by default;
ArkShop 1.61's newer connector negotiates it fine, the old Permissions one does not. Creds,
network, DB, and auth-plugin are all irrelevant here — the connection dies pre-auth.

**Fix:** disable server-side TLS so the old connector connects plaintext. In `docker-compose.yml`
the mariadb service carries `command: ["--skip-ssl"]`. Plaintext DB traffic is acceptable because
the DB is on the internal compose network only (host port defaults to `127.0.0.1`) and this is a
single-operator cluster — see the comment on that service and [ADR 0001](../decisions/0001-db-engine-mariadb.md).

**Gotcha:** the MariaDB **11.4 CLI defaults to *requiring* TLS**, so after `--skip-ssl` the CLI
itself fails with `TLS/SSL error: SSL is required, but the server does not support it`. That is the
CLI's default, not a real outage — the plugins connect fine. Query with the client-side flag:
`mariadb --skip-ssl -u<user> -p<pass> <db> -e '...'`.

Confirm Permissions actually connected (not just loaded) by checking its tables exist:
`PermissionGroups`, `Players`, `TribePermissions` in the `arkshop` DB.

## Operational notes

- **Update game builds SEQUENTIALLY, one map at a time.** Concurrent `steamcmd` runs against the
  same account step on each other — observed 2026-07-14: three parallel updates left one map
  silently on the old build with no error. If a delta update reports `state is 0x6`, delete
  `steamapps/appmanifest_2430930.acf` and re-run with `validate` (the entrypoint does this
  automatically on the boot path).
- **A green "Loaded plugin" line is necessary but not sufficient** — a plugin can load and still
  fail its DB connection (failure mode 3). Verify the DB side separately.
