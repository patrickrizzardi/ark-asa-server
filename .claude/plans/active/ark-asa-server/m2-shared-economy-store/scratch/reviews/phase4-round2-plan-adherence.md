# Plan Adherence Review: m2-shared-economy-store Phase 4 Round 2

## Plan Adherence Review: m2-shared-economy-store Phase 4

### Verdict: PASS

### Diff Scope
- Files changed: 5 (entrypoint.sh, docker-compose.yml, Dockerfile, .env.test.example, .env.prod.example)
- Lines added/removed: +130 / -7 (cumulative from base 29735d2; round-2 delta is entrypoint.sh only)
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example`
- Round context: Round 1 PASSed this reviewer; round-2 delta consists entirely of reviewer-mandated fixes from code-reviewer BLOCK (pdb gate logic + Xvfb fail-fast + comment restatement) and rules-compliance-reviewer BLOCK (main() Big-O annotation). The diff command covers the full cumulative range so the round-2 additions are visible alongside the round-1 base.

---

### Step-by-Step Audit

Phase 4 has 4 Steps. Steps 1–3 were MET in round 1 and are unchanged in the round-2 delta — carried forward below. Step 4 had its runtime boot evidence deferred to acceptance-verifier; no change to that status here.

**Step 1**: entrypoint: add `ENABLE_ASAAPI` default (`:= 1`) to the env block (~entrypoint.sh:20); define `LOADER_EXE=…/Binaries/Win64/AsaApiLoader.exe`.

**MET** (carried from round 1, unchanged in round-2 delta) — `entrypoint.sh` diff: `: "${ENABLE_ASAAPI:=1}"` in env-defaults block; `LOADER_EXE="${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe"` defined alongside `SERVER_EXE`. No regression in round-2 delta.

**Step 2**: At launch (entrypoint.sh:95): if `ENABLE_ASAAPI == 1`, `proton run "${LOADER_EXE}" "${query}" ${flags}`; else keep the vanilla `${SERVER_EXE}` path. Same `${query}`/`${flags}`.

**MET** (carried from round 1; round-2 delta ADDS to this step's area — see approach audit) — The launch branch is intact. Round-2 additions within this area:
- `ensure_modded_pdb()` call inserted into main() before the launch gate (guards the pdb-absent case for vanilla→modded flip, closing the code-reviewer BLOCK from round 1). Evidence: diff hunk `if [[ "${ENABLE_ASAAPI}" == "1" ]]; then ensure_modded_pdb; fi` after `install_vcredist`.
- Xvfb fail-fast guard added after the 50-iteration socket-wait loop. Evidence: `if [[ ! -S /tmp/.X11-unix/X0 ]]; then echo FATAL: Xvfb failed... exit 1; fi`.
- `ensure_modded_pdb()` function body added (new function, entrypoint.sh diff +56 lines in the new block after `install_vcredist()`).

These are all within Phase 4's declared work area (the launch block and its supporting logic) or are fixes to documented Deviation #3 (pdb conditional). No regression to the launch routing.

**Step 3**: compose: add `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` to `the-island.environment`; add the var to both `.env.*.example`.

**MET** (carried from round 1, unchanged in round-2 delta) — docker-compose.yml and both .env.*.example files unchanged from round 1. No regression.

**Step 4**: Boot on `dell` with `ENABLE_ASAAPI=1` and confirm AsaApi init in `ArkApi.log`; if it faults, debug with `WINEDEBUG=+err,+seh`.

**MET** (status unchanged from round 1) — The round-2 code changes are the entrypoint fixes to defects discovered during the dell boot. The deviations file documents the specific runtime faults observed (`nodrv_CreateWindow`, `[critical] Failed to read pdb`), the WINEDEBUG=+err,+seh debugging, and the fix confirmations ("log then showed `API was successfully loaded` + both plugins loaded"). This step's runtime evidence file (`phase4-runtime-evidence.md`) remains the acceptance-verifier's domain — the round-2 delta does not change this picture. ACs remain unchecked pending formal receipt.

---

### Scope Audit

Phase 4 `Files (expected scope)`: `entrypoint.sh`, `docker-compose.yml`, `.env.test.example`, `.env.prod.example`

Round-2 delta (entrypoint.sh only):

- `entrypoint.sh`: **IN SCOPE** — the round-2 delta is 100% in entrypoint.sh, which is the primary in-scope file for Phase 4. All additions are within the declared work area (launch block, supporting functions, env block).
- `docker-compose.yml`: **IN SCOPE** (unchanged in round 2; carries round-1 changes; status unchanged).
- `.env.test.example`: **IN SCOPE** (unchanged in round 2; carries round-1 changes; status unchanged).
- `.env.prod.example`: **IN SCOPE** (unchanged in round 2; carries round-1 changes; status unchanged).
- `Dockerfile`: **DEVIATION (DOCUMENTED)** (unchanged in round 2; carries round-1 Deviation #1; status unchanged — unzip apt layer, documented in phase4-deviations.md).

The coordinator stated the round-2 delta is entrypoint.sh only. The diff confirms this — only entrypoint.sh has new additions beyond what round 1 produced. No new files touched. No new scope deviations.

Files in expected scope NOT touched in round-2 delta: `docker-compose.yml`, `.env.test.example`, `.env.prod.example` — intentional; round-2 fixes were confined to entrypoint.sh per reviewer mandates.

---

### Approach Audit

Round-1 approach deviations #2 (Xvfb) and #3 (pdb conditional) are carried forward and their documentation is unchanged. The round-2 delta adds remediation for the code-reviewer BLOCK on the pdb approach — specifically the `ensure_modded_pdb()` function that closes the vanilla→modded flip gap. This is not a new approach deviation; it is a fix that makes Deviation #3's stated intent actually work under the adversarial ordering the code-reviewer identified.

1. "Same `${query}`/`${flags}`" (Step 2 approach hint) → **MATCHED** (carried from round 1, no regression — `proton run "${launch_exe}" "${query}" ${flags}` unchanged).

2. Deviation #2 (Xvfb) — **DEVIATED-WITH-REASON** (carried from round 1). Round-2 adds the Xvfb fail-fast guard (the FATAL exit when the socket doesn't appear after 50 iterations). This is a direct response to code-reviewer Concern #1 (elevated to fix-mandate by the coordinator). The guard is within the loader branch, vanilla path untouched. No new deviation — this is robustness within the already-documented Xvfb approach.

3. Deviation #3 (pdb conditional) — **DEVIATED-WITH-REASON** (carried from round 1, remediated in round 2). The code-reviewer round-1 BLOCK identified that the pdb-shed was gated on first-install state rather than the toggle, meaning a vanilla→modded flip would silently boot with no plugins. Round-2 adds `ensure_modded_pdb()` (called in main() only when `ENABLE_ASAAPI=1`) which: (a) returns early if pdb exists (common path), (b) runs steamcmd validate up to 3 times if absent, (c) verifies the pdb file after each attempt — trusting the artifact, not the exit code — (d) fatal-exits with a clear message if still absent after 3 attempts. This closes the adversarial ordering gap the code-reviewer identified. The approach is aligned with the plan's "verify the artifact, not the exit code" discipline (Decision Ledger style, entrypoint.sh's existing SERVER_EXE check at ~line 40). No new deviation introduced.

4. Comment restatement (code-reviewer Concern #4 / round-1 BLOCK mandate): The diff at lines 44-48 replaces the stale pdb comment ("shed ~6GB we never need on a headless server") with a correct multi-line comment explaining the conditional logic and the vanilla→modded flip path handled by `ensure_modded_pdb()`. This matches the round-1 mandate verbatim: "the comment must be re-stated to match whatever invariant you land on." **MATCHED.**

5. main() Big-O (rules-compliance-reviewer round-1 BLOCK): Diff adds `# Time: O(1) compute; boot is I/O-dominated (steamcmd update + pdb restore up to 3 calls, Proton game load, Xvfb socket poll bounded to 50 × 0.1s)  Space: O(1)` immediately after `main() {`. This addresses the rules-compliance BLOCK exactly — the annotation covers the Xvfb poll loop (bounded O(1)), the pdb restore loop (up to 3 I/O calls), and the dominant I/O costs. **MATCHED.**

