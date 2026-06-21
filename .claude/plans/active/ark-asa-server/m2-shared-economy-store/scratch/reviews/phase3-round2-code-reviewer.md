## Code Review: m2-shared-economy-store Phase 3 (Round 2)

### Verdict: PASS

### Diff Scope
- Files changed: 8 (entrypoint.sh, Dockerfile, ADR 0002 [new], design-sources.md, build-time-vs-runtime.md, plan.md, notes.md, state.md)
- Lines added/removed: +228 / -8
- Phase commits reviewed: `git diff 1f9f1b7` (committed Phase 1/2 base + uncommitted Phase 3 work)
- Round-1 delta focus: entrypoint.sh `install_vcredist` rc-capture + Big-O `Space:` annotation; ADR 0002 + entrypoint version-precision wording.

### What's Solid
- **rc-capture is the textbook-correct pattern.** `local rc=0` on its own line, then `proton run ... || rc=$?` on a separate line. This is exactly the shape that dodges the classic `set -e` abort AND the `local rc=$(cmd)` exit-code-masking footgun. Because the assignment (`local rc=0`) is decoupled from the command, `$?` reflects `proton run`'s real exit, not `local`'s. The `|| rc=$?` short-circuits `set -e` so a benign 3010/1638 does not abort the boot before the DLL verify runs.
- **DLL-presence is genuinely the sole gate.** Flow: log rc-if-nonzero → build `missing=()` → `exit 1` if any of the 3 DLLs absent → `touch "${marker}"` only AFTER the missing-check passes. The marker is unreachable on a failed install. This mirrors the established `install_or_update` discipline (steamcmd exits 0 on failure → binary-presence check gates the `.installed` marker) — same pattern, correctly reused, not a parallel invention.
- **Fast-path skip gate is correct.** `[[ -f marker && -f msvcp && -f vcrt && -f vcrt1 ]]` requires BOTH the marker AND all three DLLs, so a prefix nuke (DLLs gone, marker survives only if it lived in the prefix — it lives at `${STEAM_COMPAT_DATA_PATH}/.vcredist-installed`, sibling to `pfx/`, so it CAN survive a `pfx/` wipe) still forces reinstall because the DLL checks fail. The ADR's "prefix reset re-triggers correctly" claim holds: a `rm -rf .../pfx` removes the system32 DLLs, the `&& -f msvcp` conjunct goes false, reinstall runs. Correct.
- **Version wording corrected accurately.** entrypoint.sh now says only "VC++ 2019 runtime"/"VC++ 2019 redist" — no false "14.2x" build precision anywhere (grep confirms zero "14.2" strings). The `aka.ms/vs/16` URL is the VS 2019 distribution channel; I resolved it live (301 → download.visualstudio.microsoft.com, 200, ~25MB) — it serves Microsoft's current merged VC++ 2015-2022 (14.x) redistributable, which provides the VC++ 2019 runtime (`msvcp140`, `vcruntime140`, `vcruntime140_1`) AsaApi needs. The ADR frames this as evergreen-fetch-then-frozen with the named tradeoff. Accurate.
- **Big-O comment compliant.** `Time: O(1)  Space: O(1) — missing[] bounded to 3 elements (constant)` — Hard Rule 7 satisfied, the `Space:` annotation the coordinator's round-1 fix asked for is present and correct (the array is bounded to 3, genuinely O(1)).
- **Quoting clean under `set -euo pipefail`.** Every variable expansion in the new block is double-quoted (`"${pfx_sys32}"`, `"${marker}"`, `"${missing[@]}"`). `printf "  %s\n" "${missing[@]}"` correctly iterates the array. `${#missing[@]}` arithmetic comparison is safe. No word-split hazards.

### Required Fixes (BLOCK only — empty if PASS)
None — phase ready to commit.

### Concerns (non-blocking, but will bite later)
1. **entrypoint.sh:144-145, 189** — `STEAM_COMPAT_DATA_PATH` is consumed under `set -u` with no `: "${STEAM_COMPAT_DATA_PATH:=...}"` default-assignment in this script (unlike `STEAMCMD_DIR` which gets one at line 205). It is supplied by the base image / compose env. This is **pre-existing, not introduced by Phase 3** — line 189's `mkdir -p "${STEAM_COMPAT_DATA_PATH}"` already depended on it before this phase, and `main` calls that mkdir (189) before `install_vcredist` (212), so the dir exists by the time the new function dereferences it. If that env var is ever unset, the script already aborted at 189 long before the new code. Not a regression; noting only for completeness. No action required for this phase.
2. **Plan deviation entry** — the coordinator added a `## Design Divergences` entry to plan.md and amended `build-time-vs-runtime.md`'s VC++ table row (originally "Dockerfile") to reflect the entrypoint reality. That's design-compliance-reviewer's lane, not mine — cross-flag only, no code-quality issue on my side.

### Laziness Pattern Audit
- Placeholder / mock pollution: PASS — no dummy values; `/opt/vcredist/VC_redist.x64.exe` is a real baked artifact, DLL names are the real runtime DLLs.
- Half-finished implementations: PASS — full happy-path + failure-path. The install failure mode (DLLs missing) is handled with `exit 1` + diagnostic listing the missing files and expected path. Not happy-path-only.
- Type escape hatches (code-quality angle): N-A — shell, no type system; no `eval`/unquoted-glob hazards.
- Smuggled TODOs (code-quality angle): PASS — no TODO/FIXME/phase-reference/`not implemented` markers in the new shell or the ADR.
- Magic constants without provenance: PASS — the three DLL filenames are the named VC++ 2019 runtime DLLs (self-documenting, provenance stated in-comment); 3010/1638 exit codes are documented inline as Microsoft installer benign codes with their meanings; `aka.ms/vs/16` URL provenance is documented in both Dockerfile comment and ADR.
- Documented deviations — adversarial inputs constructed: PASS — the executor's report frames the rc-capture as "DLL check is the sole arbiter, set -e no longer aborts." Adversarial inputs I constructed across 3 strategies: (1) **benign-nonzero-but-DLLs-present** (rc=3010, all 3 DLLs landed) → log line printed, missing[] empty, marker touched, return 0 ✓ correct; (2) **rc=0-but-DLLs-missing** (installer lies success, e.g. wrong prefix) → no rc log, missing[] populated, `exit 1` fires — the gate catches a false-success, which is the exact failure mode the design claims to defend ✓; (3) **prefix-reset second-caller** (pfx/ nuked after a prior success, marker survives) → fast-path conjunct `&& -f "${msvcp}"` goes false → full reinstall re-runs ✓ matches ADR claim. None broke the design. Deviation validated.

### Test Coverage Audit
N/A — not a bug-fix or Tier A plan. This is infrastructure shell (Dockerfile + entrypoint) with no unit-test harness in the project; the "test" is the idempotent boot path itself, and the failure-path `exit 1` + DLL-presence gate IS the runtime assertion. No existing test was weakened (no test files in diff).
- Bug-fix Phase 1 failing test present: N/A
- Test weakening detected: PASS — no test files touched.
- Tier A invariants tested: N-A
- Tier A adversarial cases: N-A

### Bottom Line
Chief, the executor actually nailed both fixes this round — rc-capture is the correct decoupled pattern, the DLL check is a real gate not theater, and the version wording stopped lying about a build number it never knew. Ship it.
