# Deviation Judge — Full Report
## Plan: ark-asa-server / m2-shared-economy-store | Phase 3, Round 2, Deviation #1

---

## Deviation summary

`install_vcredist()` uses a conjunctive fast-path (`marker AND all 3 DLLs present`) rather than the plan's stated "DLL presence alone" gate. Round 2 adds an rc-tolerant install block (`|| rc=$?` + rc-logging) with `missing[]` as the sole success arbiter, followed by `touch marker`. The re-judge probes the INTERACTION between this new install path and the conjunctive fast-path across multi-boot sequences.

---

## Adversarial inputs constructed

### Input 1 (primary — mixed rc-tolerance + partial-DLL scenario)
Installer exits rc=3010 (benign "reboot suppressed") but only 2 of 3 DLLs land — e.g., `vcruntime140_1.dll` fails to extract into the prefix.

**Trace:**
1. Fast-path (line 152): marker absent (first boot) → conjunctive check short-circuits to FALSE immediately on `[[ -f "${marker}" ]]` → falls through. Correct.
2. `proton run … || rc=$?` (line 164): exits rc=3010, rc captured, `set -e` neutralized by `||`. Correct.
3. Line 165–167: rc ≠ 0 logged. Execution continues.
4. `missing[]` check (lines 170–173): `vcruntime140_1.dll` absent → `missing+=("vcruntime140_1.dll")`.
5. Line 175–180: `${#missing[@]} -gt 0` → TRUE → `exit 1`. Marker never written.
6. Next boot: same path. No false-skip. **CORRECT.**

### Input 2 (marker written + single DLL later deleted — post-install volume mutation)
Boot 1 succeeds: all 3 DLLs verified, `touch marker` at line 182 fires. Between boots, an operator or Proton update deletes `vcruntime140.dll` from the prefix (e.g., partial prefix reset that clears `system32/` but not the parent `STEAM_COMPAT_DATA_PATH/` directory).

**Trace:**
1. Fast-path (line 152): `[[ -f "${marker}" ]]` → TRUE. `[[ -f "${msvcp}" ]]` → TRUE. `[[ -f "${vcrt}" ]]` → `vcruntime140.dll` ABSENT → FALSE. Conjunctive check fails → falls through to install. **CORRECT — no false-skip.**
2. Install re-runs, DLL-presence verify runs again after install.

### Input 3 (SIGKILL mid-install, before touch marker)
Container is OOM-killed or Docker stops while `proton run` is executing on first boot. Marker has never been written.

**Trace:**
1. Next boot: `[[ -f "${marker}" ]]` → FALSE → fast-path fails immediately → install re-runs. **CORRECT.**

### Input 4 (rc=3010, all 3 DLLs present — normal Windows runtime installer success)
Installer exits 3010 (reboot suppressed), all DLLs land correctly.

**Trace:**
1. rc captured (non-zero), logged.
2. `missing[]` = empty.
3. `exit 1` guard not triggered.
4. `touch marker` at line 182. **CORRECT.**

### Input 5 (STEAM_COMPAT_DATA_PATH not mounted / empty directory)
Volume not mounted, directory absent.

**Trace:**
1. Fast-path `-f` checks on nonexistent paths → all FALSE → falls through. No false-skip.
2. `proton run` fails with a hard non-zero rc. rc captured.
3. `missing[]`: all 3 absent → `exit 1`. **CORRECT — no false-skip, no marker written.**

---

## Key invariant confirmed

`touch "${marker}"` at line 182 is ONLY reachable when:
- `missing[]` is empty (all 3 DLLs present AND verified), AND
- The `exit 1` guard at lines 175–180 did NOT fire.

This means: **marker-written ↔ all-3-DLLs-verified-at-write-time** is a strict invariant enforced by control flow. There is no path where the marker is written without DLL verification passing. The conjunctive fast-path (`marker AND DLLs`) is therefore strictly a performance optimization with no correctness consequence:

- If fast-path fires: marker present (implies DLLs were present at marker-write time) AND DLLs still present now → safe skip.
- If fast-path fails: install re-runs. The `missing[]` gate is the actual correctness gate.

The rc-tolerant install (new in round 2) does not create any path to `touch marker` that bypasses `missing[]`. The `|| rc=$?` construct correctly absorbs `set -e` for the `proton run` line. The subsequent `missing[]` array checks with `[[ ]] || missing+=()` are also `set -e`-safe for the same reason.

---

## Strategies attempted

### Mixed inputs (primary target per orchestrator directive)
Input 1: rc=3010 (benign, rc-tolerant path) + partial DLL landing (2 of 3). The fast-path never fires (no marker yet on first boot). The `missing[]` check catches the partial install and `exit 1` fires before `touch marker`. No false-skip possible. No corrupt marker created.

### Boundary inputs
Input 5: `STEAM_COMPAT_DATA_PATH` absent. All `-f` checks false → install attempted → rc likely hard-fail → missing[] catches all 3 → `exit 1`. Correct.

Input 3: SIGKILL mid-install → no marker written → next boot re-enters install. Correct.

### Existing-primitive check
Searched for a narrower "DLL-only check" primitive — the `missing[]` array check at lines 170–173 IS that primitive. The fast-path adds the marker conjunction on top. The marker write is gated downstream of `missing[]`, so the conjunction can never produce a stale-marker false-skip: a marker can only exist if DLLs were verified at write time.

### Trace-through (sequential boot states)
Traced all reachable `(marker_present, dll_present)` state combinations:
- `(false, false)` → install runs. Correct.
- `(false, true)` → fast-path fails (no marker) → install runs (idempotent via rc-tolerance and missing[] gate). Correct.
- `(true, false)` → fast-path fails (DLL absent) → install runs. Correct.
- `(true, true)` → fast-path fires → skip. Correct (invariant: marker ↔ DLLs verified at write time; DLLs still present).

No state combination produces a false-skip.

### Round-trip / marker corruption
There is no read-back of the marker's content — it is a bare existence marker (`touch`). No serialization risk. Its only role is as a fast-path hint; the `missing[]` gate is the authoritative path for any boot where the fast-path fails.

---

## Verdict: PASS

The round-2 rc-tolerant install block does NOT introduce any path to `touch marker` that bypasses `missing[]`. The conjunctive fast-path and the new install path compose correctly across all reachable boot sequences. No false-skip scenario exists.

---

## Bottom Line

Tried rc=3010 + partial DLL landing, mid-install SIGKILL, volume-not-mounted, and post-install single-DLL deletion. Every path either re-triggers install or exits 1 before touching the marker. The `missing[]` gate is structurally upstream of `touch marker` with no bypass route. PASS.