N/A lines for new approach hints: no new approach hints were introduced in the round-2 delta beyond what was already documented.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

Phase 4 has 3 ACs (all remain unchecked `[ ]` — no plan-file checkbox changes in round-2 delta):

- **AC1**: "With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / 'loaded' lines), no fatal load error."
  **Yes (stronger than round 1)** — `ensure_modded_pdb()` removes the last structural path that could produce `[critical] Failed to read pdb` (the vanilla→modded flip case). The deviations file's D3 rationale states "log then showed `API was successfully loaded` + both plugins loaded" after the pdb was restored. Formal log receipt still required from acceptance-verifier.

- **AC2**: "The server still reaches 'has successfully started' / advertises for join (the M1 success signal) under the loader."
  **Unclear** (same as round 1) — code supports it; no formal runtime receipt file exists. Cross-flag to acceptance-verifier.

- **AC3**: "With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild."
  **Yes (structurally)** — `ensure_modded_pdb()` is gated on `ENABLE_ASAAPI == "1"` in main(); Xvfb block unchanged (loader-branch only); vanilla `else` branch unchanged from round 1. Byte-for-byte M1 path preserved.

---

### Out-of-Scope Content Creep

Round-2 delta is confined to entrypoint.sh. The additions are:

1. `ensure_modded_pdb()` function body (~56 lines) — directly addresses the code-reviewer round-1 BLOCK at entrypoint.sh:33-52. In-scope: Phase 4 declared work area (launch prerequisites). Called only from main() under the ENABLE_ASAAPI=1 guard. No unrelated functions modified.

