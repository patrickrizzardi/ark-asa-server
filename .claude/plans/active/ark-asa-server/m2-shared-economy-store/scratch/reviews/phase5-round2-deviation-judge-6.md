# Deviation Judge: m2-shared-economy-store Phase 5 Deviation #6 — Round 2

## Verdict: PASS

## Deviation summary
`_inject_mysql_block()` helper and `inject_plugin_db_config()` together inject ArkShop/Permissions DB credentials into plugin config.json files via jq; round-1 BLOCK was a non-numeric `ARKSHOP_DB_PORT` slipping the fail-fast guard, reaching `jq tonumber`, jq failing silently under `set -e`'s non-final-`&&`-element exemption, and producing a false-success log against an unwritten config.

---

## Adversarial inputs constructed

1. `ARKSHOP_DB_PORT=""` (empty string, ENABLE_ASAAPI=1) — empty string passed to regex `^[0-9]+$`.
2. `ARKSHOP_DB_PORT="03306"` (leading zero) — numeric but non-canonical; reaches jq `tonumber`.
3. `ARKSHOP_DB_PORT=" 3306"` (leading space) — looks numeric, fails digit-first regex.
4. `ARKSHOP_DB_PORT="65536"` (above valid TCP range) — all digits, passes regex, reaches tonumber.
5. Malformed Permissions `config.json` (invalid JSON) — probes the second `_inject_mysql_block` call site via the `jq -e has("Mysql")` guard path.
6. `mktemp` returning empty / failing — tests whether `set -e` covers the mktemp assignment.

---

## Trace

### Input 1: `ARKSHOP_DB_PORT=""`

- Line 24: `ARKSHOP_DB_PORT="${ARKSHOP_DB_PORT:-3306}"` — if caller exports `ARKSHOP_DB_PORT=""`, bash `:-` expansion does NOT substitute (the var is set, just empty); result: `ARKSHOP_DB_PORT=""`.
- Line 345: `-z` check covers HOST, USER, PASS, NAME only — PORT is NOT in this list.
- Line 354: `if ! [[ "${ARKSHOP_DB_PORT}" =~ ^[0-9]+$ ]]` — empty string does not match `^[0-9]+$` (requires ≥1 digit); condition is true → `exit 1` fires at line 356.
- `_inject_mysql_block` is never reached. False-success log never emitted.
- **Result: PASS — correctly aborts.**

### Input 2: `ARKSHOP_DB_PORT="03306"` (leading zero)

- Line 354: `"03306"` matches `^[0-9]+$` — passes guard.
- `_inject_mysql_block` called; line 320: `($port | tonumber)` — jq `tonumber` on the string `"03306"` yields integer `3306` (jq ignores leading zeros in numeric conversion). Written JSON contains `3306`.
- ArkShop sees a valid integer port value. No false-success, no bad JSON. Semantically valid.
- **Result: PASS — correct behavior.**

### Input 3: `ARKSHOP_DB_PORT=" 3306"` (leading space)

- Line 354: `" 3306"` — first character is a space, not `[0-9]`; regex `^[0-9]+$` does not match → `exit 1` fires.
- **Result: PASS — correctly aborts.**

### Input 4: `ARKSHOP_DB_PORT="65536"` (out-of-range but all-digits)

- Line 354: `"65536"` matches `^[0-9]+$` → passes guard.
- Line 320: `($port | tonumber)` = `65536`; valid jq operation. JSON written with `MysqlPort: 65536`.
- ArkShop will fail to connect (port 65536 is above valid TCP range), but this is a SEMANTIC error, not a false-success script error. The config IS written correctly; the connection will fail at ArkShop startup, not silently at config-injection time. Port range validation is out of scope for a jq-injection false-success fix — the fix's stated problem was a script false-success log after jq failure, not TCP port semantics.
- **Result: PASS for the stated problem. Note: port range validation could be a future improvement but is not a gap in the false-success fix.**

### Input 5: Malformed Permissions config.json (invalid JSON, ENABLE_ASAAPI=1)

