# Plan Adherence Review: m2-shared-economy-store Phase 2 Round 3

### Verdict: PASS

---

### Diff Scope

- Files changed: 4 (`notes.md`, `plan.md`, `Dockerfile`, `entrypoint.sh`) — but only `Dockerfile` and `entrypoint.sh` are in Phase 2's declared scope. `notes.md` and `plan.md` are plan-folder housekeeping; all plan-folder files are standard coordinator churn between phases and rounds.
- Lines added/removed in scope files: `Dockerfile` +1 comment word (reword of Dockerfile:34 doc-pin comment); `entrypoint.sh` +1 comment line (Big-O annotation at entrypoint.sh:66).
- Diff source: `git diff 21fe5a8` (working tree vs Phase 1 committed SHA, as directed by coordinator)

**Round 3 context**: This is a polish-only pass. The two changes since round 2 are:
1. `entrypoint.sh:66` — Big-O comment added to `deploy_plugins()` header: `# Time: O(n)  Space: O(n) where n = plugin count (2-5 in practice)`
2. `Dockerfile:34` — `PERMISSIONS_VERSION` doc-pin comment reworded to explicitly reference `ASAAPI_VERSION`: `# doc-pin only — Permissions ships bundled in the AsaApi zip; no separate download, no URL interpolation. Records which Permissions version the pinned AsaApi (ASAAPI_VERSION) carries.`

Both are comment-only edits. No logic, no control flow, no new files. Confirmed by reading the live files: `Dockerfile` line 34 and `entrypoint.sh` line 66 match exactly what the coordinator described.

---

### Step-by-Step Audit

Phase 2 has 4 steps per the plan.

1. **Resolve the distribution channel FIRST — find a scriptable, non-interactive download URL for pinned AsaApi v1.21, ArkShop, and Permissions binaries; record the choice + pinned versions in plan notes before proceeding**: MET — `notes.md` §Phase 2 — distribution channel resolution records: ark-server-api.com confirmed non-auth-gated via live `curl`; versioned URLs `?version=1.21` (AsaApi) and `?version=1.4` (ArkShop) tested and live; Permissions confirmed bundled in AsaApi zip (no separate download). Pinned versions ASAAPI_VERSION=1.21, ARKSHOP_VERSION=1.4, PERMISSIONS_VERSION=1.1 recorded. (No round-3 change touches this step — it was MET in round 2 and remains MET.)

2. **Dockerfile: add ARG pins (ASAAPI_VERSION=1.21, ARKSHOP_VERSION=…, PERMISSIONS_VERSION=…) and RUN steps (as root) to download + unzip into /opt/asaapi/ with the AsaApi tree at the root and plugins under /opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/ (DLL name == folder name). chown -R container:container /opt/asaapi**: MET — `Dockerfile:32-54` delivers all three `ARG`s, the full `RUN` chain (mkdir → curl AsaApi → unzip → cp -r ArkApi → rm ONLY FOR DEVELOPERS dir → explicit cp of 6 root files → curl ArkShop → unzip → cp -r ArkShop/. → cleanup → find .pdb -delete → chown). DLL folder == folder name: `Permissions/Permissions.dll` (via `cp -r ArkApi`), `ArkShop/ArkShop.dll` (via `cp -r ArkShop/.`). Round-3 change: `Dockerfile:34` comment reword only — no ARG value or RUN logic changed.

