# Design Compliance Review: m2-shared-economy-store Phase 3 Round 2

**Reviewer**: design-compliance-reviewer (Cortana voice)
**Timestamp**: 2026-06-20
**Diff source**: `git diff 1f9f1b7` (Phase 3 cumulative diff against Phase 2 commit)

---

## Verdict: PASS

---

## Diff Scope

- **Files changed**: 4 primary files in scope — `Dockerfile`, `entrypoint.sh`, `.claude/rules/build-time-vs-runtime.md`, `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`; plus `.claude/design-sources.md` (registry bootstrap), `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md` (Design Divergences entry added)
- **Lines added/removed**: approximately +180 / -5 (Dockerfile adds VC++ bake block; entrypoint adds `install_vcredist()` function; build-time-vs-runtime.md row amended; ADR 0002 written; registry created)
- **Diff source**: `git diff 1f9f1b7` — cumulative diff from Phase 2 commit to HEAD (includes both committed Phase 3 work and any uncommitted state)

---

## Registry State

- **Registry path**: `/home/patrick/docs/development/ark-asa/.claude/design-sources.md`
- **Registry status**: present-and-valid
- **Fallback globs used**: no

Registry contents parsed cleanly — 3 entries, all `[locked]`:

```
- [locked] .claude/rules/build-time-vs-runtime.md
- [locked] docs/internal/decisions/0001-db-engine-mariadb.md
- [locked] docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md
```

All 3 globs resolve to files on disk (verified via Glob tool). No stale entries.

---

## Design Docs Loaded

- `.claude/rules/build-time-vs-runtime.md` [locked] — loaded; primary domain doc for this phase (VC++ placement, launcher row, build-vs-runtime split). Sentinel Guard (c): err toward loading for all locked docs.
- `docs/internal/decisions/0001-db-engine-mariadb.md` [locked] — loaded; domain is DB engine selection. Phase 3 does not touch MariaDB configuration, but Sentinel Guard (c) requires loading all `[locked]` docs when uncertain. Read and checked — no intersection with Phase 3 diff.
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` [locked] — loaded; directly governing doc for Phase 3 (VC++ bake-in-image + install-at-runtime pattern). Registry bootstrapped in Phase 3; this ADR is written by Phase 3 and then registered. Read in full.

---

## Design Docs Skipped

None — all registry docs loaded.

---

## Stale Registry Entries

None — all three registry globs resolve to at least one file on disk:
- `.claude/rules/build-time-vs-runtime.md` — present
- `docs/internal/decisions/0001-db-engine-mariadb.md` — present
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — present

---

## Round 1 BLOCK Re-Evaluation

### Finding from Round 1: `build-time-vs-runtime.md` §The Split — "Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`)"

**What Round 1 found**: The rule's example table says launch `AsaApiLoader.exe`; the code at `entrypoint.sh:24` and `entrypoint.sh:228` still launches `ArkAscendedServer.exe`. No divergence entry existed at the time. → BLOCK.

**What the coordinator did**: Added a `## Design Divergences` entry to `plan.md` recording the transient mismatch with a rationale.

**Re-reading the divergence entry** (plan.md §Design Divergences, the single table row):

