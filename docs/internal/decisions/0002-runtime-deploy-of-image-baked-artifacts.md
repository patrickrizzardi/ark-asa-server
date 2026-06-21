---
doc-type: adr
id: "0002"
title: Bake immutable artifacts in the image, deploy onto the volume at runtime
status: accepted
date: 2026-06-20
---

# ADR 0002 — Bake immutable artifacts in the image, deploy onto the volume at runtime

## Status

Accepted

## Context

The ARK: Survival Ascended server image builds on `ghcr.io/parkervcp/steamcmd:proton`. Two
categories of artifacts need to reach the running server but cannot be `COPY`-ed directly to
their final destination at image-build time:

**VC++ 2019 redistributable runtime DLLs** — required by `AsaApiLoader.exe`. The DLLs are not
copied as files; they are registered into the Proton Wine prefix by running the VC++ installer.
The Wine prefix lives on the `ark-game` named volume at
`${STEAM_COMPAT_DATA_PATH}/pfx/` (i.e., `/home/container/arkserver/steamapps/compatdata/2430930/pfx/`).
That path does not exist at image-build time — Docker creates the named volume at `docker compose up`
time and Proton creates the prefix on first boot. A `RUN proton run VC_redist.x64.exe` during
`docker build` would fail: no prefix, no volume mount, no runtime env.

**AsaApi loader + plugin DLLs** — the game's `ShooterGame/Binaries/Win64/` is on the `ark-game`
volume (the full ~30GB install lands there via `steamcmd +app_update` at first boot). Plugins live
under `Win64/ArkApi/Plugins/<name>/`, which is also on the volume. A `COPY` into that path during
the build is overwritten or hidden by the volume mount at runtime.

Both cases share the same structure: the artifact is **immutable once baked** (satisfies the
Dockerfile condition), but its **deployment target is a runtime volume** (fails the Dockerfile
condition). The build-time-vs-runtime.md 3-question test applied to each:

| Question | VC++ install | Plugin deploy |
|---|---|---|
| 1. Depends on runtime state (mounted volume)? | **Yes** — prefix is on the volume | **Yes** — `Win64/` is on the volume |
| 2. Target changes often? | No (frozen in image layer at build time) | No (pinned versions in `ARG`) |
| 3. Must re-run every boot to stay correct? | No (idempotent marker-guard) | Yes (version wins; clean-replace on bump) |

Note: the community plugins are **name-pinned** (`?version=ARG` in the URL) — the `ARG` value is
the version source-of-truth and rebuilding the image with a new `ARG` is the deliberate update
mechanism. The VC++ installer URL (`aka.ms/vs/16/release/vc_redist.x64.exe`) is **evergreen** —
it always resolves to Microsoft's current merged VC++ 2015–2022 (14.x) redistributable. The exact
binary is frozen into the image layer at `docker build` time, so every container from a given image
gets the identical installer; but a rebuild on a later date may fetch a newer 14.x point release.
This is acceptable: Microsoft's 14.x redistributable is ABI-stable and backward-compatible by
their compatibility contract, so a newer point release is safe for any consumer of the VC++ 2019
runtime. The DLL-presence check verifies the three runtime DLLs by filename regardless of 14.x
point version. See the Consequences section for the named tradeoff.

Any "yes" → entrypoint. Both cases land in the entrypoint.

## Decision

Split each artifact into two pieces:

1. **Bake the immutable source into the image** at a neutral `/opt/` path owned by the
   `container` user. For community plugins, the image `ARG` values are the version
   source-of-truth; rebuilding with a new `ARG` is the deliberate update mechanism — no
   hands-off auto-updates. For the VC++ redistributable, the `aka.ms/vs/16` URL is evergreen
   (see Context note above); the specific binary is frozen into the image layer at build time.

2. **Deploy from `/opt/` onto the volume at entrypoint runtime**, idempotent and marker-guarded
   (or DLL-presence-gated) so re-runs are no-ops on warm boots.

