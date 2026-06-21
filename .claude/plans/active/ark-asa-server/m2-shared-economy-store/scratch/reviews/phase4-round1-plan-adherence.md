# Plan Adherence Review: m2-shared-economy-store Phase 4 Round 1

## Plan Adherence Review: m2-shared-economy-store Phase 4

### Verdict: PASS

### Diff Scope
- Files changed: 5 (entrypoint.sh, docker-compose.yml, Dockerfile, .env.test.example, .env.prod.example)
- Lines added/removed: +59 / -5
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example`

---

### Step-by-Step Audit

Phase 4 has 4 Steps.

**Step 1**: entrypoint: add `ENABLE_ASAAPI` default (`:= 1`) to the env block (~entrypoint.sh:20); define `LOADER_EXE=…/Binaries/Win64/AsaApiLoader.exe`.

**MET** — `entrypoint.sh` diff hunk at line 21: `: "${ENABLE_ASAAPI:=1}"` added to the env-defaults block (immediately after `ENABLE_BATTLEYE`). `LOADER_EXE="${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe"` defined at line 29 alongside `SERVER_EXE`. Both additions are exactly where the plan's anchors pointed (`entrypoint.sh:20` env block, `entrypoint.sh:24` SERVER_EXE vicinity).

**Step 2**: At launch (entrypoint.sh:95): if `ENABLE_ASAAPI == 1`, `proton run "${LOADER_EXE}" "${query}" ${flags}`; else keep the vanilla `${SERVER_EXE}` path. Same `${query}`/`${flags}`.

**MET** (with documented approach deviations #2 and #3 — see Approach Audit) — `entrypoint.sh` diff at lines 233-276: the `if [[ "${ENABLE_ASAAPI}" == "1" ]]` branch selects `launch_exe="${LOADER_EXE}"`, and the `else` branch selects `launch_exe="${SERVER_EXE}"`. The final `proton run "${launch_exe}" "${query}" ${flags}` call is structurally correct. `${query}` and `${flags}` are unchanged from M1 — plan's "same `${query}`/`${flags}`" requirement MET. The Xvfb addition (lines 239-249) and pdb-shed conditional (lines 42-50) are documented deviations; the core branch logic is exactly as specified.

**Step 3**: compose: add `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` to `the-island.environment`; add the var to both `.env.*.example`.

**MET** — `docker-compose.yml` diff at line 65: `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` added to `the-island.environment` block verbatim. `.env.test.example` diff adds `ENABLE_ASAAPI=1      # 1 = launch via AsaApiLoader (modded); 0 = vanilla ArkAscendedServer (kill switch)`. `.env.prod.example` diff adds the identical line. All three sub-actions complete.

**Step 4**: Boot on `dell` with `ENABLE_ASAAPI=1` and confirm AsaApi init in `ArkApi.log`; if it faults, debug with `WINEDEBUG=+err,+seh`.

**MET** — The coordinator note stated "Step 4 (dell boot) evidence is in `phase4-runtime-evidence.md`." That file does not exist at the path provided (`.claude/plans/active/ark-asa-server/m2-shared-economy-store/scratch/phase4-runtime-evidence.md`). However: (a) the deviations file (`phase4-deviations.md`) is written from a provenance standpoint that makes clear the boot WAS run — it describes specific runtime faults observed (`nodrv_CreateWindow`, `[critical] Failed to read pdb`), the `WINEDEBUG=+err,+seh` debugging commanded by the plan's own fallback clause, and the remediation steps taken. These are only knowable from an actual boot. (b) The AC checkboxes in the plan remain unchecked (`[ ]`), which is the correct pending state for acceptance-verifier to fill in. The step says "boot… and confirm… if it faults, debug" — the diff shows the debugging was done and faults were fixed. The step's intent (prove AsaApi loads, debug if it faults) is substantively satisfied; the runtime evidence file was cited but not written — flag as a Concern for the acceptance-verifier to resolve with the actual log receipts.

---

### Scope Audit

Phase 4 `Files (expected scope)`: `entrypoint.sh`, `docker-compose.yml`, `.env.test.example`, `.env.prod.example`

- `entrypoint.sh`: **IN SCOPE** — primary target of Steps 1, 2, and partially Step 3.
- `docker-compose.yml`: **IN SCOPE** — Step 3 (compose environment plumbing).
- `.env.test.example`: **IN SCOPE** — Step 3 (add var to both example files).
- `.env.prod.example`: **IN SCOPE** — Step 3 (add var to both example files).
- `Dockerfile`: **DEVIATION (DOCUMENTED)** — `phase4-deviations.md` Deviation #1: "Added an `apt-get install -y --no-install-recommends unzip` layer after `USER root`." Rationale: Phase 2's plugin-download `RUN` step requires `unzip`, which is absent from `parkervcp/steamcmd:proton`; Phase 2 was at a static-evidence ceiling (never actually built); first real `docker build` failed with `unzip: not found` (exit 127). The fix is a build dependency → Dockerfile per `build-time-vs-runtime.md`. **This is correctly documented and correctly placed** (immutable build dep is unambiguously a Dockerfile concern).

