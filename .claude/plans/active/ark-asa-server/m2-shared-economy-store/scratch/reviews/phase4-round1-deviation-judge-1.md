# Deviation Judge — Phase 4 Round 1 Deviation #1

**Plan**: m2-shared-economy-store
**Phase**: 4
**Deviation type**: scope (Dockerfile touched outside Phase 4 declared Files)
**Verdict**: PASS

---

## Deviation summary (one line)

A standalone `RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*` layer was prepended to the Dockerfile (lines 15-19, before the `ARG STEAMCMD_DIR` declaration) to supply `unzip` for the Phase 2 AsaApi/ArkShop download-and-extract block.

---

## Adversarial inputs constructed

### Input 1 (primary — mixed/layer-ordering probe)

A subsequent `docker build` triggered by a **non-unzip change** (e.g., bumping `ASAAPI_VERSION` ARG or editing the entrypoint COPY) on a builder where the apt package index is even 1 day stale.

Mechanically: the new standalone apt RUN layer sits at Dockerfile position ~4 (after `FROM` + comment + `USER root`). Any cache miss on this layer — which occurs whenever the Debian package-repo metadata changes, or whenever the builder's layer cache is cold (CI, new machine, `--no-cache`) — busts ALL downstream layers:
- steamcmd download + self-update RUN (lines 26-30) — ~network fetch
- AsaApi + ArkShop download + unzip RUN (lines 41-60) — two network fetches + zip extraction
- VC++ redist download RUN (lines 67-70) — one network fetch
- `mkdir /home/container/arkserver` + chown (lines 74-75)

The narrower placement — embedding `apt-get update && apt-get install -y unzip` INSIDE the AsaApi RUN block (lines 41-60) where `unzip` is actually consumed — would restrict cache busting to only that RUN layer and everything after it, sparing the steamcmd layer.

### Input 2 (boundary — scope-only probe)

Phase 4's declared `Files (expected scope)` is `entrypoint.sh`, `docker-compose.yml`, `.env.test.example`, `.env.prod.example` — Dockerfile is explicitly excluded. The adversarial question for a scope deviation: does touching Dockerfile in Phase 4 introduce a side effect the plan didn't authorize that is distinct from the stated problem (missing `unzip`)?

Traced: the deviation installs exactly one package (`unzip`, with `--no-install-recommends`), cleans the apt lists, and adds no other behavior. The apt install is root-owned and completes before `USER container` drop at line 90. No runtime behavior introduced — this is purely a build-layer tool installation.

---

## Trace

**Input 1 — layer-ordering cache-bust probe:**

1. Builder executes `FROM ghcr.io/parkervcp/steamcmd:proton` (cached — base image unchanged).
2. `USER root` (no-op; cached).
3. New layer at `Dockerfile:17-19`: `RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*`. Docker computes cache key from: (a) the parent layer digest, (b) the RUN command string. The command string is FIXED — it doesn't change between builds unless someone edits it. Therefore this layer is CACHED as long as the parent layer (USER root instruction = sha of base image) doesn't change.
4. Critical observation: unlike `apt-get update` in an early layer that's followed by a version-pegged `apt-get install curl=X.Y`, `unzip` here is unversioned. Docker does NOT re-run `apt-get update` just because repo indexes changed on the apt server — it re-runs the layer only if the LAYER CACHE KEY changes (parent digest + command string). Since neither changes between builds (absent a base image update or editing the RUN line), the apt layer IS STABLE across builds.

**Where this resolves the concern:** Docker layer caching is keyed on (parent_digest, run_instruction_string) — NOT on whether the upstream apt repository has changed. `apt-get update` inside a Docker RUN only re-runs on a cache miss, not on a time-based staleness check. The "daily repo update busts your cache" concern applies to builds using `--no-cache` or after a base image update, but in those cases ALL subsequent layers would rebuild regardless of where `apt-get update` lives.

**Consequence:** Moving the apt layer inside the AsaApi RUN block would only save cache-busting IF the apt layer itself becomes stale (e.g., base image bumped). In that case, the steamcmd layer is ALSO stale by the same parent-digest change and would rebuild regardless. The ordering does not change the blast radius for the primary busting event.

**Input 2 — scope-only trace:**

The deviation touches Dockerfile:13-19. The only change is an `apt-get install unzip` in a new RUN. No ARG modified, no ENV added, no COPY changed, no runtime variable introduced. The package installs to the standard Debian bin path (`/usr/bin/unzip`) and is consumed only by the `unzip -q` calls at Dockerfile:44 and Dockerfile:56 (AsaApi + ArkShop extraction). Phase 4's expected-scope files are untouched by this layer; the deviation is narrowly scoped to supplying a missing build tool.

---

## Strategies attempted

### Mixed inputs
Tried: new apt layer as a "cache-bust amplifier" — does its placement before steamcmd mean a non-unzip change causes more rebuilds than placing the apt install inside the AsaApi RUN block?

Result: No break. Docker layer cache is keyed on (parent_digest, command_string), not on apt repo freshness. The apt layer's cache is only busted when the base image digest changes OR when the RUN line is edited. When the base image changes, ALL downstream layers rebuild regardless — the steamcmd layer would be stale too. The placement of the apt install does not amplify cache busting beyond what a base-image update would cause anyway.

### Boundary inputs
Tried: `docker build --no-cache` (simulates fresh CI builder or forced rebuild). In this case ALL layers execute regardless. The apt layer runs `apt-get update` fresh, installs `unzip`. The downstream layers (steamcmd, AsaApi, ArkShop, vcredist) all re-download. This is identical to the behavior if `unzip` were in the AsaApi RUN block — `--no-cache` blows every layer.

Result: No differential break introduced by this placement.

### Existing-primitive check
Searched for any existing apt-install layer in the Dockerfile that could have been amended to include `unzip` instead of adding a new RUN: `grep -n "apt-get" Dockerfile` — returns only the new lines 17-19. No prior apt layer exists in the Dockerfile. The steamcmd download uses `curl | tar`, not a package; VC++ is a `curl` download of a `.exe`. There is no existing apt RUN to fold into.

Result: No narrower merge target exists. The standalone RUN is the only viable form given no prior apt layer.

### Trace-through
Traced the full Dockerfile execution with the adversarial input (non-unzip cache bust, warm builder). apt layer: CACHE HIT (parent digest unchanged, command string unchanged). steamcmd layer: CACHE HIT (parent unchanged). AsaApi layer: CACHE MISS on ARG change → rebuild, downloads zips, calls `unzip -q` — now succeeds because `/usr/bin/unzip` exists from the cached apt layer. VC++ layer: CACHE MISS (downstream of AsaApi). Result: correct behavior, no regression.

### Round-trip / scope-side-effect check
The new layer installs `unzip` to the image. Checked: does this introduce any runtime behavior (entrypoint access, volume interaction, secret exposure)? No — `unzip` is a build-time extraction tool; the `rm -rf /var/lib/apt/lists/*` cleanup correctly removes the apt index (standard hardening). The package adds ~170KB to image size. `--no-install-recommends` keeps it lean. No side effects.

---

## Where the fix overshoots (BLOCK only)

N/A — verdict is PASS.

---

## Bottom Line

The standalone apt layer is structurally correct: no prior apt target to fold into, cache is keyed on command-string not repo freshness, and `--no-install-recommends` + list cleanup keeps it tight. The only non-trivial adversarial angle (cache-bust amplification) dissolved when tracing Docker's actual cache-keying semantics. PASS — this one's clean, chief.
