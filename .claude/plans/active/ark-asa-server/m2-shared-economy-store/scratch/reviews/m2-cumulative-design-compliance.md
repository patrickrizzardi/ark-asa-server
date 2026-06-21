# Design Compliance Review: m2-shared-economy-store Phase cumulative (whole-milestone)

### Verdict: PASS

### Diff Scope
- Files changed (cumulative `873509a..HEAD`, audited via HEAD end-state of the load-bearing files): `Dockerfile`, `entrypoint.sh`, `docker-compose.yml`, `.env.*.example`, `config/**`, `plugins-config/**`, `docs/internal/decisions/0001-*.md`, `docs/internal/decisions/0002-*.md`, `.claude/design-sources.md`, `.claude/rules/build-time-vs-runtime.md`, `README.md` (per plan `files:` front-matter + per-phase scopes).
- Lines added/removed: not separately counted — this is a cumulative end-of-milestone gate; the audit reconciles the HEAD state of the three load-bearing artifacts (Dockerfile, entrypoint.sh, docker-compose.yml) against the three `[locked]` docs.
- Diff source: `git diff 873509a..HEAD` (resolved end-state read directly from disk — no Bash tool in this environment; HEAD is the cumulative target the milestone built).

### Registry State
- Registry path: `/home/patrick/docs/development/ark-asa/.claude/design-sources.md`
- Registry status: present-and-valid
- Fallback globs used: no
- Parsed entries: 3 `[locked]`, 0 `[aspirational]`, 0 parse errors.

### Design Docs Loaded
All three `[locked]` entries loaded — every one is in-domain for an end-of-milestone cumulative sweep that touched Dockerfile + entrypoint + compose.
- `.claude/rules/build-time-vs-runtime.md` [locked] — governs Dockerfile-vs-entrypoint placement; the whole milestone is build/runtime split work → load (also locked-errs-toward-loading).
- `docs/internal/decisions/0001-db-engine-mariadb.md` [locked] — MariaDB engine + `mariadb:3306` service-name connection; compose adds the DB service → load.
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` [locked] — bake-to-/opt + deploy-at-runtime for VC++ AND plugins; entrypoint + Dockerfile implement exactly this → load.

### Design Docs Skipped
None — all registry docs loaded.

### Stale Registry Entries
None — all three registry globs resolved to at least one file:
- `.claude/rules/build-time-vs-runtime.md` → exists.
- `docs/internal/decisions/0001-db-engine-mariadb.md` → exists.
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` → exists.

### Required Fixes (BLOCK only — empty if PASS)
None — no design-doc contradictions found.

### Reconciliation detail (per locked doc)

