# Plan Adherence Review: m2-shared-economy-store Phase 4 Round 3

## Plan Adherence Review: m2-shared-economy-store Phase 4

### Verdict: PASS

### Diff Scope
- Files changed: 5 in cumulative diff vs 29735d2 (entrypoint.sh, docker-compose.yml, Dockerfile, .env.test.example, .env.prod.example)
- Round-3 delta: entrypoint.sh ONLY — 4 targeted hardening changes (Xvfb liveness check, pdb size-floor helper `pdb_ok()`, geometry comment, reworded install-time shed comment)
- Lines added/removed (cumulative from 29735d2): +152 / -7 approx; round-3 delta is ~+25 lines in entrypoint.sh
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example`
- Round context: Rounds 1 and 2 both PASSed this reviewer. Round-3 delta is exclusively reviewer/judge-mandated defensive hardening within entrypoint.sh:
  - rules-compliance round-2 BLOCK: geometry literal `1024x768x24` needed inline rationale
  - code-reviewer round-2 Concern #1 (elevated per Rule 11): Xvfb orphan on fail-fast exit + stale-socket dual-condition check
  - code-reviewer round-2 Concern #2 (elevated per Rule 11): presence-only pdb gate insufficient for truncated file
  - code-reviewer round-2 Concern #4 / round-1 carry-over: install-time shed comment restated to match conditional logic

---

### Step-by-Step Audit

Phase 4 has 4 Steps. Steps 1–3 were MET in rounds 1 and 2, and are UNCHANGED in the round-3 delta — carried forward. Step 4 (boot on dell / runtime evidence) is an acceptance-verifier concern and is structurally unchanged.

**Step 1**: entrypoint: add `ENABLE_ASAAPI` default (`:= 1`) to the env block (~entrypoint.sh:20); define `LOADER_EXE=…/Binaries/Win64/AsaApiLoader.exe`.

**MET** (carried from rounds 1–2, unchanged in round-3 delta) — `: "${ENABLE_ASAAPI:=1}"` present in env-defaults block (diff line `+: "${ENABLE_ASAAPI:=1}"`) and `LOADER_EXE="${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe"` defined. No regression in round-3 delta.

**Step 2**: At launch (entrypoint.sh:95): if `ENABLE_ASAAPI == 1`, `proton run "${LOADER_EXE}" "${query}" ${flags}`; else keep the vanilla `${SERVER_EXE}` path. Same `${query}`/`${flags}`.

**MET** (carried; round-3 additions within this step's area are scope-correct hardening — see Approach Audit) — Launch branch intact. Round-3 additions within this area:

- **Xvfb liveness check**: `kill -0 "${xvfb_pid}" 2>/dev/null || xvfb_dead=1` + `|| "${xvfb_dead}" -eq 1` added to the fail-fast guard. The check now catches BOTH absent socket AND dead Xvfb process (stale socket case). Evidence: entrypoint.sh lines 318-325 in the diff.
- **Xvfb cleanup on fail-fast**: `kill "${xvfb_pid}" 2>/dev/null || true` added inside the fatal-exit path. Cleans up the backgrounded Xvfb before `exit 1`. Evidence: line 323 in the diff.
- **Geometry comment**: "Geometry 1024x768x24 is an arbitrary conventional minimum: the loader only needs a valid display to create its init window; ASA/Wine render nothing (headless), so the actual resolution is ignored." inserted directly before the `Xvfb` launch line. Evidence: lines 302-303 in the diff.
- **Reworded install-time pdb shed comment**: the stale "shed ~6GB we never need on a headless server" replaced with a multi-line comment explaining the conditional logic and noting the `ensure_modded_pdb()` coverage of the vanilla→modded flip. Evidence: lines 44-50 in the diff.
- **`pdb_ok()` size-floor helper**: `pdb_ok() { [[ -f "${pdb}" ]] && [[ "$(stat -c%s "${pdb}" 2>/dev/null || echo 0)" -gt 1048576 ]]; }` — replaces (or rather, now IS) the pdb-presence check throughout `ensure_modded_pdb()`. The function rejects 0-byte or truncated pdb files; requires >1 MiB. Evidence: entrypoint.sh line 217 in the diff (inside `ensure_modded_pdb()`).

All five round-3 additions are within the declared Phase 4 work area (the launch block and its supporting functions). No regression to the launch routing. `proton run "${launch_exe}" "${query}" ${flags}` unchanged.

**Step 3**: compose: add `ENABLE_ASAAPI: ${ENABLE_ASAAPI:-1}` to `the-island.environment`; add the var to both `.env.*.example`.

**MET** (carried from rounds 1–2, unchanged in round-3 delta) — docker-compose.yml and both .env.*.example files show the correct additions. No regression.

**Step 4**: Boot on `dell` with `ENABLE_ASAAPI=1` and confirm AsaApi init in `ArkApi.log`; if it faults, debug with `WINEDEBUG=+err,+seh`.

**MET** (status unchanged from rounds 1–2) — The round-3 hardening is the hardened artifact of what was observed and fixed during the dell boot (documented in phase4-deviations.md). The deviations file records the WINEDEBUG=+err,+seh debugging, the specific faults (nodrv_CreateWindow, [critical] Failed to read pdb), and the confirmations ("API was successfully loaded" + both plugins loaded). Runtime receipt file (`phase4-runtime-evidence.md`) remains acceptance-verifier domain — no change.

---

### Scope Audit

Phase 4 `Files (expected scope)`: `entrypoint.sh`, `docker-compose.yml`, `.env.test.example`, `.env.prod.example`

Round-3 delta scope (entrypoint.sh only; all other files carry rounds 1-2 state unchanged):

- `entrypoint.sh`: **IN SCOPE** — the round-3 delta is 100% in entrypoint.sh, the primary in-scope file for Phase 4. All additions are within the declared work area (launch branch, `ensure_modded_pdb()`, env block, install-time shed comment).
- `docker-compose.yml`: **IN SCOPE** (unchanged in round 3; carries round-1 ENABLE_ASAAPI addition; status unchanged from prior rounds).
- `.env.test.example`: **IN SCOPE** (unchanged in round 3; carries round-1 ENABLE_ASAAPI addition).
- `.env.prod.example`: **IN SCOPE** (unchanged in round 3; carries round-1 ENABLE_ASAAPI addition).
- `Dockerfile`: **DEVIATION (DOCUMENTED)** (unchanged in round 3; carries round-1 Deviation #1 — unzip apt layer; documented in phase4-deviations.md under "Deviation #1 (scope)").

Files in expected scope NOT touched in round-3 delta: `docker-compose.yml`, `.env.test.example`, `.env.prod.example` — intentional; round-3 fixes were confined to entrypoint.sh per reviewer mandates.

No new files touched. No new scope deviations introduced. All-within-scope (for the round-3 delta).

---

### Approach Audit

Documented deviations #1, #2, #3 are carried from prior rounds; their documentation is unchanged. The round-3 delta refines the implementation of Deviation #2 (Xvfb) and the supporting code for Deviation #3 (pdb conditional) — these are hardening passes within already-documented approach deviations, not new approach deviations.

1. **"Same `${query}`/`${flags}`" (Step 2 approach hint)** → **MATCHED** (carried from rounds 1–2, no regression — `proton run "${launch_exe}" "${query}" ${flags}` unchanged).

2. **Deviation #2 (Xvfb) — DEVIATED-WITH-REASON** (carried; hardened in round 3):
   Round-3 strengthens the post-readiness check from socket-presence-only to a dual condition: socket present AND Xvfb process alive (`kill -0` probe). The round-2 code-reviewer identified the stale-socket case (socket file persists after Xvfb dies → `-S` passes → `proton run` hits ECONNREFUSED). Round-3 addresses it. Not a new deviation — a correct hardening of the already-documented Xvfb approach. The vanilla branch is untouched.

3. **Deviation #3 (pdb conditional) — DEVIATED-WITH-REASON** (carried; hardened in round 3):
   `pdb_ok()` replaces the former `[[ -f "${pdb}" ]]` presence-only gate throughout `ensure_modded_pdb()`. The round-2 code-reviewer Concern #2 identified that a truncated/partial pdb would pass a presence-only check, and AsaApi would SHA-256 a corrupt file → wrong cache key → silent zero-plugin load. The `stat -c%s` size-floor (>1 MiB) rejects 0-byte or truncated files while guaranteeing real ~6GB pdbs always pass. The comment within `pdb_ok()` explains the reasoning. Not a new deviation — remediation of the identified gap within the already-documented pdb approach.

4. **Geometry comment (rules-compliance round-2 BLOCK fix)** → **MATCHED** — the BLOCK required an inline rationale for `1024x768x24`. The round-3 diff adds a two-sentence block comment immediately before the `Xvfb` launch line explaining that the resolution is an arbitrary conventional minimum and that ASA/Wine render nothing in headless mode. The mandate asked for "any valid X geometry; 1024x768x24 is conventional minimum — Wine/ASA ignore the actual resolution"; round-3 delivers substantively identical coverage in a block comment (two sentences instead of an inline suffix). The substance matches the mandate exactly.

5. **Reworded shed comment (code-reviewer round-1/2 mandate)** → **MATCHED** — the stale "shed ~6GB we never need on a headless server (re-pulled only on a future validate)" comment has been replaced with a durable multi-line comment explaining: Movies/ is always shed; the pdb is conditional on ENABLE_ASAAPI; and the vanilla→modded flip case is handled by `ensure_modded_pdb()`. The new comment describes the current code's properties, not the diff that produced them. Durable; no changelog language.

No new approach hints or deviations in round 3.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

Phase 4 has 3 ACs — all remain unchecked `[ ]`, unchanged from rounds 1–2:

- **AC1**: "With `ENABLE_ASAAPI=1`, `…/Binaries/Win64/logs/ArkApi.log` shows AsaApi initialized (framework banner / 'loaded' lines), no fatal load error."
  **Yes (structurally stronger than round 2)** — `pdb_ok()` with size-floor now rejects a truncated pdb before any `proton run` attempt, eliminating the last structural path to the silent `[critical] Failed to read pdb` failure. The dell evidence (deviations file D3: "API was successfully loaded" + both plugins) is unchanged. Formal log receipt remains acceptance-verifier domain.

- **AC2**: "The server still reaches 'has successfully started' / advertises for join (the M1 success signal) under the loader."
  **Unclear** (unchanged from round 2) — code supports it; formal runtime receipt is acceptance-verifier domain.

- **AC3**: "With `ENABLE_ASAAPI=0`, launch is byte-for-byte the M1 vanilla path (`ArkAscendedServer.exe`) — rollback works with no rebuild."
  **Yes (structurally)** — `ensure_modded_pdb()` is gated on `ENABLE_ASAAPI == "1"` (unchanged); Xvfb block and liveness check are within the loader branch only (unchanged structure); `pdb_ok()` helper is defined inside `ensure_modded_pdb()` scope — unreachable from the vanilla path. Byte-for-byte M1 path preserved.

---

### Out-of-Scope Content Creep

Round-3 delta is confined to entrypoint.sh. The five additions are:

1. **`pdb_ok()` nested function** — defined inside `ensure_modded_pdb()` at entrypoint.sh:217; directly addresses round-2 code-reviewer Concern #2 (presence-only pdb gate). Called from exactly three points within `ensure_modded_pdb()` (early-return check, per-attempt check, post-loop check). No call sites outside this function. In-scope.

2. **Xvfb process-liveness check** (3 lines: `xvfb_dead=0`, `kill -0` probe, extended `if` condition) — directly addresses round-2 code-reviewer Concern #1/3 (stale socket). Within the loader branch of main(). In-scope.

3. **Xvfb cleanup on fail-fast** (1 line: `kill "${xvfb_pid}" 2>/dev/null || true` inside the fatal path) — companion to the liveness check; prevents Xvfb orphan on the `exit 1` path. In-scope.

4. **Geometry comment** (2 lines before `Xvfb :0 ...`) — directly addresses rules-compliance round-2 BLOCK. In-scope.

5. **Reworded install-time shed comment** (replaces 2 lines with ~6 lines at entrypoint.sh:44-50) — directly addresses code-reviewer mandate. In-scope.

No refactoring of unrelated functions. No helper utilities added outside the pdb-ok scope. No style-only line touches on lines unrelated to mandated work. **None observed.**

---

### Deviation Rationale Phrase Check

Round-3 delta introduces no new documented deviations. Deviations #1, #2, #3 from `phase4-deviations.md` are unchanged from round-2. The rationale texts were already checked clean in rounds 1 and 2.

Mechanical re-check on new prose in the round-3 delta against the `no-duct-tape.md` `## Phrases That Trigger Review` list:

