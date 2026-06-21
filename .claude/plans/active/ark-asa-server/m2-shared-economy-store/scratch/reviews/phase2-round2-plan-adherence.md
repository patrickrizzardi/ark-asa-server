# Plan Adherence Review: m2-shared-economy-store Phase 2 Round 2

### Verdict: PASS

### Diff Scope
- Files changed: 5
- Lines added/removed: +176 / -2
- Diff source: `git diff 21fe5a8` (working tree vs Phase 1 committed SHA)
- Files in diff: `notes.md` (+69/-0), `plan.md` (+3/-1), `.claude/state.md` (+1/-1), `Dockerfile` (+30/-0), `entrypoint.sh` (+74/-0)

---

### Step-by-Step Audit

Phase 2 Steps (from plan.md Phase 2):

1. **Resolve the distribution channel FIRST**: MET — `notes.md` "Phase 2 — distribution channel resolution" block documents the full channel resolution: both `ark-server-api.com` URLs confirmed non-auth-gated via live `curl` tests, ZIPs confirmed valid (PK magic bytes), Permissions bundled in AsaApi ZIP confirmed, pinned versions recorded. Step 1's "record the choice + pinned versions in this plan's notes before proceeding" sub-requirement satisfied. Evidence: `notes.md` lines 19–52.

2. **Dockerfile ARG pins + RUN steps to download into `/opt/asaapi/`**: MET — `Dockerfile:32-34` carry `ARG ASAAPI_VERSION=1.21`, `ARG ARKSHOP_VERSION=1.4`, `ARG PERMISSIONS_VERSION=1.1`. `Dockerfile:35-55` contains the `RUN` chain: downloads AsaApi ZIP, unpacks, `cp -r ArkApi` into `/opt/asaapi/`, removes "ONLY FOR DEVELOPERS" dir, copies six root-level files explicitly, downloads ArkShop ZIP, copies `ArkShop/` contents to `/opt/asaapi/ArkApi/Plugins/ArkShop/`, cleans temp dirs, strips `.pdb` files, `chown -R container:container /opt/asaapi`. DLL-name == folder-name invariant satisfied (`ArkShop/ArkShop.dll` in `/opt/asaapi/ArkApi/Plugins/ArkShop/`; Permissions already named correctly in bundled tree). Evidence: `Dockerfile:32-55`.

3. **entrypoint `deploy_plugins()` after `install_or_update`, before launch, clean-replace**: MET — `entrypoint.sh:53-130` defines `deploy_plugins()`. Called at `entrypoint.sh:151` after `install_or_update` and before the `LOG_FILE` clear + launch block. Clean-replace strategy: stash operator `config.json` files from `ArkApi/Plugins/*/`, `rm -rf` the AsaApi-owned paths (ArkApi/, AsaApiLoader.exe, AsaApiLoader.pdb, root DLLs), `cp -r ArkApi` fresh from image, copy root binaries, restore stashed configs. Does NOT touch non-AsaApi `Win64` content. Seed-if-absent for the framework `config.json`. Evidence: `entrypoint.sh:53-130`, call at line 151. Plan said "rsync --delete" OR "remove-then-copy" — Deviation D1 (stash-rm-cp) was previously adjudicated PASS by deviation-judge #2 round 1; carries as DEVIATED-WITH-REASON (documented in `scratch/phase2-deviations.md`).

4. **Keep launch as `ArkAscendedServer.exe` (unchanged this phase)**: MET — no changes to `entrypoint.sh:24` (`SERVER_EXE=`), no changes to the launch block at `entrypoint.sh:95`. The `deploy_plugins` call inserts between `install_or_update` and the log-clear, before the launch. Evidence: diff shows no modification to the launch line; `entrypoint.sh` hunk is purely the `deploy_plugins` function block + its single call.

---

### Scope Audit