- Line 373: `if [[ -f "${perms_cfg}" ]] && jq -e 'has("Mysql")' "${perms_cfg}" >/dev/null 2>&1`
- jq exits with code 5 on malformed JSON input; `2>&1` suppresses error output.
- The `&&` chain: `[[ -f ... ]]` is true (file exists), then `jq -e ...` exits 5 (nonzero) → the compound `&&` expression is false overall.
- `if` condition is false → the `then` block (line 374, `_inject_mysql_block "${perms_cfg}"`) is NOT executed.
- The "Permissions DB config injected" log is NOT emitted. No false-success for the Permissions path.
- ArkShop injection at line 366 already succeeded with a valid log. The Permissions skip is silent but not a false-success — it's a quiet skip on a conditional path, which is acceptable: ArkShop can function without Permissions DB config if the Permissions plugin doesn't have a Mysql block (or has corrupt JSON).
- **Result: PASS — Permissions failure-to-inject is safe, not a false-success.**

### Input 6: `mktemp` failure

- Line 309: `tmp="$(mktemp)"` — mktemp fails (e.g., /tmp is full or unmounted).
- `set -euo pipefail` is active. A command substitution that fails in an assignment IS covered by `set -e` (unlike the `&&`-chain non-final-element exemption — assignments are ordinary command positions). Script aborts before reaching `jq`.
- **Result: PASS — mktemp failure aborts the script safely.**

---

## Where the fix overshoots (BLOCK only)

N/A — PASS verdict.

---

## Strategies attempted

### Mixed inputs
Tried empty string + regex guard (`""`); leading-zero + tonumber (`"03306"`); leading-space + regex (`" 3306"`). None produced a false-success path. The regex `^[0-9]+$` correctly catches all non-pure-digit values including empty, leading-space, and mixed-character strings. The tonumber behavior on leading-zero strings is correct (jq normalizes to integer).

### Boundary inputs
Tried empty string (caught by regex), `"0"` (valid, passes, jq handles it), very large number `"65536"` (passes regex, valid jq, semantic TCP error is out of fix scope), `"65535"` (passes, correct boundary). No boundary yields a false-success or uncaught jq failure.

### Existing-primitive check
Searched for an alternate numeric guard in the script (`grep -n "ARKSHOP_DB_PORT" entrypoint.sh`). The only guard is the new regex at line 354. No competing or conflicting guard exists. The belt-and-suspenders `||` exit in `_inject_mysql_block` (line 321) covers any jq error not related to port (e.g., malformed input JSON). The two-layer guard is correct and non-redundant.

### Second-caller check
`_inject_mysql_block` has exactly two call sites: line 366 (ArkShop) and line 374 (Permissions). Both are inside `inject_plugin_db_config()`, which runs the port regex guard once (line 354) before either call. The guard is not per-call but per-invocation of the parent function — which is correct since `ARKSHOP_DB_PORT` is a module-level env var, not a per-call argument. The second caller (Permissions) does not introduce a new code path that bypasses the guard.

### Trace-through
Traced all six adversarial inputs end-to-end. The only case that merits a note is port `"65536"` (out of TCP range): the script DOES inject successfully (correct behavior for the fix's stated problem), and ArkShop fails to connect at runtime. This is not a false-success log — the config IS written, just with a semantically invalid port. Out of scope for the jq-false-success fix.

### Round-trip / serialization
The `mktemp + mv` pattern is atomic from the perspective of the file: either the full jq output lands in `config.json` (via mv) or the temp file is removed and the original is untouched (via the `|| { rm -f; exit 1; }` handler). The `mv` at line 322 is a separate statement unreachable after jq failure (exit 1 already fired). The round 1 BLOCK (false-success after jq failure) is fully closed.

---

## Bottom Line

Both parts of the fix land correctly: the port regex catches every non-digit value before jq, and the `|| exit 1` handler is structurally final so it fires unconditionally on any remaining jq failure. Six adversarial inputs across five strategies, zero breaks. PASS.