Candidate text from round-3 additions:
- `pdb_ok()` comment: "A bare -f test passes a 0-byte or truncated pdb (e.g. steamcmd exhausted disk mid-download), which AsaApi then fails to SHA-256 — the exact silent-zero-plugin failure this function prevents. The real pdb is ~6GB; require >1 MiB to reject truncated files while never rejecting a real one." — No banned phrases.
- Geometry comment: "Geometry 1024x768x24 is an arbitrary conventional minimum: the loader only needs a valid display to create its init window; ASA/Wine render nothing (headless), so the actual resolution is ignored." — No banned phrases.
- Shed comment reword: "Shed assets a headless server never needs. Movies/ is the intro videos a headless server never plays. ArkAscendedServer.pdb (~6GB): kept on a fresh modded install, shed on a fresh vanilla install. A volume first-installed as vanilla (pdb absent) that later flips to ENABLE_ASAAPI=1 is handled by ensure_modded_pdb() at the launch gate — it restores the pdb via steamcmd validate without requiring a manual intervention or a full reinstall." — No banned phrases.
- Xvfb liveness comments: "Two ways Xvfb leaves us without a usable display, both ending in the same nodrv_CreateWindow abort we started Xvfb to prevent…" + "Require BOTH the socket present AND the Xvfb process still alive before proceeding. stderr was suppressed above, so these checks are the only signal we have." — No banned phrases.

