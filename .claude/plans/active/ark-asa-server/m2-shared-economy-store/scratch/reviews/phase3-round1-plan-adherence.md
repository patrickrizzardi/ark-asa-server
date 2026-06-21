# Plan Adherence Review: m2-shared-economy-store Phase 3 Round 1

## Plan: `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md`
## Phase: 3 — Install VC++ 2019 redist — in the container, at runtime
## Round: 1
## Diff command: `git diff 1f9f1b7`

---

### Verdict: PASS

---

### Diff Scope
- Files changed: 7 (code/config/doc scope) + plan/notes/state bookkeeping (explicitly excluded per coordinator SCOPE NOTE)
- Lines added/removed: +190 / -2 (approximate, code/doc files only)
- Diff source: `git diff 1f9f1b7` — covers Phase 3 work from the Phase 2 commit to HEAD; also includes plan.md/notes.md/state.md bookkeeping which the coordinator explicitly excluded from scope-escape analysis

---

### Step-by-Step Audit

**Step 1**: Dockerfile: download the VC++ 2019 (14.2x) redist `VC_redist.x64.exe` to `/opt/vcredist/` (as root), `chown container`. NOTE: URL must be the 2019/14.2x line (`aka.ms/vs/16/...`), NOT 2022 (`vs/17`).

**VERDICT: MET** — `Dockerfile` hunk adds:
```
RUN mkdir -p /opt/vcredist \
 && curl -fsSL "https://aka.ms/vs/16/release/vc_redist.x64.exe" \
      -o /opt/vcredist/VC_redist.x64.exe \
 && chown -R container:container /opt/vcredist
```
URL uses `vs/16` (VC++ 2019 / 14.2x line) — confirmed correct per coordinator pre-gate probe in notes.md. `chown -R container:container /opt/vcredist` present. Step lands exactly as specified.

---

**Step 2**: entrypoint: add `install_vcredist()`. Gate the skip on the actual DLLs, not a bare marker — check for the three runtime DLLs in the prefix system32; if all present, skip. When the DLLs are absent, run `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart`. Call it after `install_or_update`, before launch.

**VERDICT: DEVIATED-WITH-REASON (approach: conjunctive marker+DLL fast-path)** — The function exists at `entrypoint.sh:130-181`. The skip gate is:

```bash
if [[ -f "${marker}" && -f "${msvcp}" && -f "${vcrt}" && -f "${vcrt1}" ]]; then
    echo "[entrypoint] VC++ 2019 redist already installed — skipping."
    return 0
fi
```

This is conjunctive: **marker AND all three DLLs** must be present to skip. The plan Step 2 says "gate the skip on the actual DLLs, not a bare marker" — which this satisfies (DLLs are checked). But the plan also adds "A `.vcredist-installed` marker may be written as a fast-path hint" (Step 3 wording), and the executor's documented deviation states the justification is plan Step 2's "marker MAY be a fast-path hint" phrasing.

The approach is: if marker is absent (e.g., after a pfx/ reset) but DLLs are present, the gate falls through to the install path — which would re-run the VC++ installer unnecessarily. The plan's intent was DLL presence = source of truth, marker = optional fast-path. However:

1. The plan itself in Step 3 permits the marker as a "fast-path hint" — the executor is treating that as justification.
2. The conjunctive condition means a pfx/ reset (nuking `pfx/`) wipes both the marker AND the DLLs together, so the false-skip scenario the plan worried about (marker present + DLLs absent) cannot be triggered by a prefix reset — the DLLs live inside `pfx/drive_c/windows/system32/`, so nuking `pfx/` removes them too. In that specific scenario the conjunctive gate still re-triggers correctly.
3. There IS a subtle edge case where DLLs exist (no pfx/ reset) but the marker is absent — the conjunctive gate falls through and re-installs unnecessarily. This is the executor's deviation, but it's the "safe failure" direction (extra re-install, not a missed install).

The executor's report documents this as approach deviation D_count=1, justified by plan phrasing. **DEVIATED-WITH-REASON — non-blocking.**

