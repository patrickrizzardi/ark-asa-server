# Plan Adherence Review: m2-shared-economy-store Phase 3 Round 2

### Verdict: PASS

### Diff Scope
- Files changed: 8
- Lines added/removed: +228 / -8
- Diff source: `git diff 1f9f1b7` (Phase 2 commit SHA, full cumulative diff)

**Round 2 context**: Round 1 PASSed with 6/6 Steps MET and Scope-escape CLEAR. Since then, three
targeted fixes were applied:
1. `entrypoint.sh` — `Space:` added to the Big-O annotation at line 141 (rules-compliance fix)
2. `entrypoint.sh` — `local rc=0 / proton run ... || rc=$?` pattern replaces bare `proton run` so
   `set -e` does not abort on benign installer exit codes 3010/1638 (code-reviewer concern elevated
   to fix per Rule 11)
3. `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — version-precision
   wording updated: explains `aka.ms/vs/16` is evergreen (14.x ABI-stable), names the tradeoff,
   clarifies "2019" is the product-name family label while the URL targets the 14.x merged redist
   (code-reviewer concern elevated to fix per Rule 11)
4. `plan.md` — `## Design Divergences` table populated by the coordinator with the
   AsaApiLoader-launch-deferred-to-Phase-4 entry (design-compliance fix)

All four changes are in-scope for Phase 3 (files within the declared expected scope or
coordinator/radar bookkeeping).

---

### Step-by-Step Audit

Phase 3 Steps (plan.md lines 379–384):

**Step 1**: "Dockerfile: download the VC++ 2019 (14.2x) redist `VC_redist.x64.exe` to `/opt/vcredist/` (as root), `chown container`."

**MET** — `Dockerfile:56-64` adds:
```
RUN mkdir -p /opt/vcredist \
 && curl -fsSL "https://aka.ms/vs/16/release/vc_redist.x64.exe" \
      -o /opt/vcredist/VC_redist.x64.exe \
 && chown -R container:container /opt/vcredist
```
`/opt/vcredist/VC_redist.x64.exe` matches the plan filename exactly; `chown container:container`
matches. The URL uses `vs/16` (the 2019/14.x endpoint per the corrected ADR wording); the "14.2x"
plan label is the product-family vocabulary and the ADR correctly explains the `vs/16` →
evergreen-14.x relationship. URL correction from round 1's `vs/17` to `vs/16` confirmed present.

**Step 2**: "entrypoint: add `install_vcredist()`. Gate the skip on the actual DLLs, not a bare marker — check for the three runtime DLLs in the prefix system32; if all present, skip. [...] When the DLLs are absent, run `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart`."

**MET** — `entrypoint.sh:129-184` adds `install_vcredist()`. Skip gate is conjunctive: marker AND
all three DLLs (`entrypoint.sh:151-155`). When DLLs absent, runs `proton run
/opt/vcredist/VC_redist.x64.exe /quiet /norestart` (`entrypoint.sh:163`). The round-2 fix is also
present: `local rc=0 / ... || rc=$?` captures the installer exit code without letting `set -e`
abort on benign 3010/1638 returns (`entrypoint.sh:162-165`). Comment explicitly names the benign
codes and states DLL check is the arbiter (`entrypoint.sh:159-161`). This matches the plan's
spirit ("verify the artifact, not the exit code"). Function is called at `entrypoint.sh:211` after
`deploy_plugins`.

**Step 3**: "After install, verify the three runtime DLLs landed (`${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/{msvcp140.dll,vcruntime140.dll,vcruntime140_1.dll}`) — fail fast with a clear message if not. A `.vcredist-installed` marker may be written as a fast-path hint, but the DLL presence check is the source of truth."

**MET** — `entrypoint.sh:167-177` builds a `missing=()` array checking all three DLLs; if
`${#missing[@]} -gt 0`, prints a `FATAL:` message with each missing filename and `exit 1`
(`entrypoint.sh:172-177`). Marker is written with `touch "${marker}"` only AFTER the DLL verify
passes (`entrypoint.sh:179`). DLL presence check is the source of truth per the plan; marker is
the fast-path hint. Precise match.

**Step 4**: "Amend `build-time-vs-runtime.md`: correct the 'Wine prefix + VC++ redist install' table row [...] Add a one-line note explaining the table previously assumed a prefix-in-image."

**MET** — `.claude/rules/build-time-vs-runtime.md` diff:
- Table row changed from `Dockerfile | pre-warm once → reproducible + fast boot` to
  `entrypoint (volume-backed prefix — see note) | Q1 yes: prefix lives on the mounted ark-game
  volume → entrypoint`
