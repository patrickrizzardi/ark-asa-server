# Design Compliance Review: m2-shared-economy-store Phase 3 Round 1

### Verdict: BLOCK

### Diff Scope
- Files changed: 5 (Dockerfile, entrypoint.sh, .claude/rules/build-time-vs-runtime.md, docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md, .claude/design-sources.md)
- Lines added/removed: estimated +130 / -3 (Phase 3 additions: VC++ Dockerfile layer ~5 lines, install_vcredist() ~47 lines, build-time-vs-runtime.md VC++ row amendment ~8 lines, ADR 0002 ~105 lines, design-sources.md registry ~9 lines; no git diff execution available — read from HEAD state)
- Diff source: HEAD read (git diff 1f9f1b7 command supplied; diff not directly executable in this context — full artifact analysis performed from current HEAD file state vs. prior-phase committed anchors documented in plan.md)

### Registry State
- Registry path: `/home/patrick/docs/development/ark-asa/.claude/design-sources.md`
- Registry status: **present-and-valid** — created in this very diff (Phase 3 bootstraps it); 3 valid `[locked]` entries parsed, 0 parse errors, 0 blank-only lines
- Fallback globs used: no

Registry content (verbatim, 3 entries):
```
- [locked] .claude/rules/build-time-vs-runtime.md — (internal) hard rule governing Dockerfile vs entrypoint placement; 3-question test is load-bearing for every phase
- [locked] docs/internal/decisions/0001-db-engine-mariadb.md — (internal) ADR: MariaDB as economy store engine; MySQL ≥8.0.28 rejection is a hard constraint
- [locked] docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md — (internal) ADR: bake-in-image + deploy-at-runtime pattern for VC++ + plugins
```

Registry format validation against `~/.claude/memory/design-sources.md`:
- All three lines match the valid form `- [locked] <glob> [— <domain note>]` ✓
- Domain notes present and non-empty ✓
- No comment lines, no blank lines, no parse-error lines ✓
- **FORMAT: VALID**

### Design Docs Loaded
- `.claude/rules/build-time-vs-runtime.md` [locked] — directly governs Dockerfile vs entrypoint placement; this diff's primary subject (VC++ installer bake + runtime install). Loaded unconditionally (Sentinel Guard (c): `[locked]` docs err toward loading).
- `docs/internal/decisions/0001-db-engine-mariadb.md` [locked] — ADR for MariaDB engine choice. Domain: DB engine selection, compose configuration. Phase 3 touches Dockerfile and entrypoint; no DB-engine changes are in scope. Loaded per Sentinel Guard (c) (`[locked]` → err toward loading).
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` [locked] — ADR for bake-in-image + deploy-at-runtime pattern. Created in this very diff and directly governs VC++ + plugin deploy pattern. Loaded unconditionally.

### Design Docs Skipped
None — all three registry docs loaded.

### Stale Registry Entries
None — all three globs resolved to exactly one file on disk:
- `.claude/rules/build-time-vs-runtime.md` ✓ (present, read)
- `docs/internal/decisions/0001-db-engine-mariadb.md` ✓ (present, read)
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` ✓ (present, read)

---

## Reconciliation Analysis

### Doc 1: `.claude/rules/build-time-vs-runtime.md` [locked]

**Phase 3's stated purpose for this doc:** amend the VC++ table row from "Dockerfile" (stale — assumed prefix-in-image) to "entrypoint (volume-backed prefix)" with the 3-question rationale. The plan's `## Design Divergences` section explicitly characterizes this as a doc *correction* in-change, not a divergence.

**VC++ row (amended):**
The amended table row reads:
```
| Wine prefix + VC++ redist install | **entrypoint** (volume-backed prefix — see note) | Q1 yes: prefix lives on the mounted ark-game volume → entrypoint |
```
Accompanied by a note clarifying the original row assumed a prefix baked into the image; the 3-question test resolves it to entrypoint for the volume-backed case. The installer binary itself is baked in `/opt/vcredist/` (immutable); it runs against the live prefix at runtime.

