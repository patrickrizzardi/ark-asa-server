## Acceptance Verifier Report: m2-shared-economy-store Phase 3

### Diff Scope
- Files changed: 8
- Lines added/removed: +186 / -3
- Diff source: `git diff 1f9f1b7` (phase 2 commit → HEAD; uncommitted working-tree changes included)

---

### Per-AC Audit (structured — coordinator parses this to write Evidence sub-bullets into plan file)

--- AC ENTRY ---
AC: "After first boot, `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` contains `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`"
Verdict: MET
Evidence: entrypoint.sh (new function `install_vcredist()` lines +130–+177 in diff); specifically the post-install verification block that checks `${pfx_sys32}/msvcp140.dll`, `${pfx_sys32}/vcruntime140.dll`, `${pfx_sys32}/vcruntime140_1.dll` and exits 1 if any are absent; and Dockerfile lines +56–+63 baking `/opt/vcredist/VC_redist.x64.exe` into the image.
Reason: The evidence ceiling for this repo is static (no live docker build runnable here; runtime boot deferred to Phase 4/dell per coordinator context and Phase 2 precedent). Within that ceiling the evidence is complete: (1) the Dockerfile bakes the VC++ 2019 installer at `/opt/vcredist/VC_redist.x64.exe` (new `RUN` block, diff Dockerfile +56–+63); (2) `install_vcredist()` runs `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` into the prefix; (3) immediately after, it checks for all three DLLs by exact path and calls `exit 1` with a FATAL message if any are missing — so the only way boot succeeds is if all three DLLs are present in the exact system32 path the AC names. The install path is wired into `main()` after `deploy_plugins` (diff entrypoint.sh +201). The static shell logic provably implements the AC's behavior; runtime confirmation is Phase 4 scope.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "The install-skip is gated on actual DLL presence (not a bare marker); a second boot skips the install (log shows the skip), and a `pfx/` reset correctly RE-triggers the install rather than falsely skipping"
Verdict: MET
Evidence: entrypoint.sh `install_vcredist()` fast-path gate (diff lines ~+155–+160): `if [[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]; then echo "[entrypoint] VC++ 2019 redist already installed — skipping." return 0; fi` — all three DLL paths AND the marker must be present to skip; DLL-check code comment at diff line ~+140: "Skip gate: check for the three runtime DLLs directly in the prefix system32 rather than relying on a bare marker file. A marker-only gate would falsely skip after a pfx/ reset…"
Reason: Three sub-behaviors in this AC, all covered statically within the evidence ceiling:

1. **Skip gated on DLL presence, not bare marker**: The fast-path condition requires `&&` conjunction of all four: marker AND msvcp140.dll AND vcruntime140.dll AND vcruntime140_1.dll. If the marker is present but DLLs are absent (pfx reset scenario), the condition is false — the function falls through to reinstall. Not marker-only.

2. **Second boot skips with log**: When all four conditions hold (warm boot, no pfx reset), the function echoes `"[entrypoint] VC++ 2019 redist already installed — skipping."` and returns 0. The log message is exactly what the AC requires.

3. **pfx/ reset re-triggers install**: After a prefix nuke, the three DLL paths become missing. The fast-path condition fails (even if the `.vcredist-installed` marker survives on the volume parent dir). The function proceeds to reinstall. The comment in-code explicitly names this invariant. ADR 0002 Consequences section also documents it: "Prefix reset re-triggers VC++ install correctly."

All three sub-behaviors are mechanically enforced by the gate logic, not just described. Runtime receipt deferred to Phase 4 per evidence ceiling.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "`build-time-vs-runtime.md` table row for VC++/prefix amended to reflect volume-backed-prefix → entrypoint, with the rationale note"
Verdict: MET
Evidence: `.claude/rules/build-time-vs-runtime.md` diff — table row changed from `| Wine prefix + VC++ redist install | **Dockerfile** | pre-warm once → reproducible + fast boot |` to `| Wine prefix + VC++ redist install | **entrypoint** (volume-backed prefix — see note) | Q1 yes: prefix lives on the mounted ark-game volume → entrypoint |`; plus new "Note on VC++ redist placement" paragraph added immediately after the table (diff lines +37–+43) explaining the original assumption, the correct 3-question test resolution, and pointing to ADR 0002.
Reason: Both required elements are present: (1) the table row itself is amended to say "entrypoint" with the volume-backed-prefix qualifier and cites the 3-question test result; (2) the rationale note explains the original row assumed prefix-in-image, the correct resolution under the 3-question test (Q1 yes → entrypoint), and cross-references ADR 0002. The rule doc no longer contradicts the implementation, satisfying Rule 00 (one consistent home). This AC is fully verifiable statically.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "ADR `0002` exists (pattern + 3-question-test rationale); `.claude/design-sources.md` created registering the rule + both ADRs `[locked]`"
Verdict: MET
Evidence: `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — new file, 104 lines; contains `doc-type: adr`, `id: "0002"`, `status: accepted`, Context section with 3-question-test table applied to both VC++ and plugins, Decision section, Rejected alternatives, Consequences; `.claude/design-sources.md` — new file, 8 lines; registers three `[locked]` entries: `build-time-vs-runtime.md`, `0001-db-engine-mariadb.md`, `0002-runtime-deploy-of-image-baked-artifacts.md`.
Reason: The AC has three sub-requirements:

1. **ADR 0002 exists**: File is new in the diff at the correct path under `docs/internal/decisions/`. Confirmed.

2. **Pattern + 3-question-test rationale**: The Context section contains a full 3×3 table applying all three questions to both VC++ install and plugin deploy use cases, with "Any yes → entrypoint" conclusion. The Decision section articulates the two-piece split pattern. Rejected alternatives document why all other approaches fail. Consequences section names costs explicitly (no duct tape language). The rationale is substantive, not hand-waved.

3. **`.claude/design-sources.md` created registering the rule + both ADRs [locked]**: File is new in the diff. Contains `[locked]` entries for `build-time-vs-runtime.md`, `docs/internal/decisions/0001-db-engine-mariadb.md`, and `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`. All three required registrations are present. The format matches the `[locked]` sentinel the design-compliance gate checks.

All three sub-requirements MET. Fully statically verifiable.
--- END AC ENTRY ---

---

### Overall Verdict

OVERALL VERDICT: PASS — all 4 AC are MET

### Required Fixes

None — all ACs MET.

### Bottom Line

Chief, all four ACs check out cold. The DLL-presence gate is the real deal — marker AND three explicit file paths in logical conjunction, with the pfx-reset scenario explicitly named in both the comment and the ADR. The rule doc amendment and design-sources registry are clean, complete, and cross-referenced. Static evidence ceiling honored throughout; nothing being asked of this diff that requires a live boot.
