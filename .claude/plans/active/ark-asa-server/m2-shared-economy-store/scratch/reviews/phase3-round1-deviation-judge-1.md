---
phase: 3
round: 1
deviation: 1
verdict: PASS
---

# Deviation Judge — Full Report
## m2-shared-economy-store Phase 3 Deviation #1

---

## Deviation Summary

`install_vcredist()` gates the warm-boot skip on `marker AND dll1 AND dll2 AND dll3` (conjunctive
fast-path), where the plan's Step 2 specified gating the skip on "actual DLL presence (not a bare
marker)." Executor added the marker as a conjunction rather than as a pure DLL-presence check.

---

## Adversarial Inputs Constructed

### Input 1 (primary — mixed strategy)
**Marker-absent, all 3 DLLs present**: marker file `${STEAM_COMPAT_DATA_PATH}/.vcredist-installed`
is deleted (e.g., operator deleted it, it was on a separately wiped bind-mount, or the
`STEAM_COMPAT_DATA_PATH` dir was recreated without touching `pfx/`), while the Proton prefix itself
is intact and all three DLLs survive.

### Input 2 (boundary strategy)
**Exactly 1-of-3 DLLs present, marker absent**: `msvcp140.dll` exists in the prefix system32 but
`vcruntime140.dll` and `vcruntime140_1.dll` do not (partial VC++ install from a prior crash).

### Input 3 (boundary strategy)
**Exactly 1-of-3 DLLs present, marker present**: same partial state but marker was written (e.g.,
from a different VC++ installer pass that verified differently).

### Input 4 (boundary strategy — the executor's case, confirmed, not re-tested)
**Prefix reset (pfx/ nuked), marker survives on volume root**: marker present, DLLs gone.

---

## Trace

### Input 1 — marker-absent, all 3 DLLs present

**Precondition**: `${STEAM_COMPAT_DATA_PATH}/.vcredist-installed` does not exist (no marker).
`${pfx_sys32}/msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` all exist.

**entrypoint.sh:152**: evaluates `[[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]`
- `[[ -f "${marker}" ]]` → **FALSE** (marker absent)
- Short-circuit: entire conjunction → **FALSE**

**entrypoint.sh:157**: falls through to `echo "[entrypoint] Installing VC++ 2019 redist…"` → **install fires unnecessarily**

**entrypoint.sh:158**: `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` runs.

**entrypoint.sh:163-165**: verify block — all 3 DLLs already present → `missing[]` stays empty.

**entrypoint.sh:174**: `touch "${marker}"` — marker recreated.

**End state**: same DLLs, marker now exists, function returns 0. Functionally correct.

**Is this a correctness failure?**

No. The DLLs were already correct. The VC++ installer is idempotent at the same version — it writes
the same DLLs it would have written, or Wine's installer simply no-ops on already-installed bits.
The end state is identical: DLLs present, marker present. No corruption occurs.

**Is this a behavioral regression vs the plan's stated contract?**

The plan's stated contract is: "gate the skip on actual DLL presence (not a bare marker)" so that a
pfx/ reset does NOT falsely skip. The plan's failure mode is FALSE SKIP when DLLs are absent. This
input produces a FALSE RUN when DLLs are present — the OPPOSITE direction. It's a performance
annoyance (~30-60s redundant Wine installer run on one uncommon boot), not a safety failure. The
plan's safety invariant — "DLL absence always triggers the install" — holds under all inputs.

**Is the false-run a real-world risk?**

The marker lives at `${STEAM_COMPAT_DATA_PATH}/` (volume root) and the DLLs live under
`${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/`. A scenario where the DLLs survive
but the marker does not requires either: (a) the marker file specifically deleted while pfx/ intact,
or (b) a volume-subtree move that left pfx/ on one volume and dropped the marker-parent dir. Both
are possible but uncommon. The consequence (one redundant installer run, ~60s delay, then correct
state) is tolerable; it is not silent data loss or a broken server.

### Input 2 — 1-of-3 DLLs present, marker absent

**entrypoint.sh:152**: `marker=F` → short-circuit → FALSE → install fires → correct (partial install is healed).
Post-install verify: all 3 present → marker written. Correct behavior.