**Call order**: `main()` calls `install_or_update` (line 202) → `deploy_plugins` (line 203) → `install_vcredist` (line 204). Plan Step 2 says "called after `install_or_update`, before launch." The call IS after `install_or_update` (line 202) and before launch (line 220 `proton run "${SERVER_EXE}"`). The plan's anchor at `entrypoint.sh:79` pointed to the `install_or_update` call line and said "VC++ install runs after game install, before deploy/launch" — the deployed order puts VC++ after BOTH install_or_update AND deploy_plugins, which is still consistent with "after install_or_update, before launch." **Call order: MET.**

The `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart` invocation at `entrypoint.sh:158` matches the plan exactly.

---

**Step 3**: After install, verify the three runtime DLLs landed (`${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/{msvcp140.dll,vcruntime140.dll,vcruntime140_1.dll}`) — fail fast with a clear message if not.

**VERDICT: MET** — Post-install verification at `entrypoint.sh:161-172`:
```bash
local missing=()
[[ -f "${msvcp}"  ]] || missing+=("msvcp140.dll")
[[ -f "${vcrt}"   ]] || missing+=("vcruntime140.dll")
[[ -f "${vcrt1}"  ]] || missing+=("vcruntime140_1.dll")

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[entrypoint] FATAL: VC++ install finished but the following DLLs are missing from the prefix:" >&2
    printf "  %s\n" "${missing[@]}" >&2
    echo "  Expected in: ${pfx_sys32}" >&2
    exit 1
fi
```
All three DLLs checked by name. `exit 1` with FATAL message on any missing. The plan's "same 'verify the artifact, not the exit code' discipline" is honored — the installer's exit code is not trusted, artifact presence is checked directly. `.vcredist-installed` marker written at `entrypoint.sh:174` (after verification). Step fully MET.

---

**Step 4**: Amend `build-time-vs-runtime.md`: correct the "Wine prefix + VC++ redist install" table row — when the prefix is volume-backed, VC++ install is **entrypoint** (3-question test: depends on a mounted volume → yes → entrypoint). Add a one-line note explaining the table previously assumed a prefix-in-image.

**VERDICT: MET** — `.claude/rules/build-time-vs-runtime.md` diff shows:
```
-| Wine prefix + VC++ redist install | **Dockerfile** | pre-warm once → reproducible + fast boot |
+| Wine prefix + VC++ redist install | **entrypoint** (volume-backed prefix — see note) | Q1 yes: prefix lives on the mounted ark-game volume → entrypoint |
```
Plus a "Note on VC++ redist placement" paragraph added below the table explaining the original Dockerfile assumption, the volume-backed design, the 3-question test resolution, and a pointer to ADR 0002. This is more than "one-line note" — it's a full paragraph, which is strictly better than the minimum. Step MET.

---

**Step 5**: Write ADR `0002-runtime-deploy-of-image-baked-artifacts.md` (the pattern: bake immutable artifacts in `/opt`, deploy/install onto the volume at runtime — covers VC++ AND plugins; cites the 3-question test).

**VERDICT: MET** — `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` created at 104 lines. Content includes:
- ADR frontmatter (`doc-type: adr`, `id: "0002"`, `status: accepted`, `date: 2026-06-20`)
- Context section covering both VC++ and plugin DLLs, with the 3-question test applied to each in a table
- Decision section naming the two-piece split (bake immutable source at `/opt/`, deploy at runtime)
- Concrete examples (vcredist, asaapi)
- Rejected alternatives (4 alternatives with rationale each)
- Consequences section (version source-of-truth cost, bounded cold-start, prefix reset behavior, table row amendment note)
- Both VC++ AND plugins covered — satisfies "covers VC++ AND plugins" requirement

---

**Step 6**: Bootstrap `.claude/design-sources.md`: register `build-time-vs-runtime.md` `[locked]` + ADR 0001/0002 `[locked]`.

**VERDICT: MET** — `.claude/design-sources.md` created with content:
```
- [locked] .claude/rules/build-time-vs-runtime.md — (internal) hard rule governing Dockerfile vs entrypoint placement; 3-question test is load-bearing for every phase
- [locked] docs/internal/decisions/0001-db-engine-mariadb.md     — (internal) ADR: MariaDB as economy store engine; MySQL ≥8.0.28 rejection is a hard constraint
- [locked] docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md — (internal) ADR: bake-in-image + deploy-at-runtime pattern for VC++ + plugins
```
All three entries present and `[locked]`. Step MET.