**All new prose in round-3 delta is clean — no banned phrases detected.**

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

Plan has `roadmap: ark-asa-server` and `milestone: m2-shared-economy-store` front-matter. Capability ledger at `.claude/plans/active/ark-asa-server/capability-ledger.md` confirmed (loaded). Phase 4 `**Scope Boundary**` block present: in-scope capability = `"Launch flips to AsaApiLoader.exe (not ArkAscendedServer.exe)"` (ledger row: `m2-shared-economy-store | planned`).

Round-3 delta is confined to entrypoint.sh (in-scope file). All five additions are:
- `pdb_ok()` — size-floor gate within `ensure_modded_pdb()`, which is itself within the declared "Launch flips to AsaApiLoader.exe" capability (the gate prevents silent zero-plugin load on the launcher flip path).
- Xvfb liveness check + cleanup — within the Xvfb block of the loader branch (Deviation #2, documented, within the flip capability).
- Geometry comment + shed comment reword — documentation within in-scope functions/blocks.

No capability-ledger rows other than `"Launch flips to AsaApiLoader.exe (not ArkAscendedServer.exe)"` are touched or partially implemented. No m3-cluster, m4-ops-tooling, or unscoped work appears in the round-3 delta.

`Scope-escape: CLEAR — no escapes detected; all round-3 diff work falls within the declared Scope Boundary ("Launch flips to AsaApiLoader.exe (not ArkAscendedServer.exe)") and directly addresses round-2 reviewer mandates.`

---

### Required Fixes (BLOCK summary — empty if PASS)

None — all plan steps MET and scope respected.

---

### Bottom Line

Four surgical fixes, all mandated, all in entrypoint.sh, all in their right place. The pdb size-floor closes the truncated-pdb silent-failure path the code-reviewer caught, the liveness check closes the stale-Xvfb-socket trap, the geometry comment kills the rules-compliance BLOCK, and the shed comment now describes what the code actually does. Zero scope drift. Zero surprises. Round 3 cleans up round 2's outstanding items with no new damage.