**Code vs amended rule — VC++ placement:**
- `Dockerfile:61-64`: `RUN mkdir -p /opt/vcredist && curl ... -o /opt/vcredist/VC_redist.x64.exe && chown -R container:container /opt/vcredist` — installer baked immutably ✓
- `entrypoint.sh:130-176`: `install_vcredist()` — runs `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` into the volume prefix at runtime, gated on DLL presence ✓
- `entrypoint.sh:204`: `install_vcredist` called after `install_or_update`, before launch ✓

**Result: VC++ placement CONSISTENT with the amended rule.** The amendment and the code agree. The correction-in-change is legitimate — the 3-question procedure in the rule's own §The Rule already yields "entrypoint" (Q1: depends on mounted volume = yes → entrypoint), so the table was always wrong, and this phase makes the table match the procedure. No contradiction.

**AsaApi pinning row:**
Rule says: `| AsaApi loader/framework — **pinned version** | **Dockerfile** | version-controlled; you choose when it updates |`
Code: `Dockerfile:32-54` — ARG-pinned download + unzip to `/opt/asaapi/`. Consistent ✓

**Idempotency rule:**
Rule says: "It runs on every start, so every step must be safe to re-run."
`install_vcredist()`: DLL-presence gated skip (not a bare marker). `rm -rf` before `cp -r` in `deploy_plugins()` is safe on absent paths under `set -euo pipefail` (rm -rf returns 0 on absent targets). ✓

**HOWEVER — one table row demands scrutiny: `Launch AsaApiLoader.exe (NOT ArkAscendedServer.exe)`**

The rule's table contains this row (present both before and after the Phase 3 amendment; Phase 3 did not touch this row):
```
| Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`) | **entrypoint** | runtime, params from env |
```

The `(NOT ArkAscendedServer.exe)` clause is an explicit prohibition — not merely a placement note. It declares that the correct runtime launch binary is `AsaApiLoader.exe` and the vanilla binary must not be used.

Current code in `entrypoint.sh`:
- Line 24: `SERVER_EXE="${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"`
- Line 220: `proton run "${SERVER_EXE}" "${query}" ${flags} 2>&1 &`

The code still launches `ArkAscendedServer.exe`. Phase 3 does not change this — the flip is deferred to Phase 4.

**Is this a new contradiction introduced by Phase 3?** The `ArkAscendedServer.exe` launch predates Phase 3 (present since M1). However, Phase 3 is the phase that **creates the registry**, making `build-time-vs-runtime.md` formally `[locked]` for the first time. This is the first invocation at which the doc is under enforcement. The contradiction between the locked doc's table and the code exists at HEAD and must be adjudicated now.

**Design Divergences check:**
The plan's `## Design Divergences` section is explicitly empty:
> `_(Divergences from a \`[locked]\` design doc. ... Empty.)_`
> `| — | — | — | _(empty — no divergences; the rule table is corrected in-change, see Phase 3)_ |`

No divergence is recorded for the `AsaApiLoader.exe` vs `ArkAscendedServer.exe` contradiction.

**no-duct-tape.md carve-out check:**
The "Intentional Test-First Breaks (Planned RED Repros)" carve-out in `no-duct-tape.md` could theoretically exempt a deferred code state — but only when all four conditions hold:
1. Anchored to a same-plan fixing phase or ledger row ✓ (Phase 4 in the same active plan)
2. A RED test locks the break ✗ — **no locking test exists**. `## Planned RED Repros` is explicitly empty.
3. Zero independent production exposure — unclear; the toggle `ENABLE_ASAAPI` doesn't yet exist (Phase 4 adds it), so there's no kill switch on the current launcher path
4. Honestly documented in-code — partial (plan documents Phase 4 flip, but no in-code marker)

**Condition 2 fails.** The carve-out requires a locking RED test; none exists. The carve-out cannot apply. The contradiction is not exempted.