2. `ensure_modded_pdb()` call in main() — 3-line `if` block. In-scope.

3. Xvfb fail-fast guard (~5 lines after socket-wait loop) — directly addresses code-reviewer Concern #1 (which the coordinator treated as a BLOCK mandate given Rule 11). In-scope: within the Xvfb block of the loader branch that Deviation #2 already covered.

4. main() Big-O annotation (1 comment line) — directly addresses rules-compliance round-1 BLOCK. In-scope.

5. Restated pdb comment at lines 44-48 — directly addresses code-reviewer round-1 Concern #4 (flagged as comment rot post-fix). In-scope.

No refactoring of unrelated functions observed. No helper utilities added that aren't called by the in-scope flow. No style-only line touches outside the mandated work. **None observed.**

---

### Deviation Rationale Phrase Check

Round-2 delta introduces no new documented deviations. The three existing deviations (D1, D2, D3) from `phase4-deviations.md` are unchanged and were already checked clean in round 1.

**Round-2 additions are fixes to existing deviations, not new deviations.** No new deviation rationale text to check.

Round-1 verdict carried: **All rationales clean — no banned phrases detected.**

Mechanical re-confirm for any new prose in the round-2 delta against banned phrases:

The `ensure_modded_pdb()` function comments include: "A volume first-installed with ENABLE_ASAAPI=0 sheds the pdb and writes .installed, so subsequent boots with ENABLE_ASAAPI=1 skip install_or_update entirely and would launch into the silent failure without this gate." — No banned phrases. The phrase "silent failure" is a description of a real defect being fixed, not an "acceptable for now" framing.

The restated pdb comment includes: "A volume first-installed as vanilla (pdb absent) that later flips to ENABLE_ASAAPI=1 is handled by ensure_modded_pdb() at the launch gate — it restores the pdb via steamcmd validate (~2.0 GB) without requiring a manual intervention or a full reinstall." — No banned phrases.

**All new prose in round-2 delta is clean — no banned phrases detected.**

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

[Plan has `roadmap: ark-asa-server` and `milestone: m2-shared-economy-store` front-matter. Capability ledger at `.claude/plans/active/ark-asa-server/capability-ledger.md` confirmed. Phase 4 `**Scope Boundary**` block present.]

Phase 4 Scope Boundary in-scope: `"Launch flips to AsaApiLoader.exe (not ArkAscendedServer.exe)"` (ledger row confirmed: `m2-shared-economy-store | planned`).

Round-2 delta is confined to entrypoint.sh (in-scope file). All additions are:
- `ensure_modded_pdb()` — implementation of the declared "Launch flips to AsaApiLoader.exe" capability's prerequisite gate (pdb must be present for AsaApi to load; without it the flip silently fails). Within declared Scope Boundary.
- Xvfb fail-fast guard — within the already-documented Deviation #2 (Xvfb, part of making the loader branch work). Within declared Scope Boundary.
- main() Big-O + comment restatement — documentation/annotation within in-scope function. Within declared Scope Boundary.

No new capability-ledger rows are touched or partially implemented. No m3-cluster or m4-ops-tooling work appears in the round-2 delta.

`Scope-escape: CLEAR — no escapes detected; all round-2 diff work falls within the declared Scope Boundary ("Launch flips to AsaApiLoader.exe") and directly addresses round-1 reviewer mandates.`

---

### Required Fixes (BLOCK summary — empty if PASS)

None — all plan steps MET, scope respected, round-2 reviewer mandates addressed, no new undocumented deviations introduced.

---

### Bottom Line

The round-2 delta is exactly what was prescribed — `ensure_modded_pdb()` closes the vanilla→modded flip gap the code-reviewer caught, the Xvfb fail-fast turns a confusing crash loop into a one-line root cause, main() gets its Big-O, and the stale comment is updated to match the code. No scope drift, no silent deviations, no surprises. Staying in our lane.