Concretely:

- `/opt/vcredist/VC_redist.x64.exe` — baked in `Dockerfile`; `install_vcredist()` in
  `entrypoint.sh` runs `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` into the
  volume prefix on first boot. Skip gate: presence of the three runtime DLLs in
  `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` (not a bare marker, which would falsely
  skip after a prefix reset). A `.vcredist-installed` marker on the volume provides a fast-path hint.

- `/opt/asaapi/` — baked in `Dockerfile`; `deploy_plugins()` in `entrypoint.sh` syncs the tree
  into `${ARK_DIR}/ShooterGame/Binaries/Win64/` each boot using a clean-replace strategy (stash
  operator configs → remove AsaApi-owned paths → copy fresh from image → restore configs).

The `steamclient.so` bake-to-`/opt/steamcmd` + boot-time-symlink pattern (established in M1) is
the direct precedent for this split.

## Rejected alternatives

**Run the VC++ installer in the Dockerfile** — fails at build time because the Proton prefix does
not exist; `docker build` has no volume mounts. This is a hard mechanical constraint, not a
preference.

**Copy plugin DLLs into the image at their final Win64 path** — the `COPY` destination is hidden
by the `ark-game` volume mount at runtime. The copied files would be unreachable.

**Download artifacts at entrypoint runtime** — avoids the `/opt/` staging but makes every boot
network-dependent and non-reproducible. A bad upstream release (or a URL that goes 404) would
break the server on a random restart. The anti-pattern this project is designed to beat.

**Vendor binaries into the git repo** — largest artifacts (VC++ redist ~25MB, AsaApi zip ~5MB)
are reasonable to commit but pinning via a `curl` + version `ARG` in the Dockerfile is cleaner
for auditability (URL + version visible in the layer history) and keeps the repo lean. If the
distribution URL becomes unavailable, vendoring is a valid fallback; the `ARG` pins make the
version explicit regardless.

## Consequences

- **Community plugins are version-pinned via `ARG`.** Updating a plugin requires bumping the `ARG`
  and rebuilding. The cost paid: no hands-off auto-updates. The cost avoided: a bad upstream
  release silently breaking the server on a random restart.
- **VC++ redistributable is evergreen-fetch-then-frozen.** The `aka.ms/vs/16` URL always resolves
  to Microsoft's current merged VC++ 2015–2022 (14.x) redistributable; the exact binary is frozen
  into the image layer at `docker build` time. A rebuild on a later date may fetch a newer 14.x
  point release. This is a deliberate tradeoff: the community plugins use name-pinned URLs because
  a volatile upstream build can break the server silently — the `ARG` pin is the safety valve.
  The VC++ 14.x redistributable is ABI-stable and backward-compatible by Microsoft's compatibility
  contract, so a newer point release is safe for any consumer of the VC++ 2019 runtime. The
  DLL-presence check verifies the three runtime DLLs by filename regardless of 14.x point version.
  The cost paid: a rebuild on a different date may produce a marginally different binary. The cost
  avoided: pinning via a frozen URL would require vendoring or a custom CDN to guarantee
  availability — additional infrastructure for an artifact whose point-release churn is safe.
- **Cold-start overhead is bounded.** The VC++ install (`proton run`) runs once per prefix
  lifetime; `deploy_plugins()` is a fast `cp -r` on every boot (binaries already on disk in
  `/opt/`). Neither step requires network access after the image is built.
- **Prefix reset re-triggers VC++ install correctly.** Because the skip gate checks DLL presence
  rather than a bare marker file, nuking and recreating the prefix (e.g., `rm -rf
  ${STEAM_COMPAT_DATA_PATH}/pfx`) will correctly re-run the installer on the next boot.
- **`build-time-vs-runtime.md` table row for VC++ amended** to reflect this design (the original
  row said "Dockerfile"; that assumed a prefix baked into the image, which is not this project's
  architecture).
