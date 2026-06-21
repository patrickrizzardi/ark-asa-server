# Deviation Judge — Full Report
## Plan: m2-shared-economy-store | Phase 4 | Deviation #3

---

## Deviation Judge: m2-shared-economy-store Phase 4 Deviation #3

### Verdict: BLOCK

### Deviation summary (one line)
The executor wrapped the `ArkAscendedServer.pdb` deletion inside `if [[ "${ENABLE_ASAAPI}" != "1" ]]`, but this guard only fires during the FIRST-INSTALL block (gated on `.installed` marker absence) — making the pdb's presence or absence a permanent artifact of what `ENABLE_ASAAPI` was set to on the very first boot, regardless of future toggles.

---

### Adversarial input(s) constructed

1. **Boot 1 (vanilla)**: `ENABLE_ASAAPI=0` on first install. Marker absent → first-install fires → pdb deleted (guard says `!= "1"` is true → delete fires) → `.installed` written. Boot 2+ (modded): operator sets `ENABLE_ASAAPI=1` in compose env → first-install block SKIPPED (marker present) → pdb is absent → AsaApi loads → "Failed to read pdb" → zero plugins load.

2. **Boundary: UPDATE_ON_BOOT=1 path after vanilla first-install**: Operator sets `ENABLE_ASAAPI=1` AND `UPDATE_ON_BOOT=1` for a game-patch boot. The `elif UPDATE_ON_BOOT == "1"` branch runs `steamcmd +app_update` WITHOUT `validate` — a delta update that does NOT re-download the pdb (Steam only re-downloads changed depot files; the pdb is a fixed large file that doesn't change between minor patches). pdb absent → same failure.

3. **Validate path via manual out-of-band steamcmd**: The rationale itself admits "a future `steamcmd validate` was needed" to restore the pdb on the test box. This is NOT a code path inside `entrypoint.sh` — it requires the operator to exec into the container and run steamcmd manually. An in-scope fix cannot rely on an out-of-band operator action as its recovery mechanism.

---

### Trace

**Adversarial input #1 (vanilla first-install → later ENABLE_ASAAPI=1 toggle):**

```
Boot 1:
  ENABLE_ASAAPI=0 (env at first boot)
  entrypoint.sh:33  → [[ ! -f "$INSTALL_MARKER" ]] → TRUE (first boot, no marker)
  entrypoint.sh:35-36 → steamcmd install + validate fires
  entrypoint.sh:49  → rm -rf Movies/
  entrypoint.sh:50  → if [[ "${ENABLE_ASAAPI}" != "1" ]] → "0" != "1" → TRUE
  entrypoint.sh:51  → rm -rf ArkAscendedServer.pdb   ← pdb permanently deleted
  entrypoint.sh:53  → touch "$INSTALL_MARKER"          ← marker now present
  entrypoint.sh:238 → ENABLE_ASAAPI=0 → launch_exe=$SERVER_EXE → vanilla OK

Boot 2 (operator edits compose: ENABLE_ASAAPI=1):
  entrypoint.sh:33  → [[ ! -f "$INSTALL_MARKER" ]] → FALSE (marker present) → SKIP entire block
  entrypoint.sh:54  → elif UPDATE_ON_BOOT==1? → depends on config, but even if YES:
  entrypoint.sh:56-57 → steamcmd +app_update (NO validate) → pdb NOT re-fetched
  entrypoint.sh:218 → install_or_update() returns
  entrypoint.sh:219 → deploy_plugins()
  entrypoint.sh:220 → install_vcredist()
  entrypoint.sh:238 → ENABLE_ASAAPI=1 → launch_exe=$LOADER_EXE
  entrypoint.sh:244 → Xvfb spawned
  entrypoint.sh:256 → proton run AsaApiLoader.exe ...
    → AsaApiLoader reads ArkAscendedServer.pdb (to hash-derive offset cache key)
    → pdb ABSENT on volume
    → AsaApiLoader: "Failed to read pdb" → aborts or loads zero plugins
```

The fix's conditional at entrypoint.sh:50-52 evaluates `ENABLE_ASAAPI` at first-install time only. The marker at entrypoint.sh:53 permanently commits that evaluation. No subsequent boot re-evaluates the pdb-shed decision unless `steamcmd validate` explicitly re-downloads the ~6GB pdb (which does not happen via `app_update` and is not an automated path in entrypoint.sh).

**The fix is NARROWER than the stated problem.** The rationale says: "AsaApi SHA-256's the pdb to derive its offset-cache key... no pdb → no key → no cache → critical → no plugins." This is a boot-time failure condition, not an install-time condition. The pdb must be present on EVERY modded boot, not only when `ENABLE_ASAAPI=1` was set during first install. The fix guards only the install-time shed decision, but the failure mode is live on every subsequent modded boot after a vanilla first-install.

---

### Where the fix overshoots / is NARROWER (BLOCK)

- **Stated problem**: AsaApi fails to load plugins without the pdb (because the pdb is the SHA-256 source for the offset-cache key). The fix should prevent the pdb from being deleted when AsaApi is enabled.

- **Actual gap**: The fix is scoped to the first-install block (entrypoint.sh:33-53), but the pdb's necessity is a runtime property of `ENABLE_ASAAPI`, which can change after first install. A vanilla first-install (ENABLE_ASAAPI=0) permanently deletes the pdb. A later flip to `ENABLE_ASAAPI=1` finds no pdb, and no automated code path in entrypoint.sh restores it. The stated rationale's scope ("no pdb → AsaApi fails") is boot-wide, but the fix's scope is install-time only.

- **Narrower fix that would work**: One of two options, both narrower than the broken case and without changing the current logic for the happy path (ENABLE_ASAAPI=1 on first boot):

  **Option A — Validate-on-mode-switch (in-entrypoint recovery)**: Before deploying plugins / launching, when `ENABLE_ASAAPI=1` AND the pdb is absent (`[[ ! -f "${ARK_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.pdb" ]]`), run `steamcmd +app_update ${ASA_APPID} validate` to restore the file. Idempotent: if pdb is present (happy path), validation is skipped. Slow first recovery, but automatic and not operator-dependent.

  **Option B — FATAL guard (fail loudly instead of silently)**: Before launching with `ENABLE_ASAAPI=1`, check pdb presence and `exit 1` with an actionable error message if absent ("ENABLE_ASAAPI=1 requires ArkAscendedServer.pdb — run with UPDATE_ON_BOOT=1 and STEAMCMD_VALIDATE=1 to restore"). This does not auto-recover but makes the failure deterministic and loud instead of a silent "zero plugins loaded" symptom. A second env var (`STEAMCMD_VALIDATE=1`) triggering validate in install_or_update would be the companion.

  The existing pdb check at entrypoint.sh:40-43 (`[[ ! -f "$SERVER_EXE" ]]`) is the model: verify the artifact before trusting the install. A parallel pdb check conditioned on `ENABLE_ASAAPI=1` follows the same pattern and is already idiomatic in the file. No new primitive needed — just extend the artifact-presence verification logic.

---

### Strategies attempted

N/A (BLOCK — full trace found)

---

### Bottom Line

The fix guards the shed at install time, but the pdb isn't an install artifact — it's a runtime dependency the AsaApi loader demands on every modded boot. Vanilla first-install + later mode flip = silent zero-plugin boot with no error the operator can trace without reading the AsaApi internals. That's not a toggle, that's a trap.