**FINDING — BLOCK:**
`build-time-vs-runtime.md` §The Split table, row "Launch `AsaApiLoader.exe` (NOT `ArkAscendedServer.exe`)" prohibits launching the vanilla binary. The code launches `ArkAscendedServer.exe`. No divergence recorded. No carve-out available (no locking RED test). This is a `[locked]` doc contradiction → **BLOCK**.

**Remediation paths (choose one):**
1. **Record a divergence** in `## Design Divergences` with a real rationale: name the concrete cost paid (e.g., "AsaApiLoader.exe cannot be tested until VC++ is verified present in the prefix — Phase 3 is the VC++ gate; Phase 4 is the flip gate. Launching the vanilla binary in Phase 3 avoids a chicken-and-egg boot failure: if AsaApiLoader.exe were the launch target before VC++ is confirmed installed, the first-boot failure mode is ambiguous. Concrete cost: the code contradicts the locked doc for one phase. Reversal trigger: Phase 4.") and add a note to the doc's table row clarifying this is the Phase 4 target, not the Phase 3 state.
2. **Amend the table row** to reflect the planned transition: "Launch `AsaApiLoader.exe` when `ENABLE_ASAAPI=1` (Phase 4+); `ArkAscendedServer.exe` is the Phase 3 interim (deferred — see Phase 4)." This makes the doc descriptively accurate at Phase 3 HEAD while preserving the architectural intent.
3. **Add the `ENABLE_ASAAPI` toggle now** (pull Phase 4 Step 1 forward) so the locked doc's intent is honoured in the code, just gated behind the toggle. This is the cleanest fix — the doc's prohibition is satisfied, the Phase 4 work still exists as the "verify AsaApi loads" gate, and the toggle is the explicit kill-switch the plan already planned.

Option 3 is the no-duct-tape recommendation (builds it right once), but Option 1 with a real rationale is the minimum acceptable fix to unblock.

---

### Doc 2: `docs/internal/decisions/0001-db-engine-mariadb.md` [locked]

**Domain:** DB engine choice (MariaDB 11.4 LTS), compose image tag, network isolation.

**Phase 3 changes vs ADR 0001:**
Phase 3 touches Dockerfile (VC++ installer layer), entrypoint.sh (install_vcredist function), build-time-vs-runtime.md (VC++ row), ADR 0002, and design-sources.md. None of these changes:
- Alter the MariaDB compose image tag
- Change the DB network isolation (no `ports:` added)
- Modify the ArkShop MySQL connection parameters
- Touch `docker-compose.yml` at all

ADR 0001 constraints checked:
- MariaDB 11.4 LTS pin: not touched ✓
- Internal-only (no host port): not touched ✓
- ArkShop connects via `mariadb:3306`: not touched ✓
- Economy DB backups deferred to m4-ops-tooling: not touched ✓

**Result: NO CONTRADICTION with ADR 0001.**

---

### Doc 3: `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` [locked]

This ADR is created in the Phase 3 diff itself and describes the exact pattern implemented. Checking for self-consistency:

**ADR 0002 declares:**
- `/opt/vcredist/VC_redist.x64.exe` baked in Dockerfile ✓ (`Dockerfile:61-64`)
- `install_vcredist()` in entrypoint.sh runs `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` ✓ (`entrypoint.sh:158`)
- Skip gate: presence of three runtime DLLs in `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` (not a bare marker) ✓ (`entrypoint.sh:152-155`: checks `msvcp`, `vcrt`, `vcrt1` all present AND marker)
- `.vcredist-installed` marker is a fast-path hint only, not the source of truth ✓ (`entrypoint.sh:145`: marker checked alongside DLL checks, not alone)
- `/opt/asaapi/` baked in Dockerfile; `deploy_plugins()` syncs each boot (clean-replace) ✓ (consistent with Phase 2)
- `build-time-vs-runtime.md` table row for VC++ amended ✓ (confirmed in the rule doc)