3. **entrypoint: after install_or_update (entrypoint.sh:79) and before launch, add a deploy_plugins() that syncs /opt/asaapi/* into ${ARK_DIR}/ShooterGame/Binaries/Win64/ (binaries only; idempotent so the pinned image version always wins). The sync must cleanly replace the AsaApi/plugin tree on a version bump — stash configs → rm-then-copy ArkApi/ + loader paths. Do NOT touch the rest of Win64 (game files) or plugin config.json (config handled in Phase 5 — deploy the default config only on first boot if absent)**: MET — `entrypoint.sh:55-126` implements `deploy_plugins()` with the stash-rm-cp clean-replace strategy. Call site at `entrypoint.sh:155` (after `install_or_update`, before launch). Rm list scoped to AsaApi-owned paths only (`ArkApi/`, `AsaApiLoader.exe`, `AsaApiLoader.pdb`, `msdia140.dll`, `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `msvcp140.dll`). Seed-if-absent for `config.json` at entrypoint.sh:119-123. Round-3 change: `entrypoint.sh:66` Big-O annotation added to function header — comment only, zero logic change.

4. **Keep launch as ArkAscendedServer.exe (unchanged this phase)**: MET — no change to the launch line in this diff. `entrypoint.sh` launch path (`proton run "${SERVER_EXE}"`) untouched. Round-3 change does not touch the launch block.

All 4 steps: MET. No regressions introduced by the two polish edits.

---

### Scope Audit

**Files (expected scope)**: `Dockerfile`, `entrypoint.sh` (plan Phase 2 `Files (expected scope)` block).

Files touched by diff (vs `21fe5a8`):
- `Dockerfile`: IN SCOPE — comment reword at line 34 only. No logic change.
- `entrypoint.sh`: IN SCOPE — Big-O comment added at line 66 only. No logic change.
- `.claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md`: DEVIATION (DOCUMENTED) — plan-folder churn; Phase 2 round-2 gate entries written by coordinator. Standard executor pattern across all phases; not a silent scope addition.
- `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md`: DEVIATION (DOCUMENTED) — AC checkboxes ticked + Phase Review Gates filled in + Decision Ledger row #12 added (deviation-judge #1 directed re-homing). Coordinator-directed housekeeping.
- `.claude/state.md`: DEVIATION (DOCUMENTED) — radar counter update (12/88 done). Standard stop-hook maintenance.

**Files in expected scope NOT touched by round-3 diff**: None — both in-scope files (`Dockerfile`, `entrypoint.sh`) received the two targeted comment edits.

Scope is clean. Both plan-folder and state.md deviations are standard coordinator churn, consistent with the pattern documented across Phase 1 and Phase 2 round 2.

---

### Approach Audit

Phase 2 has explicit approach hints:

- **"stash configs → rm AsaApi-owned paths → cp fresh → restore configs" (plan Step 3 / Decision Ledger row #12)**: MATCHED — `entrypoint.sh:74-118` implements exactly this sequence. Round-3 comment edit (Big-O at line 66) does not alter the sequence; the comment describes it accurately.
- **"bake to /opt/asaapi/ at neutral path, entrypoint syncs onto volume" (plan Objective + anchor Dockerfile:20-24 + entrypoint.sh:74-77)**: MATCHED — Dockerfile:35-54 downloads to `/opt/asaapi/`; `entrypoint.sh:155` calls `deploy_plugins()` which syncs to Win64. No change in round 3.
- **"pinned versions via ARG, no auto-latest" (plan Step 2 + Scope Boundary)**: MATCHED — `Dockerfile:32-34` three ARGs with explicit values; both download URLs use `?version=${ARG}`. The round-3 Dockerfile:34 comment reword makes this MORE explicit by naming `ASAAPI_VERSION` in the comment text. No regression.
- **"DLL name == folder name" (plan Step 2)**: MATCHED — preserved by `cp -r`. Confirmed via coordinator probe (round 2). No round-3 change touches this.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

All 5 ACs were verified MET by `acceptance-verifier` in round 2. Checking for any round-3 regression:

- **AC1: Image contains /opt/asaapi/AsaApiLoader.exe + /opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/ at pinned versions**: Yes — Dockerfile logic untouched in round 3; comment-only change at line 34.
- **AC2: After a boot, volume's …/Binaries/Win64/ contains AsaApiLoader.exe + ArkApi/Plugins/{ArkShop,Permissions}/**: Yes — `deploy_plugins()` logic untouched; Big-O comment at line 66 is in the function header, not in the logic body.
- **AC3: Deploy step is idempotent**: Yes — stash-rm-cp sequence untouched.
- **AC4: Version bump cleanly REPLACES the deployed tree**: Yes — `rm -rf "${win64}/ArkApi"` untouched at entrypoint.sh:85.
- **AC5: Pinned versions recorded; no auto-latest fetch**: Yes — ARG values unchanged; round-3 comment reword at Dockerfile:34 STRENGTHENS this by noting the relationship between PERMISSIONS_VERSION and ASAAPI_VERSION.

No AC regressions. All 5 remain MET.

---

### Out-of-Scope Content Creep

Round-3 changes are two comments. Checking for anything beyond the two targeted edits:

- `Dockerfile:34`: Only the inline comment text changed. The `ARG PERMISSIONS_VERSION=1.1` value is unchanged. No other lines in Dockerfile were touched.
- `entrypoint.sh:66`: Only one comment line added (`# Time: O(n)  Space: O(n) where n = plugin count (2-5 in practice)`). The `deploy_plugins()` function body is byte-for-byte identical to round 2. No other lines in entrypoint.sh were touched.

None observed. These are surgically narrow edits.

---

### Deviation Rationale Phrase Check

The round-3 changes introduce no new deviations. The only deviations in this phase (plan.md and notes.md as out-of-scope plan-folder churn; clean-replace vs rsync; PERMISSIONS_VERSION doc-pin) were all adjudicated in round 2 with documented rationales.

Checking round-2 deviation rationales against the banned-phrase list from `no-duct-tape.md §Phrases That Trigger Review` for completeness (these rationales were already clean in round 2; re-running as a formality):

- **Decision Ledger row #12** ("rsync not guaranteed in parkervcp/steamcmd:proton base; under `set -euo pipefail` a missing rsync aborts with a confusing error; POSIX cp/rm always present"): No banned phrases. Concrete named cost (missing rsync + pipefail abort), concrete named advantage (POSIX always present). Clean.
- **PERMISSIONS_VERSION doc-pin comment** ("doc-pin only — Permissions ships bundled in the AsaApi zip; no separate download, no URL interpolation. Records which Permissions version the pinned AsaApi (ASAAPI_VERSION) carries."): No banned phrases. Factual — explains exactly what the ARG is and what it does. Clean.
- **notes.md / plan.md churn**: Standard coordinator maintenance, no rationale needed beyond "coordinator-directed."

All rationales clean — no banned phrases detected.

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

The plan has `roadmap: ark-asa-server` front-matter and a sibling `capability-ledger.md` exists. Phase 2 has a `**Scope Boundary**` block. Section 7 applies.

**Phase 2 Scope Boundary (in-scope capability strings, verbatim from plan)**:
- "AsaApi loader baked into image at pinned version"
- "ArkShop plugin baked into image at pinned version"
- "Permissions plugin baked into image (ArkShop dependency)"
- "Pinned plugin versions (rebuild-to-update)"

**Round-3 diff work** — two comment edits in `Dockerfile` and `entrypoint.sh`:

1. `Dockerfile:34` — comment reword on `PERMISSIONS_VERSION` ARG. This directly serves "Permissions plugin baked into image (ArkShop dependency)" and "Pinned plugin versions (rebuild-to-update)" — both in the declared Scope Boundary. IN SCOPE.
2. `entrypoint.sh:66` — Big-O annotation on `deploy_plugins()` header. `deploy_plugins()` is the runtime deploy step for "AsaApi loader baked into image at pinned version" + "ArkShop plugin baked into image at pinned version". IN SCOPE.

Both edits fall entirely within the declared Scope Boundary. No work outside the Scope Boundary boundary was introduced.

`Scope-escape: CLEAR — no escapes detected; all diff work falls within the declared Scope Boundary`

---

### Required Fixes (BLOCK summary)

None — all plan steps MET and scope respected.

---

### Bottom Line

Two comment edits, both within scope, both touching exactly the lines the coordinator called out, zero logic delta. The only thing that changed between round 2 and round 3 is that `deploy_plugins()` now tells you its complexity in the header and `PERMISSIONS_VERSION` now tells you which AsaApi version it's riding. Clean. PASS.