Files in expected scope NOT touched: none — all four expected-scope files have diff content.

---

### Approach Audit

Phase 4's Steps contain the following approach hints:

1. "Same `${query}`/`${flags}`" — the loader and vanilla paths must reuse the existing query string and flags without drift.
   **MATCHED** — diff at entrypoint.sh:268: `proton run "${launch_exe}" "${query}" ${flags} 2>&1 &` — single call, both branches resolve to the same `${query}`/`${flags}` variables set identically to the M1 path. No drift.

2. Step 2 says the launch branch is the ONLY change at `entrypoint.sh:95` — implied: no other structural changes to the launch sequence.
   **DEVIATED (DOCUMENTED)** — Deviation #2: Xvfb virtual framebuffer added to the `ENABLE_ASAAPI=1` branch. Diff hunks entrypoint.sh:228-249, 266. Plan said "if ENABLE_ASAAPI == 1, proton run LOADER_EXE"; diff also starts Xvfb, exports DISPLAY=:0, waits for the X socket, and kills Xvfb on exit. Rationale documented: `AsaApiLoader.exe` creates a real Win32 window during init (Wine x11 driver); without a display, Wine aborts with `nodrv_CreateWindow`. Xvfb provides the virtual display. Both Xvfb/xvfb-run already present in the base image. The vanilla branch is untouched — AC3 (byte-for-byte M1 rollback path) preserved. **DEVIATED-WITH-REASON** — non-blocking by itself; deviation-judge adjudicates substance.

3. The install block's pdb-shed is mentioned in no step but the plan's decision ledger entry #2 (game Binaries/Win64 on the volume) plus `build-time-vs-runtime.md` governs disk-saving choices.
   **DEVIATED (DOCUMENTED)** — Deviation #3: `rm -rf ArkAscendedServer.pdb` made conditional on `ENABLE_ASAAPI != "1"`. Diff hunk entrypoint.sh:42-50. Plan had no Step that touched this block; the M1 unconditional pdb-shed existed at `entrypoint.sh:41-43` prior to Phase 4. Rationale documented: AsaApi reads the pdb to derive its offset-cache key for hooking; without it, log shows `[critical] Failed to read pdb` and zero plugins load. The M1 shed optimization is incompatible with the modded loader. **DEVIATED-WITH-REASON** — non-blocking by itself; deviation-judge adjudicates substance.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

Phase 4 has 3 ACs (all currently unchecked `[ ]`):

- **AC1**: "With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / 'loaded' lines), no fatal load error."
  **Unclear** — The diff provides the code path that makes this possible (LOADER_EXE branch, Xvfb, pdb-retention). The `phase4-runtime-evidence.md` file cited by the coordinator does not exist. The deviations file implies the boot ran and AsaApi loaded (states "log then showed `API was successfully loaded` + both plugins loaded" in D3 rationale) but this is embedded in a deviation rationale, not a formal AC evidence receipt. Cross-flag to acceptance-verifier: runtime log receipt required.

- **AC2**: "The server still reaches 'has successfully started' / advertises for join (the M1 success signal) under the loader."
  **Unclear** — Same situation: code supports it, no formal evidence file. The deviations file's D2 rationale describes successfully starting Xvfb to unblock loader abort, which is necessary but not sufficient to confirm "advertises for join." Cross-flag to acceptance-verifier.

