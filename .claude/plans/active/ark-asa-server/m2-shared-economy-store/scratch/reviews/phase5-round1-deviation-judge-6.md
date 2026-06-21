# Deviation Judge Full Report: m2-shared-economy-store Phase 5 Deviation #6

**Plan**: `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md`
**Phase**: 5
**Deviation type**: approach
**Deviation #**: 6 (labelled Deviation #2 in executor's report for Step 2)

---

## Verdict: BLOCK

---

## Deviation Summary

The executor replaced the plan's placeholder-substitution option with a `jq --arg` injection pattern that writes DB credentials into `ArkShop/config.json` (and `Permissions/config.json`) using a `mktemp` temp file and a `jq ... > tmp && mv tmp cfg` atomic-swap idiom.

---

## Adversarial Input Constructed

**Input**: `ARKSHOP_DB_PORT="not-a-number"` (explicit override with any non-numeric string, or an empty string via explicit `ARKSHOP_DB_PORT=""`).

This passes the fail-fast guard at `entrypoint.sh:313` — which checks only `ARKSHOP_DB_HOST`, `ARKSHOP_DB_USER`, `ARKSHOP_DB_PASS`, and `ARKSHOP_DB_NAME`. `ARKSHOP_DB_PORT` is absent from that guard. The default fallback at `entrypoint.sh:23` provides `3306`, but any explicit env override bypasses that default entirely.

---

## Trace

**Step 1**: Fail-fast check at `entrypoint.sh:313`:
```bash
if [[ -z "${ARKSHOP_DB_HOST}" || -z "${ARKSHOP_DB_USER}" || -z "${ARKSHOP_DB_PASS}" || -z "${ARKSHOP_DB_NAME}" ]]; then
```
`ARKSHOP_DB_PORT` is NOT in this condition. With `ARKSHOP_DB_PORT="not-a-number"`, the fail-fast passes.

**Step 2**: Execution reaches `entrypoint.sh:331-344`:
```bash
local tmp
tmp="$(mktemp)"
jq --arg host   "${ARKSHOP_DB_HOST}" \
   ...
   --arg port   "${ARKSHOP_DB_PORT}" \
   '.Mysql.MysqlPort = ($port | tonumber)' \
   "${arkshop_cfg}" > "${tmp}" \
&& mv "${tmp}" "${arkshop_cfg}"
```

**Step 3**: jq evaluates `("not-a-number" | tonumber)`. jq exits with code 5 and emits:
```
jq: error (at <stdin>:1): Invalid numeric literal at EOF at line 1, column 3 (while parsing 'not-a-number')
```

The redirect `> "${tmp}"` already opened `${tmp}` for writing before jq ran. `${tmp}` contains empty output (jq produced nothing before erroring). `${arkshop_cfg}` is untouched — the atomic swap didn't happen, which is the CORRECT atomicity behavior.

**Step 4 — the bug**: Under `set -euo pipefail`, the `&&` chain `jq ... > tmp && mv tmp cfg` is a compound list where jq is the LEFT side. Per bash semantics, `set -e` does NOT fire when the failing command is the non-final element of a `&&`/`||` list. Quoting the bash manual: "The shell does not exit if the command that fails is... part of any command executed in a && or || list except the command following the final && or ||." jq's failure is exactly this case — it is not the final command in the `&&` list (mv is). The compound command exits non-zero (jq's exit 5), but `set -e` is exempt from firing.

**Empirically confirmed** (bash invocation with `set -euo pipefail`):
```
jq: error (at /tmp/tmp.xxx:1): Invalid numeric literal at EOF...
[entrypoint] ArkShop DB config injected (host=mariadb, db=arkshop, user=arkshop).
{"Mysql":{"MysqlPort":3306,"MysqlPass":"original"}}   ← stale config, never updated
```

The entrypoint continues past the failed injection, prints the false-success log line, and boots the ARK server against the stale `config.json`. ArkShop uses the old (stale/default-seeded) port — which may be `3306` from the seed, not the operator-specified value. The server boots silently misconfigured with no terminal error.