> Doc: `build-time-vs-runtime.md` §The Split (launch row)
> What it says: Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`)
> What we do instead: Through M2 Phases 1–3 the launch remains `ArkAscendedServer.exe` (the proven M1 vanilla path); the flip is Phase 4
> Rationale: **Hard phase-dependency, not duct tape.** `AsaApiLoader.exe` cannot load without the VC++ runtime that *this* phase (Phase 3) installs into the volume Proton prefix — flipping before the redist lands would crash the server on boot. The registry is bootstrapped in Phase 3 Step 6, one phase before the code reaches the target launch state, so the locked row is transiently unmet. **Named cost:** the launch-target row is enforced-but-unmet for the Phase 3→4 window. **Reversal/trigger:** Phase 4 ("Flip launch to `AsaApiLoader.exe`") flips it behind the `ENABLE_ASAAPI` toggle, closing this divergence. **Risk:** none new — the interim launch IS the M1 vanilla path already proven on `dell`.

**Rationale quality gate** (per `design-sources.md` §Bindingness Semantics and `no-duct-tape.md`):

Applying the five no-duct-tape junk-rationale tests:

1. "saves time" — NOT this. The rationale names a concrete mechanical dependency: AsaApiLoader.exe will crash on boot if the VC++ DLLs are not present in the Proton prefix. This is not convenience, it is a hard sequencing constraint.
2. "works for now" — NOT this framing. The rationale explicitly names the enforcement window (Phase 3→4) and the reversal trigger (Phase 4 flip).
3. "only one consumer today" — not applicable.
4. "acceptable for the MVP without a named follow-up trigger" — NOT this. The trigger is named: Phase 4, which is a concrete, sequenced plan phase in the same active plan file. Not a vague "someday."
5. "avoids a refactor" — not applicable; the reversal IS planned and scoped.

Does the rationale name a concrete cost the chosen approach pays vs the alternative? Yes: "the launch-target row is enforced-but-unmet for the Phase 3→4 window." The cost is explicit: the locked doc's constraint is not met in this window. The alternative (flipping the launcher now, before VC++ lands) would crash the server on every boot — a concrete failure mode, not a hypothetical.

Does the rationale identify a specific constraint that makes the alternative infeasible? Yes: `AsaApiLoader.exe` requires the VC++ 2019 runtime DLLs in the Proton prefix; the prefix is created at runtime on the `ark-game` volume; Phase 3 is the phase that installs those DLLs; flipping the launcher in Phase 3 before the DLLs are present would produce a broken server on boot.

Is there a named reversal path? Yes: Phase 4 ("Flip launch to `AsaApiLoader.exe`") behind the `ENABLE_ASAAPI` toggle. This is a specific, sequenced plan phase — not a todo, not a comment, not a vague future. It is in the same active plan file, where it cannot be dropped without the plan failing its own gates.

**Verdict on divergence**: This is a REAL engineering tradeoff with a named cost and a named reversal trigger. The rationale is not junk. The Round 1 BLOCK is resolved.

**Finding cleared.** Design Divergences entry covers this — rationale is a real tradeoff: "AsaApiLoader.exe hard-requires VC++ DLLs in the Proton prefix that Phase 3 installs; flipping before the DLLs land crashes the server; Phase 4 is the reversal trigger."

---

## Full Reconciliation: All Three Locked Docs vs. Phase 3 Diff

### Doc 1: `.claude/rules/build-time-vs-runtime.md`

**What Phase 3 does to this doc**: Amends the "Wine prefix + VC++ redist install" row from "Dockerfile" to "entrypoint (volume-backed prefix — see note)" and adds an explanatory note. This is a doc correction, not a contradiction — the 3-question test (Q1: "Does it depend on runtime state / mounted volumes?" → yes, the prefix is on the `ark-game` volume) already yields "entrypoint." The original table row was stale because it assumed a prefix-in-image; the correction makes the table accurate to the project's actual design.

**Is the amended table internally consistent with the entrypoint code?**

Checking `entrypoint.sh` `install_vcredist()` (lines 130–184 as read):

- Installer baked in image at `/opt/vcredist/VC_redist.x64.exe` → Dockerfile ✓ (Dockerfile lines 61–64)
- Skip gate: marker file AND presence of `msvcp140.dll` / `vcruntime140.dll` / `vcruntime140_1.dll` in `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` — all three must exist. Fast-path if marker AND all three DLLs present; install if any are absent.
- After install: capture rc, log if non-zero (benign rc=3010/1638 documented), then verify DLLs; fail-fast if missing.
- Write marker only after DLL verification passes.

Phase 3 plan Step 3 says: "After install, verify the three runtime DLLs landed... fail fast with a clear message if not... A `.vcredist-installed` marker may be written as a fast-path hint, but the DLL presence check is the source of truth."

The coordinator's briefing notes: "install block now captures the installer rc and lets the DLL-presence check arbitrate." Confirmed in the code: `local rc=0; proton run ... || rc=$?; if [[ ${rc} -ne 0 ]]; then echo ... fi` then the three-DLL missing-array check is the actual fail gate. The marker is written at line 182 only after the DLL presence gate passes at line 175. This is exactly the "trust the artifact, not the exit code" discipline the plan requires.

**Contradiction check on the VC++ row**: no contradiction. The amended row says "entrypoint (volume-backed prefix)"; the code puts the install in `install_vcredist()` which runs in the entrypoint. The installer binary is baked in the Dockerfile at `/opt/vcredist/`. Fully consistent.

**The "Launch `AsaApiLoader.exe`" row**: code still launches `ArkAscendedServer.exe`. Divergence recorded and evaluated above — rationale passes quality gate. PASS.

**The "AsaApi loader/framework — pinned version → Dockerfile" row**: `/opt/asaapi/AsaApiLoader.exe` is baked in the Dockerfile (confirmed in Dockerfile lines 35–54 as read). The entrypoint deploys it from `/opt/asaapi/` to the volume's `Win64/` each boot via `deploy_plugins()`. The table row says "Dockerfile" — the BAKING is in the Dockerfile; the DEPLOYMENT is in the entrypoint. This is exactly the bake-to-/opt + runtime-deploy pattern the rule governs. No contradiction.

**Result: PASS — no unrecorded contradictions of `build-time-vs-runtime.md`.**

---

### Doc 2: `docs/internal/decisions/0001-db-engine-mariadb.md`

**Domain match**: ADR 0001 governs DB engine selection (MariaDB as economy store). Phase 3 scope is VC++ redist install, `build-time-vs-runtime.md` amendment, ADR 0002 creation, and registry bootstrap. No MariaDB service changes, no DB connection string changes, no ArkShop config changes.

**Contradiction check**: Phase 3 does not touch `docker-compose.yml` MariaDB service, does not touch DB credentials, does not introduce an alternative DB engine, does not alter the MariaDB network isolation. ADR 0001's constraints (MariaDB only, MySQL ≥8.0.28 rejected, internal network only, `ark-db` volume) are all unaffected by Phase 3.

**Result: PASS — ADR 0001 domain does not intersect Phase 3 changes; no contradiction.**

---

### Doc 3: `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`

**Status**: This ADR is written in Phase 3. It is also registered `[locked]` in Phase 3. This is the special case where the diff creates the doc and then the registry enforces it. The question is whether the code is consistent with the ADR it just wrote.

**ADR 0002 Decision section**: "Split each artifact into two pieces: (1) Bake the immutable source into the image at a neutral `/opt/` path; (2) Deploy from `/opt/` onto the volume at entrypoint runtime, idempotent and marker-guarded (or DLL-presence-gated) so re-runs are no-ops on warm boots."

**Concrete claims from ADR 0002:**
- `/opt/vcredist/VC_redist.x64.exe` — baked in `Dockerfile`; `install_vcredist()` runs `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` on first boot. Skip gate: DLL presence, not bare marker. `.vcredist-installed` marker is a fast-path hint only.
- `/opt/asaapi/` — baked in `Dockerfile`; `deploy_plugins()` syncs via clean-replace (stash → rm → cp → restore).
- VC++ URL (`aka.ms/vs/16/release/vc_redist.x64.exe`) is evergreen — frozen into image layer at build time; this is acceptable because VC++ 14.x is ABI-stable.

**Checking ADR 0002 vs. code:**

VC++ bake (Dockerfile:61–64): `curl -fsSL "https://aka.ms/vs/16/release/vc_redist.x64.exe" -o /opt/vcredist/VC_redist.x64.exe` then `chown -R container:container /opt/vcredist`. Consistent with ADR's "bake immutable source into image at neutral `/opt/` path."

VC++ install (entrypoint.sh `install_vcredist()` lines 130–184): DLL-presence gate as primary arbiter, rc capture not used as gate, marker written only after DLL verification. Consistent with ADR's "DLL-presence-gated so re-runs are no-ops on warm boots" and "Skip gate: presence of the three runtime DLLs... (not a bare marker)."

Plugin bake (Dockerfile:35–54): AsaApi zip downloaded to `/opt/asaapi/` at pinned `ASAAPI_VERSION=1.21`. Consistent with ADR's "community plugins are name-pinned (`?version=ARG` in the URL)."

Plugin deploy (entrypoint.sh `deploy_plugins()` lines 55–128): stash configs → rm AsaApi-owned paths → cp fresh → restore configs. Consistent with ADR's "clean-replace strategy (stash operator configs → remove AsaApi-owned paths → copy fresh from image → restore configs)."

Evergreen vs. pinned distinction: ADR 0002 Consequences section explicitly names this: "VC++ redistributable is evergreen-fetch-then-frozen... A rebuild on a later date may fetch a newer 14.x point release. This is a deliberate tradeoff... ABI-stable by Microsoft's compatibility contract." The Dockerfile uses the `aka.ms/vs/16` URL (evergreen). The ADR names this tradeoff with a concrete cost ("a rebuild on a different date may produce a marginally different binary") and the justification (ABI-stable, 14.x backward-compatible). This is exactly what `no-duct-tape.md` requires of a documented deferral/tradeoff — not "works for now" but a named cost + named reason it's acceptable.

**Result: PASS — ADR 0002 is internally self-consistent, and the code is consistent with the ADR's stated decision and consequences.**

---

## ADR 0002 Pinning Framing Check (Coordinator-Requested Re-Verification)

The coordinator flagged that "ADR 0002's pinning framing was corrected to name the evergreen-vs-version-pinned tradeoff." Verifying this is now clean:

ADR 0002 Context section: "Note: the community plugins are **name-pinned** (`?version=ARG` in the URL)... The VC++ installer URL (`aka.ms/vs/16/release/vc_redist.x64.exe`) is **evergreen** — it always resolves to Microsoft's current merged VC++ 2015–2022 (14.x) redistributable. The exact binary is frozen into the image layer at `docker build` time..."

ADR 0002 Consequences section: "Community plugins are version-pinned via `ARG`. Updating a plugin requires bumping the `ARG` and rebuilding. The cost paid: no hands-off auto-updates. The cost avoided: a bad upstream release silently breaking the server on a random restart. // VC++ redistributable is evergreen-fetch-then-frozen... This is a deliberate tradeoff: the community plugins use name-pinned URLs because a volatile upstream build can break the server silently... The VC++ 14.x redistributable is ABI-stable and backward-compatible by Microsoft's compatibility contract... The cost paid: a rebuild on a different date may produce a marginally different binary. The cost avoided: pinning via a frozen URL would require vendoring or a custom CDN..."

This is a real tradeoff with named cost on both sides. Not duct tape. The framing is correct and consistent with the `build-time-vs-runtime.md` §The Named Tradeoff section's model (which names the rebuild-to-update cost for AsaApi pinning). No contradiction with the rule.

---

## Required Fixes

None — no design-doc contradictions found.

---

## Concerns (aspirational contradictions — non-blocking)

None. The registry contains only `[locked]` entries; no `[aspirational]` docs registered.

---

## Project-vs-Global Overrides

N/A — single project registry, no scope conflict.

---

## Bottom Line

The Round 1 BLOCK is dead. The divergence entry is a genuine sequencing rationale — AsaApiLoader.exe can't run without the VC++ DLLs that THIS phase installs, so the launcher flip is correctly gated to Phase 4, and the divergence record names that cost explicitly with a concrete reversal trigger in the same active plan file. Every table row in the amended rule is consistent with the code. ADR 0002 names both the pinned-vs-evergreen tradeoff and its cost. Registry is clean, all three locked globs resolve, no stale entries. Phase 3 is clear to proceed.

---

OVERALL VERDICT: PASS
