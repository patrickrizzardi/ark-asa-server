---
plan: m2-shared-economy-store
phase: 5
deviation: 3
type: scope
round: 1
verdict: PASS
---

# Deviation Judge — Phase 5 Deviation #3
# Scope: plugins-config/.gitkeep (new file outside plan's Files scope)

## Verdict: PASS

## Deviation summary (one line)
Executor added `plugins-config/.gitkeep` to guarantee the bind-mount source directory exists in the
checkout so Docker does not auto-create it as root (which would block the non-root container user
from writing into it).

---

## Adversarial input(s) constructed

**Strategy 1 — Mixed input (redundancy probe):**
`ENABLE_ASAAPI=0` boot on a fresh clone where `plugins-config/` exists as a tracked empty dir (via
`.gitkeep`): Does the `.gitkeep`-guaranteed directory create a conflict with or become irrelevant to
the `setup_plugin_configs()` `mkdir -p "${host_root}"` call at entrypoint.sh:269? Specifically —
does the `.gitkeep` file itself (a real file at `plugins-config/.gitkeep`) land in the
host-bind-mounted path and propagate into the container as a spurious `plugins-config/.gitkeep`
that the config-seed logic might mistakenly try to act on?

**Strategy 2 — `ENABLE_ASAAPI=0` vanilla boot on fresh clone:**
Fresh clone, `ENABLE_ASAAPI=0`. The `./plugins-config` dir exists (because `.gitkeep` guarantees
it). Compose mounts `./plugins-config:/home/container/plugins-config`. `setup_plugin_configs()` is
gated on `ENABLE_ASAAPI=1` (entrypoint.sh:401-413), so it NEVER runs. The bind-mount source now
exists (non-root, `patrick:patrick` 755 as seen in `ls -la`). Does Docker still root-create
anything? No — source exists. Does anything break? No.

**Strategy 3 — Boundary input (pre-existing dir without .gitkeep, Docker auto-create behavior):**
Fresh clone WITHOUT `.gitkeep` committed: `./plugins-config` is absent from the working tree.
`docker compose up` would auto-create it as root. Is that claim accurate? Docker Compose v2
behavior: when a host bind-mount source path does not exist, Docker creates it as `root:root 0755`.
The container runs as `container` (non-root UID). `setup_plugin_configs()` calls
`mkdir -p "${host_root}"` at entrypoint.sh:269, which maps to `/home/container/plugins-config`
INSIDE the container. That path is the bind-mount target, which points back to the host's
`./plugins-config` directory already created by Docker as root. The `mkdir -p` call INSIDE the
container runs as `container` (non-root): it tries to create the dir but it already exists (Docker
already made it as root). `mkdir -p` succeeds on existing dirs regardless of ownership — it is a
no-op when the dir exists. So the failure point would be at the NEXT step: `mkdir -p "${host_dir}"`
(entrypoint.sh:275) creating `plugins-config/ArkShop` and `plugins-config/Permissions` subdirs
INSIDE a root-owned directory. Here is the actual break: a root-owned parent directory (0755, root)
blocks a non-root user from creating subdirectories inside it. `mkdir -p
/home/container/plugins-config/ArkShop` run as `container` would fail with `EACCES` if the parent
`plugins-config/` was root-created with 0755. This confirms the rationale's claim is accurate.

**Strategy 4 — The .gitkeep file itself as contamination:**
The `.gitkeep` file lives at `plugins-config/.gitkeep` on the host. The bind mount in compose is:
`./plugins-config:/home/container/plugins-config`. So inside the container,
`/home/container/plugins-config/.gitkeep` is a 0-byte file. `setup_plugin_configs()` iterates over
`ArkShop` and `Permissions` explicitly (hardcoded loop: `for plugin in ArkShop Permissions`). It
does NOT glob `${host_root}/*`. It does NOT read `.gitkeep` or react to it. The seed-if-absent
check is `[[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` — it looks for
`ArkShop/config.json` and `Permissions/config.json`, not `.gitkeep`. `inject_plugin_db_config()`
also addresses `ArkShop/config.json` and `Permissions/config.json` via explicit paths. The
`.gitkeep` file simply exists in the bind-mount and is ignored entirely by all entrypoint logic.
No contamination.

---

## Trace

**Active input: fresh clone WITHOUT `.gitkeep`, `ENABLE_ASAAPI=1` boot.**

1. `docker compose up` reads `docker-compose.yml:88`: `- ./plugins-config:/home/container/plugins-config`.
2. Docker checks whether `./plugins-config` exists on the host. It does NOT.
3. Docker Compose v2 auto-creates `./plugins-config` as `root:root 0755` on the host.
4. Bind-mount proceeds: `/home/container/plugins-config` inside container is backed by the host dir,
   now owned root:root 0755.
5. Entrypoint runs as `container` (non-root). `main()` calls `setup_plugin_configs()` at entrypoint.sh:403.
6. `setup_plugin_configs()` line 269: `mkdir -p "${host_root}"` → `mkdir -p /home/container/plugins-config`.
   This directory ALREADY EXISTS (Docker created it). `mkdir -p` is a no-op. Returns 0. No error.
