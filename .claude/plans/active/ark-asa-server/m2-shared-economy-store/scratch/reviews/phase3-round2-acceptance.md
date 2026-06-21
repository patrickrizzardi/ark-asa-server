# Acceptance Verifier Report: m2-shared-economy-store Phase 3 Round 2

### Diff Scope
- Files changed: 7 (entrypoint.sh, Dockerfile, .claude/rules/build-time-vs-runtime.md, docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md, .claude/design-sources.md, .claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md, .claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md, .claude/state.md)
- Lines added/removed: +180 / -3 (approximate from diff)
- Diff source: `git diff 1f9f1b7` (phase 2 commit to working tree / HEAD)

### Round 2 Context

Round 1 returned OVERALL PASS (4/4 MET). Two changes landed since:

1. **entrypoint.sh `install_vcredist()`**: the installer invocation now uses `|| rc=$?` to capture the exit code instead of letting `set -e` abort on a benign non-zero return (3010/1638). The DLL-presence check is explicitly declared "the sole success/failure arbiter." A `Space:` Big-O annotation was also added to the function header.

2. **docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md**: version-precision language corrected (evergreen `vs/16` URL acknowledged, ABI-stability contract named, "frozen into the image layer at build time" precision added). The pinning-tradeoff wording in Consequences was expanded.

The coordinator flagged AC1/AC2 (install+verify logic) and AC4 (ADR 0002) as the affected evidence surfaces. AC3 (rule-table amendment) is unchanged this round. All four are re-audited below.

---

### Per-AC Audit

--- AC ENTRY ---
AC: "After first boot, `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` contains `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`"
Verdict: MET
Evidence: entrypoint.sh `install_vcredist()` — `local msvcp="${pfx_sys32}/msvcp140.dll"`, `local vcrt="${pfx_sys32}/vcruntime140.dll"`, `local vcrt1="${pfx_sys32}/vcruntime140_1.dll"` (lines ~148-150 of the new block); `missing[]` array check asserts all three present after the install run; `exit 1` with named-DLL error output fires if any are absent. Dockerfile lines 56-62 bake `VC_redist.x64.exe` to `/opt/vcredist/` via `aka.ms/vs/16/release/vc_redist.x64.exe` (the vs/16 corrected URL). The `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` invocation in `install_vcredist()` is what deposits the DLLs into the prefix at runtime.
Reason: The shell logic proves the behavior at the static evidence ceiling established in Round 1: after `proton run` completes (rc captured, not trusted), the function walks all three DLL paths and fails fast with named output if any are absent. The only way `install_vcredist()` can return 0 is if all three DLLs are confirmed present. The round-2 rc-capture fix (benign 3010/1638 no longer aborts before the DLL check) actually strengthens this — the DLL check now executes unconditionally after the installer run. The installer is baked from the correct `vs/16` URL. AC is provably implemented by the static shell logic.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "The install-skip is gated on actual DLL presence (not a bare marker); a second boot skips the install (log shows the skip), and a `pfx/` reset correctly RE-triggers the install rather than falsely skipping"
Verdict: MET
Evidence: entrypoint.sh `install_vcredist()` fast-path gate (lines ~155-158 of new block): `if [[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]; then echo "[entrypoint] VC++ 2019 redist already installed — skipping."; return 0; fi`. Three legs of the AC:
  (a) Skip gated on DLL presence — the `if` condition requires `marker` AND all three DLL files. Bare-marker-only skip is impossible: the gate requires all three `-f "${dll}"` tests to pass.
  (b) Second boot skips — on a warm prefix all three DLLs exist (deposited by first boot) + marker written by `touch "${marker}"` at end of first boot → gate fires → "already installed — skipping." log line emitted → `return 0`. Log line is a concrete string: `[entrypoint] VC++ 2019 redist already installed — skipping.`
  (c) pfx/ reset re-triggers — after `rm -rf ${STEAM_COMPAT_DATA_PATH}/pfx`, the three DLL paths no longer exist. Gate condition evaluates false (DLL `-f` tests fail) → falls through to installer run. The marker file's path is `${STEAM_COMPAT_DATA_PATH}/.vcredist-installed` (one level above `pfx/`), so it survives a `pfx/` wipe. But the gate requires BOTH marker AND DLLs — marker surviving without DLLs → gate still fails → reinstall correctly triggered. This is the key design: marker alone cannot produce a false skip.