**build-time-vs-runtime.md — every step honors the split + 3-question test:**
- `unzip` + `jq` apt install → Dockerfile (`Dockerfile:17-19`). Fixed build deps, immutable; all 3 Qs = no → Dockerfile. Consistent.
- SteamCMD tool binary → Dockerfile (`Dockerfile:26-30`). Matches "SteamCMD tool → Dockerfile".
- AsaApi + ArkShop + Permissions bake → `/opt/asaapi/` Dockerfile, `ARG`-pinned (`Dockerfile:32-60`). Matches "AsaApi loader pinned → Dockerfile" + the bake-to-/opt half of ADR 0002.
- VC++ installer bake → `/opt/vcredist/` Dockerfile (`Dockerfile:62-70`); install into volume prefix → entrypoint `install_vcredist()` (`entrypoint.sh:148-202`). Matches the **amended** row (`build-time-vs-runtime.md:28,37-42`): volume-backed prefix → entrypoint, installer immutable in image. The Phase-3 amendment is internally consistent with both the code and ADR 0002 — verified.
- Game install (`steamcmd +app_update 2430930`) → entrypoint (`entrypoint.sh:38-71`). Matches "ARK game files → entrypoint".
- Plugin deploy onto Win64 → entrypoint `deploy_plugins()` (`entrypoint.sh:73-146`). Win64 on volume → entrypoint.
- Config templating (DB cred inject) → entrypoint (`entrypoint.sh:302-390`). Depends on runtime env → entrypoint.
- `tail -F` log stream → entrypoint (`entrypoint.sh:499`).
- Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`) → entrypoint, behind `ENABLE_ASAAPI` toggle (`entrypoint.sh:452-453,495`). The launcher flip is present in the cumulative code — the rule's launch-row target is MET at end-state.
- `mkdir -p`/touch on the live volume → entrypoint (`entrypoint.sh:397-398,435`).
- Idempotency mandate honored: VC++ marker+DLL gate, plugin clean-replace, seed-if-absent config — all re-runnable.

No anti-pattern hit: not "everything in entrypoint" (immutable deps + tools + baked artifacts are in the image), not "everything in Dockerfile" (game + prefix install + config are runtime), tool-vs-game distinction respected.

**ADR 0001 (MariaDB):**
- `image: mariadb:11.4` (`docker-compose.yml:23`) — matches the pin.
- No host port published for `mariadb` (no `ports:` key on the service, `docker-compose.yml:22-37`) — matches Consequences "internal to the compose network (no host port)".
- ArkShop reaches the DB at `mariadb:3306` (`entrypoint.sh:23-24` defaults + `docker-compose.yml:73-74`) — matches "connects via `mariadb:3306`".
- No MySQL ≥8.0.28 introduced anywhere. The hard rejection constraint is not violated.

**ADR 0002 (runtime-deploy of image-baked artifacts):**
- VC++: baked installer `/opt/vcredist/VC_redist.x64.exe` (`Dockerfile:67-69`); `install_vcredist()` runs `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` (`entrypoint.sh:182`); skip-gate on the three runtime DLLs in the prefix `system32` (`entrypoint.sh:165-173`) with `.vcredist-installed` as an explicit fast-path **hint** (`entrypoint.sh:163,170`). This is exactly ADR 0002 §Decision item 1 + the line-76 "not a bare marker" requirement + the prefix-reset re-trigger consequence (line 123-125). Verified to the letter.
- Plugins: baked `/opt/asaapi/` (`Dockerfile:41-60`); `deploy_plugins()` clean-replace = stash configs → rm AsaApi-owned paths → cp fresh → restore configs (`entrypoint.sh:73-146`). Matches ADR 0002 §Decision item 2 ("clean-replace strategy").
- Version pinning via `ARG`; evergreen `aka.ms/vs/16` VC++ URL — matches Consequences "evergreen-fetch-then-frozen" + "community plugins version-pinned via ARG".

### Concerns (aspirational contradictions — non-blocking)
None. (Registry has zero `[aspirational]` entries — no aspirational contradiction is even possible.)

### Design Divergences ledger reconciliation
The plan's `## Design Divergences` (plan.md:167-179) holds exactly one entry: the `build-time-vs-runtime.md` launch-row, transiently enforced-but-unmet during the Phase 3→4 window (registry was bootstrapped in Phase 3 Step 6, one phase before the launcher flip in Phase 4). At cumulative end-state the launcher IS `AsaApiLoader.exe` (`entrypoint.sh:452-453,495`), so the launch-row target is MET and the divergence is CLOSED — confirmed by Phase 4's design-compliance gate note (plan.md:464) and the HEAD code. No open `[locked]` contradiction remains that would require a divergence entry, and the one recorded divergence is moot (not junk, not open).

The table amendment to the VC++ row is a doc **correction** made in-change (the 3-question procedure itself yields "entrypoint" for a volume-backed prefix), not a divergence — and the corrected row now matches the code. No `[locked]` doc is left inaccurate by the cumulative diff.

### Project-vs-Global Overrides
N/A — single project registry, no scope conflict.

### Bottom Line
Clean sweep, chief — all three locked docs reconcile against the cumulative diff, the VC++ row amendment lines up with the code AND ADR 0002, and the only recorded divergence was closed by Phase 4. Nothing to block.

OVERALL VERDICT: PASS