- Files in expected scope: 2 (`Dockerfile`, `entrypoint.sh`)
- Files touched by diff:

  - `Dockerfile`: IN SCOPE — Phase 2 explicit scope file.
  - `entrypoint.sh`: IN SCOPE — Phase 2 explicit scope file.
  - `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md`: DEVIATION (DOCUMENTED) — executor's report (`scratch/phase2-deviations.md` Deviation #3) cites reason: "clean-replace decision re-homed from notes.md churn to plan.md Decision Ledger row #12 (durable contract); deviation-judge #1 BLOCK remedy (orchestrator-directed Fix 4)." Corroborated by `notes.md` round-2 routing log entry. This is re-homing of an existing decision to its contractually correct home, not contract tampering.
  - `.claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md`: DEVIATION (DOCUMENTED) — executor's report cites: "notes.md carries channel-resolution facts + a one-line pointer (Rule 00 compliant)." The churn document is the defined home for Findings Log content; channel-resolution records belong here per plan architecture. This deviation is present from round 1 and carries forward.
  - `.claude/state.md`: DEVIATION (DOCUMENTED) — executor's report notes round-2 work-item counter update (12/88 done). State.md is the session radar; the progress counter update is a mandatory orchestrator-maintained field. One-line change to the workstream tracking row.

- Files in expected scope NOT touched: none — both expected scope files (`Dockerfile`, `entrypoint.sh`) have substantive changes.

