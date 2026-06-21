````markdown
# Phase 1 runtime evidence — 2026-06-21T00:21:40Z

Captured locally (WSL docker). MariaDB ACs are host-agnostic (stock mariadb:11.4, no Proton);
local boot is valid evidence. Full-stack `the-island` ordering is verified on dell in Phase 4/5.

## AC1: mariadb reaches healthy before the-island starts

**mariadb-healthy (captured):**
```
poll 1: health=starting
poll 2: health=starting
poll 3: health=healthy
--- final ps ---
NAME                IMAGE          COMMAND                  SERVICE   CREATED          STATUS                    PORTS
ark-asa-mariadb-1   mariadb:11.4   "docker-entrypoint.s…"   mariadb   16 seconds ago   Up 15 seconds (healthy)   3306/tcp
```

Note: `3306/tcp` with no `0.0.0.0:` prefix confirms no host port is published — AC4 also met.

**the-island ordering:** guaranteed by `docker-compose.yml` `the-island.depends_on.mariadb: condition: service_healthy` (Compose v2 hard guarantee); empirically confirmed when the game image boots on dell in Phase 4/5.

**Predicate met:** YES (mariadb-healthy in ~10 s / 3 polls) | ordering compose-guaranteed

## AC2: app user connects to arkshop DB on mariadb:3306

**Command + output:**
```
$ docker compose --env-file /tmp/phase1-test.env exec -T mariadb mariadb -u arkshop -papppw-test-only arkshop -e 'SELECT 1 AS app_user_connects;'
app_user_connects
1
```

**Predicate met:** YES

## AC3: data persists across `docker compose restart mariadb`

**Command + output (insert → restart → select shows 42):**
```
# INSERT
$ docker compose exec -T mariadb mariadb -u arkshop -papppw-test-only arkshop \
    -e 'CREATE TABLE IF NOT EXISTS _phase1_persist (id INT); INSERT INTO _phase1_persist VALUES (42);'
(exit 0)

# RESTART + poll to healthy
 Container ark-asa-mariadb-1 Restarting
 Container ark-asa-mariadb-1 Started
poll 1: health=starting
poll 2: healthy

# SELECT after restart
$ docker compose exec -T mariadb mariadb -u arkshop -papppw-test-only arkshop \
    -e 'SELECT * FROM _phase1_persist;'
id
42
(exit 0)
```

**Predicate met:** YES
````