**One nuance on skip gate logic:**
ADR 0002 states: "Skip gate: presence of the three runtime DLLs in `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` (not a bare marker, which would falsely skip after a prefix reset)."

`entrypoint.sh:152-155`:
```bash
if [[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]; then
    echo "[entrypoint] VC++ 2019 redist already installed — skipping."
    return 0
fi
```

The fast-path requires BOTH marker AND all three DLLs. If the prefix is nuked (pfx/ reset), the DLLs disappear — the condition fails → re-triggers install correctly ✓. If the marker is absent but DLLs are present (e.g., marker lost but prefix intact), the fast-path fails → falls through to `proton run` → re-runs the installer unnecessarily but harmlessly (idempotent). The ADR says marker is "fast-path hint only"; the code requires both. This is slightly more conservative than described but not contradictory — the DLL presence check is still the source of truth (a marker-alone skip is impossible).

**Result: NO CONTRADICTION with ADR 0002.** The doc and code are self-consistent.

---

## Registry Format Audit

Per `~/.claude/memory/design-sources.md` §Registry Format:

Each entry must match: `- [locked] <glob> [— <domain note>]`

```
- [locked] .claude/rules/build-time-vs-runtime.md — (internal) hard rule ...
```
✓ Matches. Glob is a direct file path (not a wildcard), resolves to 1 file.

```
- [locked] docs/internal/decisions/0001-db-engine-mariadb.md     — (internal) ADR: ...
```
✓ Matches. Extra spaces before `—` are cosmetic, not a parse error. Glob resolves to 1 file.

```
- [locked] docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md — (internal) ADR: ...
```
✓ Matches. Glob resolves to 1 file.

All 3 entries valid. No `[aspirational]` entries. No parse errors. No declared-none. Registry is in "populated" state.

---

### Required Fixes (BLOCK)

1. **[.claude/rules/build-time-vs-runtime.md:§The Split table — "Launch AsaApiLoader.exe (NOT ArkAscendedServer.exe)" row]**
   WHAT: `entrypoint.sh:24` sets `SERVER_EXE` to `ArkAscendedServer.exe`; `entrypoint.sh:220` launches it via `proton run`. The vanilla binary is the active launch target at Phase 3 HEAD.
   CONTRADICTS: The table row explicitly states `Launch \`AsaApiLoader.exe\` (NOT \`ArkAscendedServer.exe\`)` with the parenthetical acting as a prohibition on the vanilla binary, not merely a placement note for the loader.
   DIVERGENCE RECORDED: no — `## Design Divergences` is explicitly empty.
   BLOCK REASON: `[locked]` doc table row prohibits launching `ArkAscendedServer.exe`; code does exactly that; no recorded divergence exempts it; the `no-duct-tape.md` planned-RED-repro carve-out cannot apply (no locking RED test — `## Planned RED Repros` is empty). Three remediation options in analysis above; minimum fix = record a real-rationale divergence in `## Design Divergences` naming the concrete cost (phase sequencing constraint) and reversal trigger (Phase 4).

### Concerns (aspirational contradictions — non-blocking)

None. The registry contains no `[aspirational]` entries; all three entries are `[locked]`.

### Project-vs-Global Overrides

N/A — single project registry, no scope conflict.

---

### Bottom Line

The VC++ bake-and-deploy pattern is clean — the amended rule and the new code are fully consistent, ADR 0002 is self-coherent, and the registry format is valid. The BLOCK is on a pre-existing table row that Phase 3's registry bootstrap just made formally enforceable for the first time: the locked doc says launch `AsaApiLoader.exe`, the code still launches `ArkAscendedServer.exe`, and `## Design Divergences` is empty. Fix is one of: record a real-rationale divergence, amend the table row to reflect the Phase 3 interim state, or pull the `ENABLE_ASAAPI` toggle forward from Phase 4.

OVERALL VERDICT: BLOCK