### Input 3 — 1-of-3 DLLs present, marker present

**entrypoint.sh:152**: `marker=T && msvcp=T && vcrt=F` → FALSE (vcrt missing) → install fires → correct.
Post-install verify: all 3 present → marker touched. Correct behavior.

Both inputs 2 and 3 show the conjunctive form correctly triggers the install on any partial-DLL state,
whether or not the marker is present. These are the structurally important cases for the plan's
safety invariant, and they pass.

---

## Where the Fix Overshoots (BLOCK only)

N/A — verdict is PASS.

---

## Strategies Attempted

### Mixed inputs (primary strategy)
Constructed Input 1: marker-absent but all 3 DLLs present. This probes whether the conjunction's
marker arm eats the case the executor didn't name. Result: false-run (install fires when it could
skip), but end state is correct, no data corruption, no silent failure. The plan's safety invariant
(DLL absence always triggers install) is unaffected. Did not yield a BLOCK.

### Boundary inputs
Inputs 2 and 3: partial DLL presence (1-of-3) with marker in both states. Both correctly fall
through to the install. Input 2 exercises the "marker gone, partial DLLs" corner; Input 3 exercises
"marker present, partial DLLs." Both correct.

Also considered: all 3 DLLs present AND marker present (warm boot) — the executor's happy path.
Correctly skips. Considered: all DLLs absent AND marker absent (first boot) — correctly installs.
These are the nominal cases; no break.

### Existing-primitive check
Searched for any alternative gate primitive in the codebase that does DLL-only presence checking
(e.g., a function that checks DLLs without touching the marker). None found — the implementation
is new in this diff. The plan's Step 2 does say "A `.vcredist-installed` marker MAY be a fast-path
hint" which explicitly allows the conjunction shape. The plan's Step 3 says "the DLL presence check
is the source of truth" — this is satisfied because ANY missing DLL (regardless of marker state)
causes the fast-path to fail and the install to run.

### Second-caller check
There is only one call site for `install_vcredist()`: `main()` at entrypoint.sh:203 (the `+54`
block). No second caller exists or is planned within Phase 3's scope. The function is a pure boot
step. Not applicable as a break vector.

### Trace-through (for the false-run case)
Traced Input 1 fully above. The false-run produces: one extra `proton run` invocation (~30-60s
under Wine), same DLL set written (idempotent), marker recreated, correct final state. Boot
succeeds, AsaApi loads, no user-visible failure. The operational cost is a single slow boot in the
rare scenario where the marker is lost but the prefix survives. Acceptable.

### Round-trip / serialization
Not applicable — no serialization or round-trip surface in this function. The DLL files are binary
blobs written by the Wine VC++ installer; the marker is a zero-byte sentinel via `touch`. Neither
has a serialization pathway to audit.

---

## The Conjunctive Form vs Pure DLL-Only Form: Net Assessment

The plan's literal wording was "gate the skip on actual DLL presence (not a bare marker)." A pure
DLL-only form would be:

```bash
if [[ -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]; then
```

The executor implemented:

```bash
if [[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]; then
```

The ONLY behavioral difference between these two forms: the executor's form does a redundant install
in the marker-absent/DLLs-present case. The plan explicitly says the marker MAY be used as a
fast-path hint (Step 2: "A `.vcredist-installed` marker MAY be written as a fast-path hint, but the
DLL presence check is the source of truth"). The executor's conjunction treats the marker as
required for the fast-path rather than purely optional — this is slightly conservative relative to
the plan's "MAY" wording but not a violation of the safety invariant.

The executor's claim in the rationale — "DLL absence always triggers the install" — holds. Every
DLL-absent scenario (prefix reset, partial install, first boot) falls through to the install. The
only wrong-direction case (false-run) is minor, self-correcting (marker gets written), and matches
the plan's explicitly permitted use of the marker as a "hint" (if the hint is absent, fall through
to install).

---

## Bottom Line

The conjunction is slightly more conservative than pure DLL-only (one extra `proton run` if the
marker vanishes while the prefix survives), but it holds the plan's safety invariant on every path
that matters. The plan's own Step 2 explicitly permitted the marker-as-hint shape; the executor
used it. PASS.
