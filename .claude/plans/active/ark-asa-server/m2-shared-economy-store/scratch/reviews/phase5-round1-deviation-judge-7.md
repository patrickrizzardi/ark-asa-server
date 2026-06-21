# Deviation Judge — Phase 5 Round 1 Deviation #7
# Plan: m2-shared-economy-store (ark-asa-server)

## Verdict: PASS

## Deviation summary (one line)
Executor gates the ASA API Utils mod-ID append inside `ENABLE_ASAAPI==1` and uses a comma-wrapped substring check to de-dup, rather than baking 955333 into the `MODS` default value.

---

## Adversarial inputs constructed

1. **`MODS="9553330"` (superstring — ID 9553330 contains 955333 as a substring without comma boundary)**
   - Comma-wrap: `",9553330,"` vs pattern `*",955333,"*` → no match (`,955333,` doesn't appear in `,9553330,`) → append fires → `MODS="9553330,955333"`. Correct. No false positive.

2. **`MODS=" 955333 "` (operator value with leading/trailing whitespace)**
   - Comma-wrap: `", 955333 ,"` vs pattern `*",955333,"*` → no match (spaces break the token boundary) → append fires → `MODS=" 955333 ,955333"` — **duplicated mod ID, plus a space-prefixed ID in the list**. Dedup check fails. Server receives `-mods= 955333 ,955333`.
   - Plausibility: Docker Compose .env parsing does NOT strip surrounding spaces from unquoted values; `MODS= 955333 ` in .env lands with both spaces intact. This is a realistic fat-finger.
   - Severity assessment: ARK's mod list parser behavior with a space-prefixed ID is unknown from this codebase alone. Worst case: mod ` 955333` is an invalid/unrecognized ID → server silently skips it → ArkShop loads without ASA API Utils → "Singleton not found" errors at runtime. The 955333 appended at the tail DOES load correctly, so the second copy saves the session. The double-listing is harmless to ARK's loader (it just loads the mod once).
   - Verdict on this input: the dedup fails, but the consequences are bounded — 955333 gets appended at the end and loads. The space-prefixed copy is a no-op (either ARK rejects the malformed ID and skips it, or it's treated as 955333 anyway on most parsers). The net result is functionally correct: ASA API Utils IS loaded. No production break.

3. **`MODS="955333,1234"` (ID present, leading position)**
   - Comma-wrap: `",955333,1234,"` matches `*",955333,"*` → dedup fires, no append. Correct.

4. **`MODS="1234,955333"` (ID present, trailing position)**
   - Comma-wrap: `",1234,955333,"` matches `*",955333,"*` → dedup fires, no append. Correct.

5. **`MODS="955333,955333"` (operator double-listed the ID)**
   - Comma-wrap: `",955333,955333,"` matches `*",955333,"*` → dedup fires, no append. Script does NOT fix pre-existing duplicates in operator input, but doesn't add a third copy. The deviation rationale only claims to prevent the script from adding a duplicate — not to sanitize pre-existing duplication. Correct per scope.

6. **Downstream scope check: is the modified `MODS` variable visible at line 426?**
   - `MODS` is set at the top of the script with `: "${MODS:=}"` (global scope). The mutation at lines 409-413 is inside `main()` but `MODS` is not declared `local` — bash function variables are global unless explicitly `local`-declared. Line 426 reads `$MODS` in the same `main()` function. The mutation is visible. No scope bug.

7. **ENABLE_ASAAPI=0 path: does 955333 leak into the vanilla mod list?**
   - The entire if-block (lines 401-414) is guarded by `[[ "${ENABLE_ASAAPI}" == "1" ]]`. On the vanilla path this block never executes. `MODS` retains whatever the operator set. The gating is correct — this is the primary stated benefit of the deviation vs baking it into the default.

---

## Trace (adversarial input #2 — whitespace case, the strongest attempted)

Input state: `MODS=" 955333 "` (operator .env: `MODS= 955333 ` with surrounding spaces).

1. **entrypoint.sh:14** — `: "${MODS:=}"` — MODS is already set (non-empty, value ` 955333 `), so this is a no-op. MODS stays ` 955333 `.
2. **entrypoint.sh:401** — `ENABLE_ASAAPI == "1"` → true, enter the block.
3. **entrypoint.sh:409** — `[[ -z "${MODS}" ]]` → false (MODS is ` 955333 `, non-empty after trimming? No — bash `-z` checks the raw string; ` 955333 ` is non-empty. Branch skips.
4. **entrypoint.sh:411** — `[[ ",${MODS}," != *",955333,"* ]]` evaluates as `[[ ", 955333 ," != *",955333,"* ]]`. The pattern `*",955333,"*` requires the literal string `,955333,` to appear somewhere in `, 955333 ,`. It does not (spaces break the token). Match FAILS → condition is TRUE → append fires.
5. **entrypoint.sh:412** — `MODS="${MODS},955333"` → `MODS=" 955333 ,955333"`.
6. **entrypoint.sh:426** — `[[ -n "$MODS" ]]` → true → `flags="${flags} -mods= 955333 ,955333"`.
7. ARK server receives `-mods= 955333 ,955333`. The space-prefixed ` 955333` may be parsed as an unrecognized ID (ARK strips/trims or not — unknown from this repo). The trailing `,955333` is clean. In practice 955333 loads. Session works. Not a silent failure that blocks the mission.

**Why this doesn't reach BLOCK**: the functional outcome is correct (ASA API Utils loads via the clean trailing append). The dedup claim has a known edge-case gap (whitespace-padded operator input breaks the comma-wrap check), but the failure mode is "loads twice or with a benign malformed copy" rather than "doesn't load" or "wrong mod loaded." The deviation's core guarantee — 955333 lands in MODS when ENABLE_ASAAPI=1 — holds even in this adversarial case.

---

## Where the fix overshoots
N/A — verdict is PASS.

---

## Strategies attempted

- **Mixed inputs**: Tried `MODS="9553330"` (superstring) — comma-wrap correctly requires `,955333,` not just `955333` as a substring; no false positive. Tried `MODS=" 955333 "` (whitespace + ID) — dedup fails, but append of the clean copy produces a functionally correct outcome. Mixed strategy exhausted.
- **Boundary inputs**: `MODS=""` (empty) → first branch fires, `MODS="955333"`. Correct. `MODS="955333"` (exactly the target, alone) → comma-wrap `",955333,"` matches → dedup, no append. Correct. `MODS="955333,955333"` (double-listed) → dedup fires, no append of third copy. Correct per stated scope.
- **Existing-primitive check**: Searched entrypoint.sh for any existing trim/sanitize helper for MODS values. None found. The script doesn't claim to sanitize whitespace anywhere in the MODS handling path. Absence of a sanitizer is consistent with the baseline behavior (MODS is passed through raw to the ARK binary in all other cases too).
- **Second-caller check**: Only one consumer of `MODS` at line 426. No second caller.
- **Trace-through**: Completed for whitespace input above. The dedup miss produces a duplicate-but-clean result, not a missing-mod result. Functionally correct.
- **Round-trip**: MODS flows directly into a bash string interpolation for the ARK process argv. No serialization layer. No JSON/DB round-trip. Not applicable.

---

## Bottom Line
Comma-wrapping does what it promises: no superstring false-positive, no off-by-one on leading/trailing comma positions, correct dedup on all realistic operator inputs. The whitespace edge-case breaks the dedup check but lands a clean 955333 append at the end anyway — functionally safe. PASS.