- 7-line note added below the table explaining the stale Dockerfile assumption, the 3-question
  test resolution, and pointing to ADR 0002.

**Step 5**: "Write ADR `0002-runtime-deploy-of-image-baked-artifacts.md` (the pattern: bake immutable artifacts in `/opt`, deploy/install onto the volume at runtime — covers VC++ AND plugins; cites the 3-question test)."

**MET** — `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` created
(+128 lines). Contains: frontmatter with `doc-type: adr`, Context section covering both VC++ and
plugin cases, the 3-question table applied to each, Decision section with both `/opt/vcredist/`
and `/opt/asaapi/` deployment descriptions, Rejected alternatives (4 alternatives evaluated),
Consequences with named tradeoffs including the evergreen-fetch-then-frozen VC++ tradeoff (the
round-2 version-precision fix). ADR 0002 covers both the VC++ AND plugin pattern as the plan
requires.

**Step 6**: "Bootstrap `.claude/design-sources.md`: register `build-time-vs-runtime.md` `[locked]` + ADR 0001/0002 `[locked]`."

**MET** — `.claude/design-sources.md` created (+8 lines):
```
- [locked] .claude/rules/build-time-vs-runtime.md — (internal) hard rule ...
- [locked] docs/internal/decisions/0001-db-engine-mariadb.md — (internal) ADR: MariaDB ...
- [locked] docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md — (internal) ADR: bake-in-image ...
```
All three `[locked]` registrations present. File created fresh (previously absent).

---

### Scope Audit

**Files (expected scope) per plan.md**: `Dockerfile`, `entrypoint.sh`, `.claude/rules/build-time-vs-runtime.md`, `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`, `.claude/design-sources.md`

Files touched by diff (8 total):

| File | Classification |
|---|---|
| `Dockerfile` | IN SCOPE |
| `entrypoint.sh` | IN SCOPE |
| `.claude/rules/build-time-vs-runtime.md` | IN SCOPE |
| `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` | IN SCOPE |
| `.claude/design-sources.md` | IN SCOPE |
| `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md` | COORDINATOR/RADAR BOOKKEEPING — not executor scope (as noted in coordinator scope note) |
| `.claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md` | COORDINATOR/RADAR BOOKKEEPING — not executor scope |
| `.claude/state.md` | COORDINATOR/RADAR BOOKKEEPING — stop-hook radar refresh; not executor scope |

Files in expected scope NOT touched: none — all 5 expected-scope files were modified.

Scope verdict: **all-within-scope**. The three bookkeeping files (`plan.md`, `notes.md`, `state.md`)
are coordinator/radar infrastructure explicitly excluded from executor scope per the coordinator's
scope note. No undocumented scope creep.

---

### Approach Audit

Phase 3 approach hints (from Steps):

**"Gate the skip on the actual DLLs, not a bare marker"** → MATCHED. `entrypoint.sh:151-155`
uses conjunctive check: `[[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]`.
The marker alone does not skip; all three DLLs must also be present.

**"fail fast with a clear message if not [DLLs present]"** → MATCHED. `entrypoint.sh:172-177` uses
`exit 1` with a FATAL-prefixed message naming each missing DLL and the expected path.

**"A `.vcredist-installed` marker may be written as a fast-path hint, but the DLL presence check is the source of truth"** → MATCHED. Marker written AFTER DLL verify (`entrypoint.sh:179`); fast-path requires both marker AND DLLs. Marker is a hint, not the gate.

**Round-2 approach (rc capture pattern, plan Step 2 "verify the artifact, not the exit code" discipline)** → MATCHED. `local rc=0 / proton run ... || rc=$?` at `entrypoint.sh:162-163`; DLL check at `entrypoint.sh:167-177` is explicitly the sole arbiter.

**One documented approach deviation (carried from round 1)**: conjunctive `marker AND DLLs` fast-path (plan Step 2 says skip when DLLs absent; implementation adds marker to the skip gate). Deviation-judge #1 PASSed this in round 1 as within the plan's "false-RUN not false-skip" envelope. The round-2 diff does not change this pattern.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

Phase 3 ACs (plan.md lines 386-393):

- **AC1: "After first boot, `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` contains `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`"**:
  Yes — `install_vcredist()` installs via `proton run VC_redist.x64.exe /quiet /norestart` and
  verifies all three DLLs before marking done. Static evidence ceiling (runtime boot on dell is
  Phase 3/4 boundary). Evidence: (filled at phase completion per plan).

