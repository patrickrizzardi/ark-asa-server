# Build-Time vs Runtime: What Goes in the Dockerfile vs the Entrypoint

The image and the entrypoint have different jobs. Putting a step in the wrong one is
either a fat image that rebuilds on every game patch, or a fragile 5-minute cold start that
reinstalls the world every boot. The split is a hard rule, not a judgment call.

---

## The Rule

> **Immutable + cacheable + version-pinned → Dockerfile.**
> **Mutable + volume-backed + must-be-fresh-each-boot → entrypoint.**

Ask three questions about any step. **Any "yes" → entrypoint. All "no" → Dockerfile:**

1. Does it depend on runtime state (env vars, mounted volumes, network reachability)?
2. Does the thing it produces change often (game patches, config edits)?
3. Must it re-run on every container start to stay correct?

---

## The Split (ASA server)

| Step | Where | Why |
|---|---|---|
| OS packages, Proton/Wine, winetricks, libs, curl | **Dockerfile** | fixed deps, cached layer, identical every run |
| SteamCMD — **the tool binary** | **Dockerfile** | the downloader doesn't change; bake it |
| Wine prefix + VC++ redist install | **entrypoint** (volume-backed prefix — see note) | Q1 yes: prefix lives on the mounted ark-game volume → entrypoint |
| AsaApi loader/framework — **pinned version** | **Dockerfile** | version-controlled; you choose when it updates |
| The entrypoint script itself | **Dockerfile** (`COPY`) | it's a build artifact |
| **ARK game files** (`steamcmd +app_update 2430930`) | **entrypoint** | ~30GB, patches constantly, lives on a volume |
| Cluster transfer dir (`Saved/clusters`) | **entrypoint** | volume-backed shared dir (Q1 yes) |
| Config templating from env | **entrypoint** | depends on runtime env |
| `tail -F` log streaming → stdout | **entrypoint** | runtime, every boot |
| Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`) | **entrypoint** | runtime, params from env |
| `mkdir -p` / touch logfiles | **entrypoint** | prep on the live volume |

**Note on VC++ redist placement**: the table row above was originally "Dockerfile" when this rule
was first written, assuming a Wine prefix baked into the image. This project's Proton prefix is
volume-backed (created at first boot under `STEAM_COMPAT_DATA_PATH`); the Dockerfile row was stale.
The 3-question test resolves it correctly: Q1 ("depends on a mounted volume?") = yes → entrypoint.
The installer binary itself is baked in the image at `/opt/vcredist/` (immutable); it runs against
the live prefix at runtime. See ADR 0002.

---

## The Anti-Patterns This Rule Prohibits

1. **"Everything in the entrypoint."** What the typical complex setups do — install Steam,
   download the game, run winetricks, install VC++, set up the API *every boot*. Result:
   10-minute network-fragile cold starts, nothing reproducible. This is the thing we are
   beating.
2. **"Everything in the Dockerfile."** Can't bake the game files (huge + patched weekly →
   you'd rebuild + repush the whole image every patch) and runtime config doesn't exist at
   build time.
3. **Confusing the SteamCMD tool with the game it downloads.** Tool → Dockerfile (fixed).
   Game → entrypoint (mutable, on a volume).

---

## Entrypoint Must Be Idempotent

It runs on every start, so every step must be safe to re-run: `steamcmd +app_update` is a
no-op when current, `mkdir -p`, `touch`, `tail -F`. No step may assume first-boot state.

---

## The Named Tradeoff (AsaApi pinning)

Pinning AsaApi in the Dockerfile means a rebuild to update the API — **deliberately**. The
cost paid: no hands-off auto-update. The cost avoided: a bad API release silently breaking
the whole cluster on a random restart. For a cluster-wide dependency we choose the version
to be a thing we bump and test, not a surprise. Auto-pull-latest-at-runtime is a valid
alternative only with that cost named.
