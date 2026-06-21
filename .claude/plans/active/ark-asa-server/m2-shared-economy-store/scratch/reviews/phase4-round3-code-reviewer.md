# Code Review: m2-shared-economy-store Phase 4 (round 3)

### Verdict: PASS

### Diff Scope
- Files changed: 5 (entrypoint.sh, docker-compose.yml, Dockerfile, .env.test.example, .env.prod.example)
- Lines added/removed: full phase diff vs `29735d2`; round-3 delta is entrypoint.sh only
- Phase commits reviewed: staged/uncommitted working tree (diff base `29735d2`)

### What's Solid
- **All three round-2 concerns are genuinely closed, not papered over.**
  1. **`~?GB` placeholder (round-2 Concern #1)** — gone. Lines 44–48 now read "Movies/ is the intro videos a headless server never plays" + "ArkAscendedServer.pdb (~6GB)". No unfilled placeholder survives in a durable comment.
  2. **Presence-only pdb check (round-2 Concern #2)** — closed by `pdb_ok()` (line 215): `[[ -f "${pdb}" ]] && [[ "$(stat -c%s ... || echo 0)" -gt 1048576 ]]`. A 0-byte/truncated pdb (steamcmd disk-exhaustion mid-download) now fails the guard, which was the exact silent-SHA-256-failure the whole function exists to prevent. Used at all three sites (early-return, post-validate break, final fatal-gate) — single source of truth, no drift.
  3. **Xvfb orphan on fail-fast exit (round-2 Concern #3)** — closed at line 323: `kill "${xvfb_pid}" 2>/dev/null || true` before `exit 1`.

- **The `1048576` threshold math is right.** 1 MiB = 1048576 bytes. A real ~6GB pdb is ~6442 MiB — orders of magnitude above the floor, so a valid artifact is never rejected; a truncated write is. The provenance is documented inline ("real pdb is ~6GB; require >1 MiB to reject truncated files while never rejecting a real one"). Not a magic constant — sourced and rationalized.

- **Stale-socket race fix (round-3 core delta) is sound.** Lines 318–320 add process-aliveness on top of the socket-presence check:
  ```
  xvfb_dead=0
  kill -0 "${xvfb_pid}" 2>/dev/null || xvfb_dead=1
  if [[ ! -S /tmp/.X11-unix/X0 || "${xvfb_dead}" -eq 1 ]]; then
  ```
  Fail-fast fires if socket absent OR process dead — correct De Morgan inverse of "require BOTH socket present AND process alive." The comment block (310–317) accurately names both failure modes (never-bound socket; bound-then-died stale socket → ECONNREFUSED).

- **`set -e` safety on the two flagged constructs — verified.**
  - `pdb_ok` used as an `if`-condition: a function in a tested context suppresses `set -e` inside its body, so the `[[ ]] && [[ ]]` returning non-zero (false) does not exit — it's the intended boolean. The inner `stat ... 2>/dev/null || echo 0` always yields a number, so the `-gt` comparison never errors on a missing file. Safe.
  - `kill -0 "${xvfb_pid}" 2>/dev/null || xvfb_dead=1`: failure caught by `||` → no `set -e` exit. Safe.
  - `set -u`: `xvfb_pid=""` initialized at line 295 before any branch, so the line-350 `[[ -n "$xvfb_pid" ]]` cleanup is `set -u`-safe.

- **All vars in `ensure_modded_pdb` resolve at call time.** `ASA_APPID` (line 9), `STEAMCMD_DIR` (defaulted line 268 in `main()` *before* the line-277 call), `ARK_DIR`, and a locally re-declared `force_windows` (line 212 — does not borrow `install_or_update`'s local). No `set -u` landmine.

- **Vanilla path stays byte-for-byte M1.** `ENABLE_ASAAPI=0` skips `ensure_modded_pdb` (line 276 guard), skips Xvfb (line 296 guard), sets `launch_exe=SERVER_EXE`. Round-3 changed nothing on this branch. dell happy-path re-verified (pdb present → `pdb_ok` early-returns, no validate, server up in 15s, both plugins loaded — no regression).

- **Install-time shed split is correct.** Line 49 unconditionally drops Movies/; line 50–52 only sheds the pdb when `ENABLE_ASAAPI != 1`. A fresh modded install keeps the pdb (no needless validate later); a fresh vanilla install sheds it; the vanilla→modded flip is recovered at the launch gate. Consistent with the documented flow.

### Required Fixes (BLOCK only — empty if PASS)
None — phase ready to commit.

### Concerns (non-blocking, but will bite later)
1. **entrypoint.sh:318–319** — `kill -0` returns success for a *zombie* Xvfb (a process that crashed post-bind but hasn't been reaped, since the parent only reaps at `wait`). In that narrow sub-second window the stale socket passes `-S` and `kill -0` passes too, so the guard proceeds into the ECONNREFUSED it meant to catch. This is not silent-wrong-output — `proton run` then fails loudly and `wait "$server_pid"` returns, so the failure surfaces downstream, just not at this guard. The window is tiny and the broader best-effort shape was already accepted in round 2. Noting only; not worth a fix.
2. **entrypoint.sh:318** — `xvfb_dead` is assigned without `local` (it's a global). No bug under `set -u` (assigned before read), pure style. Leave it.

### Laziness Pattern Audit
- Placeholder / mock pollution: PASS — the `~?GB` placeholder from round 2 is gone; no dummy values in any code path.
- Half-finished implementations: PASS — `pdb_ok` covers absent / truncated / valid; `ensure_modded_pdb` covers early-return, retry-exhaustion fatal-exit, restore-success; Xvfb branch covers never-bound, bound-then-died, and success. No happy-path-only logic.
- Type escape hatches (code-quality angle): PASS — N/A for bash; the deliberate unquoted `${force_windows}`/`${flags}` word-splits are documented and intentional, no expansion hides a bug.
- Smuggled TODOs (code-quality angle): PASS — no TODO/FIXME/Phase-N markers in code; the M1-rollback semantics are documented as a real kill switch, not a deferral.
- Magic constants without provenance: PASS — `1048576` is sourced inline (1 MiB floor vs ~6GB real pdb); `1 2 3` retry count, `seq 1 50`/`sleep 0.1` (~5s) cap, and `1024x768x24` geometry are each documented with rationale (geometry now explicitly noted as an arbitrary conventional minimum that Wine ignores for headless render).
- Documented deviations — adversarial inputs constructed (NOT the case executor named): PASS — executor's named case was "pdb present → early-return, no validate, no regression." Adversarial inputs attempted across strategies: (a) **boundary/integrity** — a truncated >0-byte but <1MiB pdb: now correctly REJECTED by `pdb_ok`'s size floor (round-2's presence-only gap is closed). (b) **stale-socket second-mode** — Xvfb binds then crashes to a non-zombie dead state: `kill -0` fails → `xvfb_dead=1` → fatal-exit + orphan-kill. Holds. (c) **zombie edge** — Xvfb crashes to an unreaped zombie: `kill -0` passes, guard proceeds → loud ECONNREFUSED downstream (Concern #1, not silent). (d) **second-config/rollback** — `ENABLE_ASAAPI=0`: both new gates skipped, vanilla launch unchanged. Holds. The size-floor and process-aliveness deltas survive the boundary and second-mode adversarial inputs; the only residual (zombie window) is loud, not silent. Deviation validated.

### Test Coverage Audit
N/A — infra plan (Dockerfile/entrypoint/compose). The verification artifact is the real `docker build` + boot on dell, the correct evidence form for a Proton-under-Docker stack the review environment can't run. Round-3 delta re-verified on dell: pdb present → `pdb_ok` early-returns (no validate), server up in 15s, AsaApi loaded both plugins — no regression vs round 2.

### Bottom Line
Chief, the executor cleaned up all three nits without breaking anything — the pdb size-floor and the socket-plus-liveness guard both hold under adversarial boundary inputs, and the two `set -e` constructs are genuinely safe. One theoretical zombie-Xvfb window remains but it fails loud, not silent, so it ships.