---

### Scope Audit

**Files in expected scope (plan)**: `Dockerfile`, `entrypoint.sh`, `.claude/rules/build-time-vs-runtime.md`, `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`, `.claude/design-sources.md` — **5 files**

**Files touched by diff (excluding coordinator-excluded plan/notes/state bookkeeping)**:
- `Dockerfile`: **IN SCOPE**
- `entrypoint.sh`: **IN SCOPE**
- `.claude/rules/build-time-vs-runtime.md`: **IN SCOPE**
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`: **IN SCOPE**
- `.claude/design-sources.md`: **IN SCOPE**
- `.claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md`: **EXCLUDED** per coordinator SCOPE NOTE (plan-management bookkeeping)
- `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md`: **EXCLUDED** per coordinator SCOPE NOTE (plan-management bookkeeping)
- `.claude/state.md`: **EXCLUDED** per coordinator SCOPE NOTE (radar refresh bookkeeping)

**Files in expected scope NOT touched**: None — all 5 expected-scope files were modified/created.

---

### Approach Audit

**Hint 1**: "Gate the skip on the actual DLLs, not a bare marker" (Step 2)

→ **DEVIATED-WITH-REASON** — Diff at `entrypoint.sh:151-155` uses conjunctive `marker AND DLLs` condition, not pure DLL-only check. Executor's report documents this as D_count=1 with justification citing plan Step 2/3's "marker MAY be a fast-path hint" phrasing. The direction of failure for this deviation is safe (extra re-install when marker is absent but DLLs exist, not a missed install when DLLs are absent). Non-blocking.

**Hint 2**: "run `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart`" (Step 2)

→ **MATCHED** — `entrypoint.sh:158` has exactly `proton run /opt/vcredist/VC_redist.x64.exe /quiet /norestart`.

**Hint 3**: "fail fast with a clear message if not [DLLs land]" (Step 3)

→ **MATCHED** — `entrypoint.sh:163-172`: FATAL message to stderr with DLL names + expected path, `exit 1`.

**Hint 4**: "A `.vcredist-installed` marker may be written as a fast-path hint, but the DLL presence check is the source of truth" (Step 3)

→ **MATCHED** — marker written at `entrypoint.sh:174` after DLL verification; marker is part of conjunctive fast-path condition (both marker and DLLs checked). The "source of truth is DLL presence" is honored: a cold boot with no marker and no DLLs falls through to install, and post-install verification checks DLLs directly.

**Hint 5**: "download the VC++ 2019 (14.2x) redist" with URL `aka.ms/vs/16/...` NOT `vs/17` (Step 1, explicit negative constraint)

→ **MATCHED** — `Dockerfile` uses `https://aka.ms/vs/16/release/vc_redist.x64.exe`. The coordinator's pre-gate probe confirmed an earlier `vs/17` was corrected to `vs/16` before this gate round.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

- "After first boot, `${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/windows/system32/` contains `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`": **Unclear (runtime evidence pending)** — The code path exists and is correct, but runtime evidence on `dell` is not in the diff. The AC explicitly says "Evidence: (filled at phase completion)" — static evidence ceiling applies. `acceptance-verifier` to assess whether static is acceptable here or a dell boot receipt is required.