7. Loop iteration: `plugin=ArkShop`. Line 275: `mkdir -p "${host_dir}"` → `mkdir -p /home/container/plugins-config/ArkShop`.
   This is a CREATE inside a ROOT-OWNED 0755 directory. Non-root `container` user does NOT have write permission on the parent.
   **`mkdir` fails: `Permission denied (EACCES)`.** Under `set -euo pipefail` (entrypoint.sh:6), this is an immediate fatal exit.
8. Container crashes with a cryptic `mkdir: cannot create directory '/home/container/plugins-config/ArkShop': Permission denied` error.

**Active input: fresh clone WITH `.gitkeep`, `ENABLE_ASAAPI=1` boot.**

1. `docker compose up` reads `docker-compose.yml:88`.
2. Docker checks whether `./plugins-config` exists on the host. It DOES (tracked via `.gitkeep`).
   The directory is `patrick:patrick 0755` (as confirmed by `ls -la plugins-config/`).
3. Bind-mount proceeds: `/home/container/plugins-config` inside container is backed by the host dir,
   owned `patrick` (same UID that runs the container, since Docker maps host UID to container UID in the
   bind-mount).
4. `setup_plugin_configs()` line 275: `mkdir -p "${host_dir}"` succeeds — parent is accessible.
5. Plugin dirs created, config seeded, symlinks established. No permission error.

The `.gitkeep` fix is load-bearing. Without it, `ENABLE_ASAAPI=1` boot from a fresh clone fails
fatally at the first `mkdir` inside the bind-mount.

**`.gitkeep` contamination trace (strategy 4 above):**
File lands at `/home/container/plugins-config/.gitkeep` inside the container. The entrypoint's
loop at entrypoint.sh:272 is `for plugin in ArkShop Permissions` — it never touches `.gitkeep`.
The seed check (line 279) tests `${host_dir}/config.json`, not any file in the parent dir.
`inject_plugin_db_config()` (line 293) operates on `${win64}/ArkApi/Plugins/ArkShop/config.json`
and `${win64}/ArkApi/Plugins/Permissions/config.json` via the symlinks — the bind-mount root with
`.gitkeep` is one level above. Zero contamination.

---

## Where the fix overshoots (BLOCK only)
N/A — verdict is PASS.

---

## Strategies attempted

**Mixed inputs:**
Checked whether `.gitkeep` (a real file in the bind-mount source dir) contaminates the config logic
at runtime. The entrypoint's `setup_plugin_configs()` operates on `ArkShop` and `Permissions` via
a hardcoded loop (entrypoint.sh:272) and never globs the host_root. The file is invisible to all
config-injection logic. No break.

Also checked whether `ENABLE_ASAAPI=0` boot with the `.gitkeep`-guaranteed dir present causes
issues. The whole `setup_plugin_configs()` / `inject_plugin_db_config()` chain is gated on
`ENABLE_ASAAPI=1` at entrypoint.sh:401. Vanilla boot: dir exists (no Docker root-create), bind
mounts fine, setup functions skipped. No break.

**Boundary inputs:**
The fresh-clone-without-.gitkeep input (strategy 3) is the exact boundary this fix addresses. I
traced it fully: Docker creates the dir as root, `mkdir -p` of the parent is a no-op, but the
first child `mkdir` (for `ArkShop` subdir) fails EACCES under `set -euo pipefail`. This
CONFIRMS the rationale — the fix is justified and accurate.

**Existing-primitive check:**
Checked whether `./config/.gitkeep` (the sibling bind-mount) uses the identical pattern. It does
(committed in `65d3024`, predating the plan). `docker-compose.yml:84` mounts `./config:/home/container/config`,
and `config/` has a tracked `.gitkeep`. This is an exact precedent for the pattern being
applied here. The `.gitignore` also follows the same pattern for both dirs: `plugins-config/**` plus
`!plugins-config/.gitkeep` mirrors the `config/` handling (config dir has no gitignore entry
because it's expected to hold real ini files, but the shape is consistent).

**Second-caller check:**
Is there any second caller that might use `./plugins-config` and behave differently if the dir
pre-exists as a real (non-root) dir vs. created by Docker as root? The only consumer is the
`the-island` service in compose. No second service. No break surface here.

**Trace-through:**
Executed fully above. Both paths (with and without `.gitkeep`) traced to their terminal outcome.
The `.gitkeep` path succeeds. The no-.gitkeep path crashes at entrypoint.sh:275 under
`set -euo pipefail`.

---

## Bottom Line
The rationale is technically accurate and the fix is precisely scoped: one `.gitkeep` mirrors the
existing `./config/.gitkeep` precedent, the entrypoint's `mkdir -p` doesn't create the bind-source
(Docker does, as root, blocking it), and the `.gitkeep` file is completely inert to all config-injection
logic. Nothing to BLOCK here.