Reason: The round-2 fix is directly load-bearing here. In round 1 the installer invocation was `proton run … || true` (or equivalent allowing set -e to continue) — the concern was that a benign non-zero exit from the installer could abort execution before the DLL check ran under `set -euo pipefail`. The fix: `local rc=0; proton run … || rc=$?` captures the code without aborting. The DLL-check block now executes unconditionally. The "DLL presence is the sole arbiter" comment matches the implementation. All three legs of the AC are implemented in the static shell logic.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "`build-time-vs-runtime.md` table row for VC++/prefix amended to reflect volume-backed-prefix → entrypoint, with the rationale note"
Verdict: MET
Evidence: `.claude/rules/build-time-vs-runtime.md` line 28 (diff hunk): row changed from `| Wine prefix + VC++ redist install | **Dockerfile** | pre-warm once → reproducible + fast boot |` to `| Wine prefix + VC++ redist install | **entrypoint** (volume-backed prefix — see note) | Q1 yes: prefix lives on the mounted ark-game volume → entrypoint |`. Rationale note added at lines 37-42: "Note on VC++ redist placement: the table row above was originally 'Dockerfile'… This project's Proton prefix is volume-backed… The 3-question test resolves it correctly: Q1 ('depends on a mounted volume?') = yes → entrypoint. The installer binary itself is baked in the image at `/opt/vcredist/` (immutable); it runs against the live prefix at runtime. See ADR 0002."
Reason: The diff shows the exact row substitution (old "Dockerfile" → new "entrypoint (volume-backed prefix — see note)") and the rationale note appended immediately after the table. Both elements the AC requires — the row amendment AND the rationale note — are present in the diff. This AC is unchanged from round 1; the round-2 changes did not touch this file. Evidence holds.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "ADR `0002` exists (pattern + 3-question-test rationale); `.claude/design-sources.md` created registering the rule + both ADRs `[locked]`"
Verdict: MET
Evidence:
  (a) `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — new file, +128 lines. Front-matter: `doc-type: adr`, `id: "0002"`, `status: accepted`. Contains the 3-question-test table (lines 38-43 of the file) applied to both VC++ and plugin cases, with the correct "any yes → entrypoint" conclusion. Pattern documented in Decision section. Consequences section names the VC++ evergreen-fetch-then-frozen tradeoff with ABI-stability rationale — the round-2 precision correction.
  (b) `.claude/design-sources.md` — new file, +8 lines. Registers all three `[locked]` entries: `build-time-vs-runtime.md`, `0001-db-engine-mariadb.md`, `0002-runtime-deploy-of-image-baked-artifacts.md`. Format matches the spec header comment.
Reason: The AC asks for ADR 0002 with pattern + 3-question-test rationale, and for design-sources.md with the rule + both ADRs locked. Both artifacts exist in the diff at the required content level. The round-2 edits to ADR 0002 (version-precision + pinning-tradeoff wording) do not weaken the evidence — they correct the accuracy of the tradeoff description without removing any required content. The 3-question table, the pattern description, the rejected alternatives, and the consequences are all present and correct in the final file on disk.
--- END AC ENTRY ---

---

### Overall Verdict

OVERALL VERDICT: PASS — all 4 AC are MET

### Required Fixes

None — all ACs MET.

### Bottom Line

Chief, the round-2 install-block fix does exactly what it claims: `|| rc=$?` decouples the installer's benign-non-zero exit from `set -e`, so the DLL-presence check now runs unconditionally and is genuinely the sole arbiter. All four ACs hold at the static evidence ceiling. Clean pass.
