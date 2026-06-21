# Deviation Judge — Full Report
## Plan: m2-shared-economy-store | Phase 4 | Deviation #3 | Round 2

---

## Deviation Judge: m2-shared-economy-store Phase 4 Deviation #3 (Round 2)

### Verdict: BLOCK

### Deviation summary (one line)
Round-2 fix adds `ensure_modded_pdb()` — an independent pre-launch gate (gated on ENABLE_ASAAPI=1) that validates pdb presence, runs up to 3 steamcmd validate attempts if absent, then fatal-exits if still missing. The round-1 BLOCK (install-time-only guard missing the vanilla→modded flip) is genuinely resolved. A new gap introduced by the retry loop's success-gate.

---

### Round-1 BLOCK verification

The round-1 BLOCK was: the pdb-shed conditional at install time (entrypoint.sh:50-52) evaluated `ENABLE_ASAAPI` at first-install only; a vanilla first-install permanently deleted the pdb, and no automated path in entrypoint.sh restored it on a later ENABLE_ASAAPI=1 boot.

Round-2 fix status: **RESOLVED.** `ensure_modded_pdb()` runs at entrypoint.sh:271-273, after `install_or_update()` returns, conditioned only on `ENABLE_ASAAPI == "1"` — independent of the `.installed` marker. A vanilla-first-installed volume with no pdb now hits `[[ -f "${pdb}" ]]` → FALSE (line 214) → enters the validate loop. The exact flip path ("deleted pdb → boot modded → pdb restored on attempt 1") is mechanically covered. Round-1 adversarial input #1 is dead.

Round-1 adversarial input #2 (UPDATE_ON_BOOT=1 + no pdb): also resolved — `ensure_modded_pdb()` runs AFTER `install_or_update()` returns (line 268-273 call order), so the `+app_update`-without-validate path still hits the pdb gate. The gate's retry loop runs validate independently.

---

### Adversarial input(s) constructed

1. **Partial pdb (0-byte or truncated) from a prior disk-full steamcmd validate attempt**: Volume has `.installed` marker. The `pdb` path exists on disk as a 0-byte file (Steam wrote the inode before disk space exhausted mid-download, leaving a partial file). `ensure_modded_pdb()` fires: `[[ -f "${pdb}" ]]` at line 214 → TRUE (inode exists, size not checked) → immediate `return 0`. Server launches via AsaApiLoader. AsaApi tries to SHA-256 the pdb → reads 0 bytes or corrupt bytes → "Failed to read pdb" → zero plugins load silently.

2. **UPDATE_ON_BOOT=1 on a modded volume where pdb was manually `touch`'d by an operator** (size-0 sentinel): Same existence-only gate fires at line 214, same silent AsaApi failure downstream.

---

### Trace

**Adversarial input #1 (partial pdb — 0-byte file from disk-full mid-validate):**

```
Pre-condition:
  - Volume has .installed marker (not first boot)
  - ArkAscendedServer.pdb exists at the path as a 0-byte file
    (prior steamcmd validate exhausted disk space after inode creation)

Boot with ENABLE_ASAAPI=1:
  entrypoint.sh:268  → install_or_update() runs
  entrypoint.sh:33   →   [[ ! -f "$INSTALL_MARKER" ]] → FALSE (marker present)
  entrypoint.sh:54   →   elif UPDATE_ON_BOOT==1? → false (not set) → fast-boot
  entrypoint.sh:268  → install_or_update() returns (no pdb restoration attempted)

  entrypoint.sh:271  → [[ "${ENABLE_ASAAPI}" == "1" ]] → TRUE
  entrypoint.sh:272  → ensure_modded_pdb() called
  entrypoint.sh:214  →   [[ -f "${pdb}" ]] → TRUE  ← 0-BYTE FILE PASSES THIS CHECK
  entrypoint.sh:215  →   return 0             ← EXITS IMMEDIATELY, no validate loop

  entrypoint.sh:274  → : > "$LOG_FILE"

  entrypoint.sh:291  → [[ "${ENABLE_ASAAPI}" == "1" ]] → TRUE
  entrypoint.sh:292  →   launch_exe="${LOADER_EXE}"
  entrypoint.sh:297  →   Xvfb :0 spawned
  entrypoint.sh:317  →   proton run AsaApiLoader.exe "${query}" ${flags}

  → AsaApiLoader.exe reads ArkAscendedServer.pdb
  → SHA-256 of 0-byte file: valid hash computation, but offset resolution returns 0/empty
  → AsaApi logs: "[critical] Failed to read pdb" (or variant)
  → ZERO plugins load
  → Server starts, RCON responds, game runs — SILENT FAILURE
```

