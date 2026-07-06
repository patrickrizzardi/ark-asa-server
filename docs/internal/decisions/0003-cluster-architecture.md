---
doc-type: "adr"
id: "0003"
title: "Cluster architecture — clusterid + shared transfer volume, per-server game volumes"
status: "accepted"
date: "2026-07-06"
---

# ADR 0003 — Cluster architecture: clusterid + shared transfer volume, per-server game volumes

## Status

Accepted

## Context

M3 turns the single-server M2 stack into a multi-map cluster: players move a character (and its
dinos/items) between maps via ASA's native cluster transfer, while every map keeps sharing the
same MariaDB-backed economy (already M2's job).

ASA's cluster transfer is controlled by two launch args, both required and both must agree across
every server in the cluster (verified 2026-07-05, web-confirmed — see the plan's
[Research Findings](../../../.claude/plans/active/ark-asa-server/m3-cluster/plan.md#research-findings)):

- `-clusterid=<id>` — must be **identical on every server**. Treated like a password: pick a
  non-obvious value, never the default "cluster"/"ark". Servers with different ids never see each
  other's transfers, even sharing the same directory.
- `-ClusterDirOverride=<path>` — cluster transfer files live under `<path>/<clusterid>`. **All
  servers must point at the same directory.** If the clusterid matches but the directory doesn't,
  players see the destination in the in-game transfer list but the download silently fails — no
  data moves, no error surfaced to the player. The unset default is
  `ShooterGame/Saved/Config/.../clusters`, which is per-container in a Docker deployment (each
  container has its own filesystem) — so leaving it unset guarantees broken transfers the moment
  there is more than one server.

Each map server also needs its own full game install: ASA has no supported "shared read-only
install, N config-only containers" mode — each server instance owns its own
`ShooterGame/Binaries/Win64` tree (loader + engine binaries + Wine/Proton prefix), and the M2
precedent (`ark-game` volume per service) already assumes this per-service ownership.

## Decision

1. **`ARK_CLUSTER_ID` (env) → `-clusterid=` launch arg**, appended to the launch flags **only when
   non-empty**. An empty/unset value produces the exact M2 single-server launch (no cluster args
   at all) — this is the load-bearing single-server-invariant: adding cluster capability must not
   change behavior for an operator who never sets a clusterid.
2. **`CLUSTER_DIR` (env, defaults to `${ARK_DIR}/ShooterGame/Saved/clusters`) → `-ClusterDirOverride=`**,
   appended alongside `-clusterid` under the same non-empty guard.
3. **One named Docker volume, `ark-cluster`, mounted SHALLOW at a fixed top-level path
   (`/home/container/cluster-data`) — not directly at `${CLUSTER_DIR}` — with `entrypoint.sh`
   symlinking `${CLUSTER_DIR}` → that mount on every boot.** A named volume (not per-service bind
   paths) makes "same directory across every server" structural rather than a config value each
   service author could independently get wrong. The shallow-mount-plus-symlink indirection
   (mirroring the existing `config_link` pattern for `./config`) exists because `CLUSTER_DIR`
   sits inside the already-mounted `ark-game` volume at a path that doesn't exist yet on first
   boot (steamcmd hasn't created `ShooterGame/Saved/` at mount time); mounting `ark-cluster`
   directly there would make Docker root-create the missing intermediate directories, blocking
   the non-root `container` user's writes to the cluster-transfer files. `/home/container/cluster-data`
   is pre-created and chowned to `container:container` in the `Dockerfile` (mirroring the existing
   `arkserver` pre-create), so the shallow mount lands on already-owned content. The shared anchor
   in `docker-compose.yml` is the single source of truth for the mount path, inherited by every
   service that uses it; `entrypoint.sh`'s symlink is what makes `${CLUSTER_DIR}` — the value
   `-ClusterDirOverride` actually points at — resolve to it.
4. **Per-server full game volumes** (each map service keeps its own `ark-game-<map>`-shaped
   volume, following the existing M2 `ark-game` pattern) rather than one shared read-only install
   serving N config-only containers.

## Rejected alternatives

**Leave `-ClusterDirOverride` unset (default per-container cluster dir)** — rejected outright, not
just a named tradeoff. Per-container defaults mean each server's transfer files live in its own
isolated container filesystem; a player's upload would write to a path no other server can ever
read. Transfers would break silently: the game does not error, it just never completes the
download on the destination map. This is exactly the failure mode Ledger #(shared cluster dir
wrong) risk-scores in the plan — a single shared named volume structurally eliminates it rather
than relying on every service author remembering to align paths.

**Host-path bind mount instead of a named volume** — rejected in favor of the named volume.
A host bind (e.g. `./cluster-data:/home/container/.../clusters`) works identically on this dev
box, but ties the deployment to a specific host directory layout. The named volume is portable to
a VPS with no path assumptions, matches the existing `ark-game`/`ark-db` precedent in this
compose file, and keeps the operator from needing to pre-create a host directory with the right
ownership before first boot.

**Shared read-only game install (one binary tree, N config-only containers)** — considered and
explicitly deferred, not rejected outright. See Consequences below.

## Consequences

**The shallow-mount + symlink indirection is required, not optional polish.** An earlier draft of
this decision mounted `ark-cluster` directly at `${CLUSTER_DIR}`; that was reproduced live as a
BLOCKER (nested mount at a subdir that doesn't exist yet inside the already-mounted `ark-game`
volume → Docker root-creates the missing intermediate directories → `Permission denied` for the
non-root `container` user). The fix — shallow mount at a fixed top-level path, pre-created/chowned
in the `Dockerfile`, symlinked from `${CLUSTER_DIR}` each boot by `entrypoint.sh` — is now the
committed mechanism (Decision item 3 above), not a workaround layered on top of it; any future
change to this ADR's model must preserve the shallow-mount-plus-symlink shape or re-prove the
direct-mount path against a non-root container user first.

**Named tradeoff — per-server full game volumes vs. a shared read-only install.**

- **What**: every map service gets its own complete ~13GB `ShooterGame` install (binaries + Wine
  prefix), duplicated per map, instead of one shared read-only install mounted into N
  config/save-only containers.
- **Why (real cost, not "saves time today")**: a shared-install model needs a real design — which
  parts of the tree are genuinely shareable (binaries, Proton prefix) vs. which must stay
  per-server (saves, per-map Wine state) — and ASA has no first-party support for this topology.
  Building it now would be engineering a novel deployment shape before proving the two-map cluster
  actually works end-to-end; the simple per-server-volume model is the direct extension of the
  already-proven M2 single-volume pattern.
- **Cost to fix later**: re-architecting to a shared install is a genuine redesign (read-only
  binary mount + per-server writable overlay for the Proton prefix and save state) — estimated
  1-2 sessions once a concrete disk-pressure case exists to design against.
- **Trigger**: disk pressure on the host, or the map count growing past 4 servers (at which point
  ~13GB × N stops being "cheap to just duplicate" and shared-install complexity becomes worth
  paying for).
- Cost avoided today: zero new topology to debug while the transfer/cluster-wiring mechanism
  itself is still unproven on this stack.

**The ASA transfer-dupe caveat (engine behavior, out of M3's control).** ASA's upload/download
cluster transfer can **duplicate** a dino or item if a server crashes mid-transfer (the upload
commits the item to the cluster-dir save before the source server's own state is fully
reconciled, so a crash in that window can leave the item live on both sides). This is a known ASA
engine behavior, not something this project's compose/entrypoint wiring can prevent. Mitigation is
operational, not structural: `SAVE_ON_STOP=1` + clean shutdowns (already the default posture — see
`entrypoint.sh`'s `stop()` trap) minimize the crash-during-transfer window; there is no code fix
available at this layer. This is accepted as a recorded, documented risk (plan Risk table: engine
behavior, in-game items are admin-cleanable, not money/irreversible) rather than something M3
attempts to engineer around.

**`build-time-vs-runtime.md` table amended** with a new row: the cluster transfer dir
(`Saved/clusters`) is volume-backed (Q1 = yes) → entrypoint, mirroring the reasoning already
applied to the Wine prefix in ADR 0002.