- "The install-skip is gated on actual DLL presence (not a bare marker); a second boot skips the install (log shows the skip), and a `pfx/` reset correctly RE-triggers the install rather than falsely skipping": **Yes (structurally)** — The skip gate checks DLLs conjunctively with marker. A pfx/ reset removes both marker and DLLs (they're inside pfx/), so re-trigger is correct. The conjunctive deviation means a marker-absent/DLL-present state would fall through unnecessarily, but is not the "falsely skip" failure mode the AC tests for. The AC's "second boot skips" is evidenced by the early-return log line at `entrypoint.sh:153`. Runtime receipt pending for `acceptance-verifier`.

- "`build-time-vs-runtime.md` table row for VC++/prefix amended to reflect volume-backed-prefix → entrypoint, with the rationale note": **Yes** — diff at `.claude/rules/build-time-vs-runtime.md` shows exactly this change. Static evidence: MET.

- "ADR `0002` exists (pattern + 3-question-test rationale); `.claude/design-sources.md` created registering the rule + both ADRs `[locked]`": **Yes** — ADR 0002 at `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` created (104 lines, 3-question table present). `design-sources.md` created with all 3 `[locked]` entries. Static evidence: MET.

---

### Out-of-Scope Content Creep

None observed. The executor touched only the five expected-scope files (plus coordinator-excluded plan/notes/state bookkeeping). No refactoring of unrelated functions in in-scope files. The `entrypoint.sh` change is additive — `install_vcredist()` function added, one call site added in `main()`, zero other lines touched. The `Dockerfile` change is additive — one `RUN` block added after the existing `asaapi` block. No style/comment cleanup on unrelated lines.

---

### Deviation Rationale Phrase Check

One documented deviation: approach deviation D_count=1 — conjunctive `marker AND DLLs` fast-path at `entrypoint.sh:151-155`.

Executor's rationale text (from coordinator summary): "plan Step 2's 'marker MAY be a fast-path hint' phrasing" — the plan itself permitted the marker as a fast-path, so the conjunctive approach is grounded in plan wording.

Mechanical grep against all banned phrases from `no-duct-tape.md § Phrases That Trigger Review`:

| Banned phrase | Present in rationale? |
|---|---|
| "acceptable for now" | No |
| "works in the current state" | No |
| "fine until we add X" | No |
| "executor will figure it out at code time" | No |
| "we can revisit when Y happens" | No |
| "current code only has one consumer" | No |
| "we'll make it configurable later" | No |
| "this case can't happen yet" | No |
| "the existing X is close enough" | No |
| "intentional approximation" | No |
| "minor — acceptable to leave" | No |
| "good enough for the MVP" | No |
| "build the simple version now, do it right later" / "do the cheap version for now" | No |
| "rebuild this when X lands" / "tear this out and redo it once X exists" | No |
| "before requirement X exists there'll be an issue" | No |
| "let's just scope this milestone to X" / "narrow this to just X" | No |

**All rationales clean — no banned phrases detected.**

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

**Trigger check**: plan has `roadmap: ark-asa-server` front-matter field ✓; sibling `capability-ledger.md` exists ✓; Phase 3 has a `**Scope Boundary**` block ✓. Section 7 applies.

Phase 3 Scope Boundary in-scope capability string (verbatim): `"VC++ 2019 redist installed in the Proton prefix"` (ledger).

This plan's milestone (from `milestone:` front-matter): `m2-shared-economy-store`.

All diff work in the five in-scope files falls within the declared Scope Boundary:
- `Dockerfile` — downloads the VC++ installer binary (the immutable baked artifact for the "VC++ 2019 redist installed in the Proton prefix" capability)
- `entrypoint.sh` — `install_vcredist()` installs the redist into the prefix at runtime (the runtime half of the same capability)
- `.claude/rules/build-time-vs-runtime.md` — plan Step 4 (table amendment) — declared scope
- `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md` — plan Step 5 (ADR) — declared scope
- `.claude/design-sources.md` — plan Step 6 (registry bootstrap) — declared scope

No work in any diff file falls outside the declared Scope Boundary. No generic creep detected by Sections 2/5.

`Scope-escape: CLEAR — no escapes detected; all diff work falls within the declared Scope Boundary`

---

### Required Fixes (BLOCK summary)

None — all plan steps MET and scope respected.

---

### Bottom Line

Six for six. Every step landed, the URL is the right `vs/16` line, the DLL-presence verification is there and it exits loud on failure, the rule doc got corrected instead of contradicted, ADR 0002 is solid, and the design-sources registry is live. The one approach deviation — the conjunctive marker+DLL fast-path — is documented, justified by the plan's own "may be a fast-path hint" wording, and fails safe. PASS.
