---
doc-type: adr
id: "0001"
title: Use MariaDB as the shared economy store DB engine
status: accepted
date: 2026-06-20
---

# ADR 0001 — Use MariaDB as the shared economy store DB engine

## Status

Accepted

## Context

The M2 milestone adds an ArkShop in-game economy backed by a real relational DB. ArkShop ships
its own MySQL client library bundled inside the plugin DLL; we do not control which client
version it was compiled against. The plugin communicates with the DB over the standard MySQL
wire protocol.

Several relational DB engines speak the MySQL wire protocol and were candidates.

## Decision

Use **MariaDB 11.4 (LTS)** as the database engine, pinned in `docker-compose.yml` as
`image: mariadb:11.4`.

## Rationale

ArkShop's bundled client library rejects connections to **MySQL ≥ 8.0.28**. This is a hard
compatibility constraint: the server's client-lib handshake fails against that version range,
producing a DB connection error at plugin load time. MariaDB speaks a compatible variant of
the MySQL wire protocol and is explicitly listed as supported by the ArkShop project.

MariaDB 11.4 is the current LTS release — long-term support, security patches, and a stable
wire-protocol surface. It is the lowest-risk pin: compatible today and stable over the M2–M4
horizon.

## Rejected alternatives

**Pinned MySQL 8.0.27** — the last pre-rejection MySQL minor version. Technically compatible
with ArkShop's client lib, but MySQL 8.0.x is EOL (end-of-life as of April 2024). Running EOL
software for the life of this stack introduces unpatched CVEs and no upstream support path.
Cost to reverse: replace the compose image tag + test the handshake.

**SQLite-only (no network DB)** — ArkShop's `UseMysql=false` mode falls back to SQLite, with
the DB file living in the plugin's config dir on the volume. Rejected because:
- M3 requires a shared DB that multiple map servers can reach over the network; SQLite is
  file-local and does not survive the cluster topology.
- The whole point of M2 is proving the shared-store foundation before clustering. Building on
  SQLite now means tearing it out and replacing it in M3 — build-twice, a documented
  anti-pattern (see `~/.claude/rules/no-duct-tape.md` §11).
- Cost to reverse from MariaDB to SQLite would mean re-doing M2 scope; cost to go MariaDB from
  the start is the correct sequence.

## Consequences

- MariaDB is internal to the compose network (no host port published). ArkShop connects via
  `mariadb:3306` (compose service name). This reduces the attack surface versus exposing 3306
  to the host.
- DB data lives in the `ark-db` named volume.

  **Deferred: economy DB backups (mysqldump).**
  - **What**: automated economy DB backups (`mysqldump` of the `arkshop` database).
  - **Why**: backups are out of M2 scope; the `m4-ops-tooling` milestone owns the full backup
    story (world saves + DB) as a unit — splitting it here would deliver a partial ops story with
    no coordinated restore path.
  - **Cost of deferring**: if the `ark-db` volume is lost between M2 go-live and M4, all economy
    data (points balances, shop records) is unrecoverable. The volume is standard Docker-managed
    storage we own — survives normal restarts — but it is unbacked against host-level data loss.
  - **Trigger**: the `m4-ops-tooling` milestone. This deferral is anchored to the initiative
    capability ledger at `.claude/plans/active/ark-asa-server/capability-ledger.md`, row
    "Backups: economy DB (mysqldump) | m4-ops-tooling | planned | DB unbacked between M2 ship
    and M4 — accepted" — it will be picked up as part of that milestone and cannot be dropped.
- Bumping the MariaDB tag requires a `docker compose pull` + restart (not a rebuild). The
  version pin is in `docker-compose.yml`; updating it is a one-line change.