**Same defect in the Permissions block** at `entrypoint.sh:354-367`: identical `tmp2 + && + mv` pattern, same `set -e` exemption applies.

---

## Where the Fix Overshoots

- **Stated problem**: sed-based substitution is fragile for special characters in passwords; jq `--arg` is safe because values are typed strings never interpreted as jq expressions.
- **Wider effect (the bug)**: The `jq ... > tmp && mv tmp cfg` idiom ALSO relies on `set -e` to abort on jq failure. But bash's `set -e` exempts the left side of a `&&` list from triggering exit — so a jq failure (e.g., `tonumber` on a non-numeric port) is swallowed. The entrypoint continues, prints a false-success log, and boots with a stale config.
- **Narrower fix**: Append `|| { echo "[entrypoint] FATAL: failed to write ArkShop config.json" >&2; rm -f "${tmp}"; exit 1; }` after the `&&` chain. In a `cmd1 && cmd2 || cmd3` list, `cmd3` IS the final command, and `set -e` exempts it from triggering; but the explicit `exit 1` inside the `||` block fires correctly regardless of `set -e`. Same fix applies to the Permissions `tmp2` block. The `rm -f "${tmp}"` inside the error handler cleans up the empty temp file that mktemp created.

Empirically confirmed: `jq ... > tmp && mv tmp cfg || { echo FATAL; rm -f "$tmp"; exit 1; }` exits with code 1 and does not continue.

No existing primitive found that handles this pattern more narrowly — the fix is two lines per injection site (ArkShop block and Permissions block), both at `entrypoint.sh:343-344` and `entrypoint.sh:366-367`.

---

## Strategies Attempted

### Mixed inputs
Tried `ARKSHOP_DB_PORT=3306` (numeric, normal) + `ARKSHOP_DB_PORT="not-a-number"` (non-numeric). Normal path works correctly. Non-numeric path breaks as described — the two cases use the same code path and the `&&` exemption is always present; it just only manifests as a bug when jq exits non-zero.

### Boundary inputs
- Empty port `""`: default fallback at line 23 produces `3306` when BOTH `ARKSHOP_DB_PORT` and `MARIADB_PORT` are unset; but an explicit `ARKSHOP_DB_PORT=""` passes through the `:-` expansion and results in `""`, which `tonumber` also rejects (exit 5). Same silent-continue behavior.
- Single-char non-numeric: `"a"` → same.
- Numeric string: `"3306"` → `tonumber` succeeds → clean path.

### Existing primitive check
No existing bash function in `entrypoint.sh` wraps the jq+mv idiom with an explicit error trap. The narrower fix is inlined at the call sites (`entrypoint.sh:344` and `entrypoint.sh:367`).

### Second-caller check
The Permissions block at `entrypoint.sh:354-367` is the second caller of the same inject pattern. It has the identical `&&` exemption vulnerability. The `jq -e 'has("Mysql")'` probe in the Permissions `if` condition is in a shell `if` test, which is fully exempt from `set -e` as designed — that probe is not the bug. The bug is in the Permissions `jq ... > tmp2 && mv tmp2 perms_cfg` at lines 366-367.

### Trace-through
Fully traced above. The key invariant broken: bash `set -e` does NOT fire when the failing command is the non-final element of a `&&` list. This is documented bash behavior (`man bash`, `-e` flag description), not a portability edge case.

### Round-trip / serialization
All other credential values (`--arg pass`, `--arg host`, etc.) tested empirically: newline, backslash, double-quote, dollar-sign, and a jq-filter-looking string all pass through `--arg` safely and produce valid JSON. The `tonumber` concern is the ONLY jq-path that can fail after the fail-fast guard. The rationale's claim about `--arg` safety is correct for the password; the gap is in the integer coercion for port.

---

## Bottom Line

The jq `--arg` choice is correct and every credential type is safe — except the `tonumber` coercion for port, where bash's `&&`-list `set -e` exemption silently swallows the failure and boots the server against a stale config. Add `|| { rm -f "${tmp}"; exit 1; }` after both `&&` chains; `||` makes the error handler the FINAL command in the list, and the explicit `exit 1` fires unconditionally.