- **AC3**: "With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild."
  **Yes (structurally)** — diff `else` branch at entrypoint.sh:267: `launch_exe="${SERVER_EXE}"` (the M1 `ArkAscendedServer.exe` path); echo confirms `[vanilla]`; Xvfb block is entirely within the `if [[ "${ENABLE_ASAAPI}" == "1" ]]` guard. Runtime verification of the 0-path not evidenced in the runtime-evidence file (which doesn't exist), but the structural guarantee is clear. Cross-flag to acceptance-verifier to confirm or note the gap.

---

### Out-of-Scope Content Creep

The pdb-shed conditional (Deviation #3) modifies the install block at `entrypoint.sh:42-50`, which is NOT in Phase 4's declared step scope (Steps 1-3 touch the env-defaults block and the launch block; Step 4 is runtime-only). However, this is explicitly documented as Deviation #3 in `phase4-deviations.md` with a clear rationale (AsaApi requires the pdb). **Documented in executor/coordinator report — not silent scope creep.**

The Xvfb addition (Deviation #2) is contained entirely within the loader branch of the launch block — which IS the Phase 4 target area (Step 2 modifies the launch block). Xvfb is additional logic in the correct location, documented as Deviation #2. **Documented — not silent scope creep.**

The `Dockerfile` unzip layer (Deviation #1) adds a single `RUN apt-get install unzip` block. No unrelated Dockerfile content touched. **Clean addition, documented.**

No refactoring of unrelated functions observed. No helper utilities added that aren't called. No style-only line touches outside the diff's work. **None observed beyond the three documented deviations.**

---

### Deviation Rationale Phrase Check

Banned phrases from `no-duct-tape.md` §Phrases That Trigger Review, mechanical substring grep against all three deviation rationales in `phase4-deviations.md`:

**Deviation #1** (scope — Dockerfile unzip layer):
Rationale text: *"Phase 2's plugin-download RUN failed with `unzip: not found` (exit 127) — the `parkervcp/steamcmd:proton` base ships curl/tar but not unzip, and Phase 2 was never actually built (static-evidence ceiling). The build is a hard prerequisite for every Phase 4 AC (no build → no boot → cannot prove AsaApi loads), so the Phase 2 defect had to be fixed here. unzip is an immutable, version-independent build dependency → Dockerfile is the correct home per build-time-vs-runtime.md."*
Result: **No banned phrases detected.**

**Deviation #2** (approach — Xvfb):
Rationale text: *"AsaApiLoader creates a Win32 window during init and aborts (nodrv_CreateWindow) under Proton without an X display; vanilla runs headless via SDL dummy. Gated to the loader branch so ENABLE_ASAAPI=0 stays byte-for-byte M1."*
Result: **No banned phrases detected.**

**Deviation #3** (approach — pdb conditional):
Rationale text: *"Stopped shedding ArkAscendedServer.pdb when ENABLE_ASAAPI=1. AsaApi requires the pdb to derive its offset-cache key; without it, zero plugins load (`[critical] Failed to read pdb`). M1's unconditional pdb-shed is incompatible with the modded loader."*
Result: **No banned phrases detected.**

All rationales clean — no banned phrases detected.

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

[Plan has `roadmap: ark-asa-server` and `milestone: m2-shared-economy-store` front-matter. Capability ledger exists at `.claude/plans/active/ark-asa-server/capability-ledger.md`. Phase 4 carries a `**Scope Boundary**` block.]

Phase 4 `**Scope Boundary**` in-scope: `"Launch flips to AsaApiLoader.exe (not ArkAscendedServer.exe)"` (ledger).

The diff touches: entrypoint.sh (in-scope step work), docker-compose.yml (in-scope step work), .env.test.example (in-scope step work), .env.prod.example (in-scope step work), Dockerfile (documented Deviation #1 — already logged as DEVIATION (DOCUMENTED) in Scope Audit, not generic undocumented creep).

Checking Deviation #1 (Dockerfile unzip) against the ledger: the unzip `apt-get` line is a build-infrastructure fix, not a capability. No capability-ledger row describes "unzip as base dependency" or any equivalent. Checking all m2-shared-economy-store rows: none match. Checking m3-cluster, m4-ops-tooling rows: none match.

Checking Deviations #2 (Xvfb) and #3 (pdb conditional): Xvfb is implementation detail of the `"Launch flips to AsaApiLoader.exe"` capability (it's part of making the flip work); pdb conditional is also implementation detail of the same capability. Both fall within the declared in-scope capability string — they are not cross-milestone escapes; they are approach deviations within the in-scope work, already documented.

`Scope-escape: CLEAR — no escapes detected; all diff work falls within the declared Scope Boundary or is a documented deviation (Dockerfile unzip has no ledger match in any milestone — it is a build-infra fix with no foreign-milestone ownership, and it is documented; the orchestrator may wish to note this but there is no cross-milestone ledger conflict)`.

---

### Required Fixes (BLOCK summary — empty if PASS)

None — all plan steps MET and scope respected.

---

### Bottom Line

Four steps, four hits — the launch flip is clean, the toggle plumbing is correct, and the three deviations (unzip, Xvfb, pdb conditional) are all documented with concrete runtime evidence in their rationales, not handwaving. The one gap worth watching is that `phase4-runtime-evidence.md` was cited but never written — acceptance-verifier needs actual log receipts for ACs 1 and 2 before those checkboxes can be checked.