**plan.md contract-tampering check (coordinator-requested):** The diff to `plan.md` is exactly one added row in the Decision Ledger table (row #12, `plan.md:119`) and one updated Phase 1 gate checkbox (`- [ ] Committed: <commit SHA>` → `- [x] Committed: 21fe5a8`, `plan.md:281`). No ACs modified, no gate criteria altered, no scope boundaries changed, no Phase 3/4/5 content touched. Contract intact.

**Phase 3/4/5 bleed check (coordinator-requested):** Zero diff content in Phase 3 (VC++), Phase 4 (launcher flip), or Phase 5 (ArkShop config). `entrypoint.sh` additions add `deploy_plugins()` and its call only. `Dockerfile` additions are the AsaApi/ArkShop bake block only. No `install_vcredist`, no `AsaApiLoader.exe` launch path, no `ENABLE_ASAAPI` toggle, no ArkShop `config.json` injection logic present in the diff. Clean.

---

### Approach Audit

**Approach hint 1**: Step 2 — "download + unzip into `/opt/asaapi/` with the AsaApi tree at the root and plugins under `/opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/` (DLL name == folder name)."
→ MATCHED — `Dockerfile:35-55` unpacks to exactly this layout. `ArkApi/` goes to `/opt/asaapi/ArkApi/`, ArkShop contents go to `/opt/asaapi/ArkApi/Plugins/ArkShop/`. DLL-name == folder-name: ArkShop/ArkShop.dll in ArkShop/, Permissions/Permissions.dll in Permissions/. `chown -R container:container /opt/asaapi` present. `Lib/` excluded (not copied). Evidence: `Dockerfile:39,47-53`.

**Approach hint 2**: Step 2 — "`chown -R container:container /opt/asaapi`"
→ MATCHED — `Dockerfile:55`: `&& chown -R container:container /opt/asaapi`. Evidence: `Dockerfile:55`.

**Approach hint 3**: Step 3 — "after `install_or_update` (entrypoint.sh:79) and before launch"
→ MATCHED — `deploy_plugins` call is at `entrypoint.sh:151`, one line after `install_or_update` and before the `LOG_FILE` clear + launch block. Evidence: `entrypoint.sh:150-151` in diff.

**Approach hint 4**: Step 3 — "cleanly replace the AsaApi/plugin tree on a version bump — stale files from a prior version must not linger"
→ DEVIATED-WITH-REASON (D1) — plan said "rsync --delete ... or remove-then-copy the ArkApi/ + loader paths." Diff implements stash-rm-cp: stash operator configs, `rm -rf` the AsaApi-owned paths, `cp -r` fresh from image, restore stashed configs. Rationale in `scratch/phase2-deviations.md` Deviation #1: "rsync may not be present in parkervcp/steamcmd:proton base image; under set -euo pipefail a missing rsync binary aborts with a confusing error; stash-restore uses only cp/rm (POSIX builtins guaranteed present) and achieves the same stale-file elimination guarantee." Deviation-judge #2 PASSed round 1; re-adjudicated same hunk in round 2 (comment reword at line 119 only; identity hash unchanged). Non-blocking.

**Approach hint 5**: Step 4 — "Keep launch as ArkAscendedServer.exe (unchanged this phase)"
→ MATCHED — launch line untouched. Evidence: absence of changes to `SERVER_EXE` assignment or launch block in diff.

---

### Acceptance Criteria Sanity Check (cross-reference for acceptance-verifier)

All Phase 2 ACs remain in `[ ]` unfilled state — expected, as Phase 2 is not yet committed and runtime evidence is deferred to Phase 4 boot on dell.

- "Image contains `/opt/asaapi/AsaApiLoader.exe` + `/opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/` at pinned versions": Unclear (static) — Dockerfile structure is present; runtime `docker run --rm ls /opt/asaapi` not yet run. Consistent with round-1 acceptance-verifier's "static-evidence ceiling" ruling.
- "After a boot, volume's `…/Binaries/Win64/` contains `AsaApiLoader.exe` + `ArkApi/Plugins/{ArkShop,Permissions}/`": Unclear (static) — deploy_plugins() code is present; boot evidence deferred to Phase 4/dell. Consistent with plan.
- "The deploy step is idempotent — a second boot re-syncs without error": Unclear (static) — code structure supports idempotency (unconditional rm-then-cp is always clean); boot evidence deferred.
- "A version bump cleanly REPLACES the deployed tree — no stale files remain": Unclear (static) — clean-replace mechanism is structurally sound; version-bump test deferred.
- "Pinned versions are recorded (Dockerfile ARGs + plan notes); no auto-latest fetch": Yes — `Dockerfile:32-34` has ARG pins; `notes.md` "Phase 2 — decisions" records pinned versions with versioned URLs confirmed live. Static evidence MET.

No AC has zero corresponding diff content. The "no evidence" gap is runtime-deferred by plan design, not executor omission.

---

### Out-of-Scope Content Creep

**Round-2 specific delta review (coordinator-requested focus):**

- `Dockerfile` line 34 doc-pin comment (`PERMISSIONS_VERSION=1.1  # doc-pin only — …`): IN SCOPE — this is Fix 1 from the round-2 routing (rules-compliance BLOCK on magic constant without provenance; deviation-judge #3 BLOCK on dead pin). Comment added to the Phase 2 ARG block; no adjacent unrelated lines touched.

- `Dockerfile` line 53 `.pdb` strip (`find /opt/asaapi -name '*.pdb' -delete`): IN SCOPE — Fix 2 from round-2 routing (code-reviewer BLOCK on ~65MB .pdb files deploying to volume every boot). Inserted in the same `RUN` chain within the Phase 2 bake block, before `chown`. Directly implements a fix to Phase 2 bake content. No adjacent unrelated lines touched.

- `entrypoint.sh` line 119 comment reword: IN SCOPE — Fix 3 from round-2 routing (rules-compliance BLOCK on phase-ref forward-delivery comment at the original line). Comment now reads "# Seed the AsaApi framework config.json only if absent — never overwrite, so operator/injector edits survive restarts." Durable mechanism description; no phase reference. No adjacent lines touched.

- `plan.md` Decision Ledger row #12: IN SCOPE (documented deviation, orchestrator-directed Fix 4) — re-homes the clean-replace decision to its contractually correct durable home. Adds one table row. No other plan.md content modified.

- `notes.md` churn additions: IN SCOPE (documented deviation, plan-folder churn document) — Phase 2 Findings Log entries, coordinator probe records, round-1 gate summary, round-2 routing entry, decisions section. All within the defined role of `notes.md` as churn/findings log.

None observed as silent creep.

---

### Deviation Rationale Phrase Check

Checking all three documented deviations in `scratch/phase2-deviations.md` against the banned-phrase list from `~/.claude/rules/no-duct-tape.md` § "Phrases That Trigger Review":

**Deviation D1 (stash-rm-cp)** rationale: "rsync may not be present in the parkervcp/steamcmd:proton base image; under set -euo pipefail a missing rsync binary aborts with a confusing error; stash-restore uses only cp/rm (POSIX builtins guaranteed present) and achieves the same stale-file elimination guarantee"

Grep results (case-insensitive substring):
- "acceptable for now" — NOT PRESENT
- "works in the current state" — NOT PRESENT
- "fine until we add X" — NOT PRESENT
- "executor will figure it out at code time" — NOT PRESENT
- "we can revisit when Y happens" — NOT PRESENT
- "current code only has one consumer" — NOT PRESENT
- "we'll make it configurable later" — NOT PRESENT
- "this case can't happen yet" — NOT PRESENT
- "the existing X is close enough" — NOT PRESENT
- "intentional approximation" — NOT PRESENT
- "minor — acceptable to leave" — NOT PRESENT
- "good enough for the MVP" — NOT PRESENT
- "build the simple version now" / "do the cheap version for now" — NOT PRESENT
- "rebuild this when X lands" / "tear this out and redo it once X exists" — NOT PRESENT
- "before requirement X exists there'll be an issue" — NOT PRESENT
- "let's just scope this milestone to X" / "narrow this to just X" — NOT PRESENT

Result: **No banned phrases detected.**

**Deviation D2 (versioned URLs + PERMISSIONS_VERSION doc-pin)** rationale: "?version=latest always fetches current stable regardless of ARG value — confirmed live that ark-server-api.com supports ?version=<N> for both resources; using the ARG in the URL makes the pin mechanically enforced rather than just documented; PERMISSIONS_VERSION is a doc-pin only (round-2 comment), drives no URL"

Grep results: All banned phrases — NOT PRESENT. Result: **No banned phrases detected.**

**Deviation D3 (scope — plan.md Decision Ledger re-homing)** rationale: "clean-replace decision re-homed from notes.md churn to plan.md Decision Ledger row #12 (durable contract); notes.md retains channel-resolution facts + a one-line pointer per Rule 00 one-home"

Grep results: All banned phrases — NOT PRESENT. Result: **No banned phrases detected.**

All rationales clean — no banned phrases detected.

---

### Execution-Time Scope-Escape Facts (Gate 1 — Route-A flags for the orchestrator)

[Per Section 7 — this plan IS under a per-initiative roadmap (`roadmap: ark-asa-server` front-matter) and a sibling `capability-ledger.md` exists. Phase 2 carries a `**Scope Boundary**` block.]

**Scope-escape: CLEAR — no escapes detected; all diff work falls within the declared Scope Boundary.**

Phase 2 Scope Boundary in-scope capability strings:
- "AsaApi loader baked into image at pinned version"
- "ArkShop plugin baked into image at pinned version"
- "Permissions plugin baked into image (ArkShop dependency)"
- "Pinned plugin versions (rebuild-to-update)"

Checking diff against the boundary:
- `Dockerfile` bake block: `AsaApiLoader.exe` + AsaApi framework → "AsaApi loader baked into image at pinned version" ✓
- `Dockerfile` bake block: ArkShop DLL + plugin files at ARG-pinned version → "ArkShop plugin baked into image at pinned version" ✓
- `Dockerfile` bake block: Permissions DLL (bundled in AsaApi ZIP, `cp -r ArkApi` carries it) → "Permissions plugin baked into image (ArkShop dependency)" ✓
- ARG pins + versioned URLs → "Pinned plugin versions (rebuild-to-update)" ✓
- `entrypoint.sh` `deploy_plugins()`: deploys the image-baked content at boot — this is the necessary runtime complement to the bake-into-image capability, covered by the scope boundary's "baked into image" string (the deploy is inseparable from the bake being useful).

**Explicitly NOT delivered (deferred) boundary respected:**
- No `install_vcredist` (Phase 3) ✓
- No launcher flip / `ENABLE_ASAAPI` (Phase 4) ✓
- No ArkShop `config.json` injection (Phase 5) ✓

No work crosses into a ledger row owned by a different milestone. No symbols added that have no declared scope boundary match.

---

### Required Fixes (BLOCK summary)

None — all plan steps MET and scope respected.

---

### Bottom Line

Four surgical fixes, all landing exactly where the round-1 reviewers pointed — doc-pin comment on line 34, `.pdb` strip on line 53, durable reword on line 119, Decision Ledger row #12. No Phase 3/4/5 bleed, no silent creep, plan.md touched only at the one new row and the Phase 1 SHA checkbox. Plan adherence is clean. PASS.