This is the exact silent-failure mode the deviation rationale named: "the server still starts and reports success, making this a silent failure." The round-2 fix eliminates the silent failure on the vanilla→flip path but preserves it on the partial-pdb path.

**How does a 0-byte pdb land on the volume?**

Realistic production path: steamcmd validate begins downloading the ~6GB pdb (a large single depot file), disk fills mid-transfer, Steam writes the inode and starts streaming before discovering the space limit. Steam's behavior on ENOSPC: partial file remains at the destination path; the process exits non-zero OR exits 0 with a "disk full" message in its stdout (steamcmd's exit-code unreliability is already documented in the fix's own comment at entrypoint.sh:224-226). The prior validate call in the loop (or a prior boot's ensure_modded_pdb call) created the partial file. The NEXT boot hits `[[ -f "${pdb}" ]]` → TRUE → return 0.

The specific case where this bites: a modded volume where disk was NEARLY full (pdb previously installed successfully), a game patch shrinks a depot, steamcmd validate reruns and deletes the old pdb and starts re-downloading, disk happens to fill on the re-download. Partial file lands. All future boots silently fail to load plugins.

---

### Where the fix overshoots

- **Stated problem**: AsaApi requires ArkAscendedServer.pdb to derive its offset-cache key; the round-1 fix's install-time-only guard didn't cover the vanilla→modded flip, leaving a silent zero-plugin boot on mode change.

- **Wider effect**: `ensure_modded_pdb()` uses `[[ -f "${pdb}" ]]` (filesystem existence, entrypoint.sh:214) as BOTH its "already good → return early" gate AND its per-attempt "success → break" gate (entrypoint.sh:227). A 0-byte or truncated file satisfies both gates. The function returns success, AsaApi launches against a corrupt pdb, and the silent-failure mode the deviation rationale explicitly named is preserved on the partial-pdb path.

- **Narrower fix**: Add a minimum-size gate alongside the existence check. The valid ASA pdb is ~6GB; any threshold above ~1MB is a reliable discriminator:

  ```bash
  # Replace the existence-only guard at lines 214-216 and 227-229 with:
  _pdb_valid() {
    local f="${1}"
    [[ -f "${f}" ]] && [[ $(stat -c%s "${f}" 2>/dev/null || echo 0) -gt 1048576 ]]
  }
  ```

  Then `if _pdb_valid "${pdb}"; then return 0; fi` at line 214, and `if _pdb_valid "${pdb}"; then ... break; fi` at line 227. A 0-byte or partial file fails the size gate and the retry loop continues. After 3 failed validate attempts where the file still doesn't reach 1MB, the fatal-exit at line 234-239 fires — loud and actionable instead of silent.

  No new primitive needed beyond a 3-line helper. The existing `stat -c%s` is available in the Alpine/Debian base. This is strictly narrower: it closes the partial-pdb path without changing any behavior on the happy path (existing valid ~6GB pdb) or the completely-absent path (the vanilla→flip path the round-1 fix targeted).

---

### Strategies attempted

- **Mixed inputs**: Tested partial pdb (0-byte) mixed with the vanilla→flip scenario that R1 named. The existence-only gate passes the partial file and breaks the function's claimed guarantee. → BLOCK found here.
- **Boundary inputs**: Tested UPDATE_ON_BOOT=1 on a modded volume with a 0-byte pdb — same gate fires at line 214, same return 0. UPDATE_ON_BOOT=1 is not in scope of the BLOCK (it doesn't change the gate's behavior) but confirms the 0-byte path isn't special-cased.
- **Existing-primitive check**: Searched for a size-check primitive in entrypoint.sh. None exists. The vcredist install check at entrypoint.sh:160-162 uses DLL existence (`-f`) not size — same pattern, but for DLLs where size is not a useful discriminator. The pdb's ~6GB size is well-characterized and a size floor is straightforward.
- **Round-1 BLOCK re-verification**: Confirmed RESOLVED — the call-order at lines 268-273 guarantees ensure_modded_pdb() runs after install_or_update() regardless of which branch install_or_update took (.installed skip, delta update, or first install). R1's adversarial inputs #1 and #2 are both dead against the R2 code.

---

### Bottom Line

Round-1's BLOCK is genuinely dead — the vanilla→flip path now hits ensure_modded_pdb() and validates correctly. But the loop's existence-only gate (`[[ -f "${pdb}" ]]`) passes a 0-byte partial pdb and returns success, preserving the exact silent-failure mode the deviation rationale said we were eliminating. Add a minimum-size floor (1MB) to the gate; stat is available, the valid pdb is ~6GB, the fix is 3 lines.