- **AC2: "The install-skip is gated on actual DLL presence (not a bare marker); a second boot skips the install; a pfx/ reset correctly RE-triggers the install"**:
  Yes — conjunctive gate at `entrypoint.sh:151-155`; a pfx reset removes the DLLs, which fails
  the gate even if the marker file survives. Static evidence ceiling applies.

- **AC3: "`build-time-vs-runtime.md` table row for VC++/prefix amended to reflect volume-backed-prefix → entrypoint, with the rationale note"**:
  Yes — `.claude/rules/build-time-vs-runtime.md` row corrected + 7-line explanatory note added.
  Verifiable from diff directly (no runtime required).

- **AC4: "ADR `0002` exists (pattern + 3-question-test rationale); `.claude/design-sources.md` created registering the rule + both ADRs `[locked]`"**:
  Yes — both files created in the diff. Verifiable from diff directly.

---

### Out-of-Scope Content Creep

None observed. The round-2 fixes are surgical:

- `entrypoint.sh`: two changes in `install_vcredist()` only — `Space:` added to the Big-O comment
  at line 141, and the `rc` capture pattern replacing the bare `proton run` call. No unrelated
  function or line touched.
- `docs/internal/decisions/0002-...md`: new file; the version-precision fix is integrated into the
  Context and Consequences sections. No content outside Phase 3's ADR scope.
- `plan.md`: coordinator-populated `## Design Divergences` entry. Not executor scope.

No "while I'm here" refactoring, no unrelated style edits, no utility additions outside the phase.

---

### Deviation Rationale Phrase Check

**One documented deviation** (carried from round 1, unchanged in round 2):

**Deviation: conjunctive `marker AND DLLs` fast-path** (entrypoint.sh:151-155). Deviation-judge #1
rationale from round 1: "false-RUN not false-skip; within plan envelope." Checking this rationale
against the banned-phrase list from `no-duct-tape.md § Phrases That Trigger Review`:

Phrases checked (mechanical substring match, case-insensitive):
- "acceptable for now" — NOT FOUND
- "works in the current state" — NOT FOUND
- "fine until we add X" — NOT FOUND
- "executor will figure it out at code time" — NOT FOUND
- "we can revisit when Y happens" — NOT FOUND
- "current code only has one consumer" — NOT FOUND
- "we'll make it configurable later" — NOT FOUND
- "this case can't happen yet" — NOT FOUND
- "the existing X is close enough" — NOT FOUND
- "intentional approximation" — NOT FOUND
- "minor — acceptable to leave" — NOT FOUND
- "good enough for the MVP" — NOT FOUND
- "build the simple version now, do it right later" — NOT FOUND
- "rebuild this when X lands" — NOT FOUND
- "before requirement X exists there'll be an issue" — NOT FOUND
- "let's just scope this milestone to X" — NOT FOUND

**All rationales clean — no banned phrases detected.**

The `## Design Divergences` entry added to `plan.md` by the coordinator also checked:
"Hard phase-dependency, not duct tape" + "Named cost" + "Reversal/trigger" — no banned phrases.
Clean.

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

This plan has a `roadmap:` front-matter field (`roadmap: ark-asa-server`) and the initiative folder
contains a `capability-ledger.md`. Phase 3 carries a `**Scope Boundary**` block:

- **In scope**: "VC++ 2019 redist installed in the Proton prefix" (ledger).
- **Explicitly NOT delivered**: "Launch flips to `AsaApiLoader.exe`" → Phase 4.

All diff work in executor-owned files maps squarely to the "VC++ 2019 redist installed in the Proton
prefix" capability:
- `Dockerfile`: bakes `/opt/vcredist/VC_redist.x64.exe` (the installer)
- `entrypoint.sh`: `install_vcredist()` — installs into the prefix
- `.claude/rules/build-time-vs-runtime.md`: doc correction for the volume-backed-prefix reality
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`: ADR for the pattern
- `.claude/design-sources.md`: registry bootstrap (Step 6, explicitly scoped in Phase 3)

No work touches the "Launch flips to `AsaApiLoader.exe`" capability that is explicitly deferred.
No work touches any other ledger capability row.

`Scope-escape: CLEAR — no escapes detected; all diff work falls within the declared Scope Boundary`

---

### Required Fixes (BLOCK summary)

None — all plan steps MET and scope respected.

---

### Bottom Line

Three targeted fixes, zero scope drift. The `Space:` annotation lands where it was missing, the `rc` capture kills the `set -e` footgun before the DLL verify, and the ADR now correctly names the evergreen-fetch-then-frozen tradeoff instead of waving at "14.2x" and hoping nobody notices. Everything the plan asked for is present, nothing extra crept in, and the one documented approach deviation is unchanged from the round-1 PASS. Chief, we're clean.
