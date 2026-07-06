---
doc-type: "adr"
id: "0004"
title: "Shared config model — repo canonical, fresh per-server copy every boot"
status: "accepted"
date: "2026-07-06"
---

# ADR 0004 — Shared config model: repo canonical → fresh per-server copy every boot

## Status

Accepted

## Context

M3 runs N map servers that must share ONE set of rules (loot, tuning, shop catalog, permissions)
without the operator hand-editing N copies. Before this decision the stack had **three different
config models at once**:

- **Engine INIs** (`Game.ini`, `GameUserSettings.ini`): the engine's
  `ShooterGame/Saved/Config/WindowsServer` path was a **whole-dir symlink** to the shared
  `./config` host bind — every server read (and wrote) the same physical files.
- **ArkShop `config.json`**: deploy-from-repo each boot, but onto a **shared** `./plugins-config`
  host bind, with the per-server plugin dir holding a symlink into that bind.
- **Permissions `config.json`**: edit-on-host (seed-if-absent from the image default) on the same
  shared bind.

Two concrete failure modes rule that mix out the moment N > 1
(plan [Research Findings](../../../.claude/plans/active/ark-asa-server/m3-cluster/plan.md#research-findings),
Decision Ledger #5c/#5d/#5e):

1. **GUS shared-write clobber.** ASA rewrites `GameUserSettings.ini` on shutdown (verified: it
   strips comments and re-serializes). With the whole-dir symlink, that rewrite lands in the
   shared `./config` bind — N servers shutting down clobber one shared file with N different
   rewrites, and the repo canonical gets trashed by whichever server exits last.
2. **Plugin-config concurrent-boot copy race.** `docker compose up` starts all N servers in
   parallel. Deploying plugin configs onto ONE shared bind means N simultaneous non-atomic `cp` +
   `jq` injections against the SAME file — a server can read a half-written file mid-copy → jq
   parse error → loud boot failure that depends on timing.

## Decision

**ONE model for all four config files: repo canonical → fresh per-server copy on every boot →
repo wins (runtime edits discarded).** No per-config special-casing.

| Config | Repo canonical (read-only, shared) | Per-server deploy target (writable, own game volume) | Per-server tweak on copy |
|---|---|---|---|
| `Game.ini` | `config/Game.ini` | `…/Saved/Config/WindowsServer/Game.ini` | none (straight copy) |
| `GameUserSettings.ini` | `config/GameUserSettings.ini` | `…/Saved/Config/WindowsServer/GameUserSettings.ini` | inject `SessionName=${SESSION_NAME}` |
| ArkShop `config.json` | `config/arkshop.config.json` | `…/Win64/ArkApi/Plugins/ArkShop/config.json` | inject `Mysql` block (nested schema) |
| Permissions `config.json` | `config/permissions.config.json` (NEW tracked seed, captured from the image default) | `…/Win64/ArkApi/Plugins/Permissions/config.json` | inject Mysql connection (flat schema — see Consequences) |

Mechanics, all in `entrypoint.sh`:

1. **`WindowsServer` is a real per-server directory** on the server's own game volume — the
   whole-dir symlink is gone. Each boot copies `Game.ini` and seeds `GameUserSettings.ini` from
   the canonicals, then injects this server's `SessionName` (line-oriented, CRLF-tolerant,
   handling key-present / key-absent / section-absent).
2. **Both plugin configs deploy from tracked repo seeds** as real files written directly into the
   per-server plugin dirs — no symlinks, no shared bind. The DB connection is injected afterwards
   onto the per-server copy only, so the tracked seeds stay secret-free.
3. **Permissions flips from edit-on-host to deploy-from-repo.** Safe because live permission
   group data lives in the shared MariaDB (the plugin's `config.json` is connection/display
   bootstrap only) — flattening it into the uniform model loses nothing an operator edits live.
4. **The shared `./plugins-config` host bind is removed** (compose bind, `.gitignore` entry, and
   the tracked placeholder dir). Its only purpose was the edit-on-host loop, which
   deploy-from-repo replaces: edit `config/*.json` (or regenerate) → push → restart.

**Why this is structurally race-free, not just less racy:** every writable config file now lives
on exactly one server's own volume. The shared artifacts (the `./config` bind) are read-only
sources that no runtime path ever writes; the written files are physically distinct per server.
There is no shared writable file left, so no ordering, locking, or boot-timing argument is needed
— the race is eliminated by topology, and stays eliminated for any N.

The per-server identity that genuinely differs (map, ports, `SessionName`, clusterid) stays
env/launch-arg-driven and never lives in the shared canonicals — that is what makes the read-only
`./config` bind safe to share.

## Rejected alternatives

**Shared writable configs (status quo for engine INIs)** — rejected outright: this IS the
GUS-clobber bug (Context #1). Any model where N servers write one file loses, deterministically,
on the first multi-server shutdown.

**Keeping the whole-dir `WindowsServer` symlink (with per-file exceptions)** — rejected: the
symlink is what routes the engine's GUS shutdown-rewrite into the shared bind. Special-casing GUS
out of it while symlinking the rest re-introduces per-config divergence for zero gain over a
plain per-server copy of both files.

**A per-server config generator (templating GUS/Game.ini per server)** — rejected as overkill:
only `SessionName` differs per server, and injection into a copy of the canonical delivers that
with one `awk` block. A generator adds a build step, a template language, and drift surface to
solve a one-key problem.

**Per-config special-casing (copy some, symlink others, seed-if-absent others)** — rejected by
Patrick's call: "do both as a fresh copy on boot… less conditionals, same result." Uniformity is
itself the feature — one model to reason about, one recovery story (restart re-deploys
everything), one place a reviewer checks for race-safety.

## Consequences

**Runtime config edits are discarded by design.** An in-game admin's GUS change, or a hand-edit
to a deployed plugin config, survives until the next restart and then loses to the repo. This was
never the supported loop; the supported loop is edit the canonical (or its generator spec) →
push → restart. The `plugins-config/` host-edit loop is gone with the bind.

**Permissions' real config schema is FLAT — its Mysql keys sit at the JSON root** (`UseMysql`,
`MysqlHost`, …), unlike ArkShop's nested `"Mysql"` object. Verified against the shipped image
default (extracted from the built image's `/opt/asaapi` tree). The injection is therefore
schema-aware (`_inject_mysql_block` takes `nested`/`flat`), and the Permissions inject guard
keys on `has("UseMysql")`. Do NOT "normalize" `config/permissions.config.json` to a nested
`Mysql` object: the plugin would silently ignore it and boot on its local store instead of the
shared DB — the exact silent failure the guard + loud skip-warning exist to surface.

**A missing repo seed is now a fatal boot error** (was: silent fall-back to the image default).
The seeds are tracked files on the read-only `./config` mount; absence means a broken checkout or
mount, and booting on image defaults would silently serve the wrong catalog / a DB-less
Permissions.

**`deploy_plugins()`'s config stash/restore stays.** It is redundant for ArkShop/Permissions
(overwritten from seeds right after) but load-bearing for plugins WITHOUT a repo seed — ArkShopUI
today — whose volume config would otherwise reset to the image default every boot. If ArkShopUI
ever earns a tracked seed, the stash becomes fully dead and can go.

**Dirty-volume transition is handled in the entrypoint, not by hand.** A volume last booted on
the old model still has `WindowsServer` as a symlink; the entrypoint removes the link itself
(never following it) before creating the real dir, so the first post-flip boot cannot write
through the stale link into the shared canonicals. Plugin-dir config symlinks from the old model
are cleared by `deploy_plugins()`'s existing clean-replace of the `ArkApi` tree.
