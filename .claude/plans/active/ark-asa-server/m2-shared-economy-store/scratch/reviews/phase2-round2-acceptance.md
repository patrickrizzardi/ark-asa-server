## Acceptance Verifier Report: m2-shared-economy-store Phase 2 Round 2

### Diff Scope
- Files changed: 2 (Dockerfile, entrypoint.sh); plan.md + notes.md also changed but are churn/evidence, not subject-of-ACs
- Lines added/removed: +109 / -0 (net new; Phase 1 SHA 21fe5a8 is the base, Phase 2 work is uncommitted working tree)
- Diff source: `git diff 21fe5a8 -- Dockerfile entrypoint.sh` (coordinator-supplied command; working tree vs Phase 1 committed SHA)

### Round 2 Delta (what changed since Round 1 PASS)

Four gate-fixes applied between Round 1 and Round 2:
1. **Dockerfile:34** — `PERMISSIONS_VERSION=1.1` ARG gained a doc-pin inline comment clarifying it drives no download and records which Permissions version ships bundled in the AsaApi zip (rules-compliance fix).
2. **Dockerfile:53** — `find /opt/asaapi -name '*.pdb' -delete` added before `chown` to strip ~65MB of debug symbols from the image (code-reviewer fix).
3. **entrypoint.sh:119** — comment on the AsaApi framework `config.json` seed block reworded from a phase-ref ("Phase 5 leaves it") to a durable mechanism description ("never overwrite, so operator/injector edits survive restarts") (rules-compliance fix).
4. **plan.md Decision Ledger** — clean-replace-vs-rsync decision moved from notes.md to plan.md row #12 (deviation-judge fix). Notes.md trimmed correspondingly.

None of these four touch any AC's subject matter — they are a doc-pin annotation, a build-layer optimization, a comment rewording, and a plan-churn relocation. AC evidence analysis below confirms no regression.

---

### Per-AC Audit (structured — coordinator parses this to write Evidence sub-bullets into plan file)

--- AC ENTRY ---
AC: "Image contains `/opt/asaapi/AsaApiLoader.exe` + `/opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/` at pinned versions (verify in the built image)"
Verdict: MET
Evidence: Dockerfile:32-54 — `ARG ASAAPI_VERSION=1.21` + `ARG ARKSHOP_VERSION=1.4`; `curl -fsSL "…asa-server-api.31/download?version=${ASAAPI_VERSION}"` unpacked into `/opt/asaapi/` with `cp -r /tmp/asaapi_src/ArkApi /opt/asaapi/` (brings `ArkApi/Plugins/Permissions/Permissions.dll`); `curl -fsSL "…asa-arkshop.34/download?version=${ARKSHOP_VERSION}"` unpacked with `cp -r /tmp/arkshop_src/ArkShop/. /opt/asaapi/ArkApi/Plugins/ArkShop/`; `cp /tmp/asaapi_src/AsaApiLoader.exe … /opt/asaapi/`; `chown -R container:container /opt/asaapi`. Coordinator pre-gate probe (notes.md Phase-2 probes) confirmed both URLs return HTTP 200 application/octet-stream ZIP with magic PK, `unzip -l` OK, and DLL-name==folder-name holds (`Permissions/Permissions.dll`, `ArkShop/ArkShop.dll`). Round-2 delta: `.pdb` strip (Dockerfile:53) removes debug symbols from `/opt/asaapi` before `chown` — does NOT remove any DLL or the loader. The tree structure and pinned-version bake are unchanged from Round 1.
Reason: The Dockerfile unconditionally builds `/opt/asaapi/AsaApiLoader.exe`, `/opt/asaapi/ArkApi/Plugins/Permissions/` (from AsaApi zip), and `/opt/asaapi/ArkApi/Plugins/ArkShop/` (from ArkShop zip) at the pinned ARG versions. The coordinator's live URL probe (notes.md) independently confirmed the URLs are scriptable and return the correct ZIP content. The round-2 `.pdb` strip is a build-layer improvement that touches no runtime binary — AC1's subject is unaffected.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "After a boot, the volume's `…/Binaries/Win64/` contains `AsaApiLoader.exe` + `ArkApi/Plugins/{ArkShop,Permissions}/` with each plugin's DLL name matching its folder"
Verdict: MET
Evidence: entrypoint.sh:55-126 `deploy_plugins()` function; specifically: `cp -r "${src}/ArkApi" "${win64}/"` (line 94) deploys `ArkApi/Plugins/Permissions/Permissions.dll` and `ArkApi/Plugins/ArkShop/ArkShop.dll`; `cp "${src}/AsaApiLoader.exe" … "${win64}/"` (lines 97-102) deploys the loader. The image-baked `/opt/asaapi` tree has folder-name==DLL-name (confirmed by coordinator probe above). `deploy_plugins()` is called unconditionally from `main()` at entrypoint.sh:153, after `install_or_update`. Round-2 delta: entrypoint.sh:119 comment reword is cosmetic — the seed-if-absent logic at lines 120-123 is identical to Round 1. No change to the copy paths or file list.
Reason: The deploy function copies the full `ArkApi/` subtree (which carries both plugin dirs) plus `AsaApiLoader.exe` to `Win64/` on every boot. The DLL-name==folder-name constraint was validated by the coordinator probe on the live ZIP content, and the Dockerfile preserves the folder structure verbatim via `cp -r`. The round-2 delta does not touch any of these copy operations.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "The deploy step is idempotent — a second boot re-syncs without error and without duplicating/clobbering game files"
Verdict: MET
Evidence: entrypoint.sh:85-91 — `rm -rf` removes only the explicitly named AsaApi-owned paths (`${win64}/ArkApi`, `${win64}/AsaApiLoader.exe`, `${win64}/AsaApiLoader.pdb`, `${win64}/msdia140.dll`, `${win64}/libcrypto-3-x64.dll`, `${win64}/libssl-3-x64.dll`, `${win64}/msvcp140.dll`) before the fresh `cp`; no other Win64 contents touched. Config stash/restore loop (lines 74-116) is a no-op on second boot when no operator-edited config.json exists yet (glob matches nothing → `[[ -f "${cfg}" ]] || continue` skips). `set -euo pipefail` (entrypoint.sh:6) means a failed `rm` or `cp` aborts rather than continuing silently. `rm -rf` on paths that already don't exist (second and subsequent boots after a version bump removed them) is a safe no-op. Round-2 delta: none affecting idempotency — the `.pdb` strip is a build-time step; the comment reword at line 119 is cosmetic.
Reason: The clean-replace strategy (`rm`-owned-paths then `cp` fresh) is inherently idempotent: running it N times converges to the same state. Only AsaApi-owned paths are in the `rm` list; game-owned files in Win64 are never referenced. The `cfg_stash` pattern stashes-then-restores operator configs so they survive every re-sync. No duplicating, no clobbering, no error on re-run.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "A version bump (changed `ASAAPI_VERSION`/plugin `ARG`) cleanly REPLACES the deployed tree — no stale files from the prior version remain in `ArkApi/`/loader paths"
Verdict: MET
Evidence: entrypoint.sh:85-91 `rm -rf "${win64}/ArkApi"` removes the entire `ArkApi/` subtree unconditionally before copying the fresh tree from the new image. Loader-path files listed explicitly in the same `rm -rf` block. The fresh `cp -r "${src}/ArkApi" "${win64}/"` (line 94) then places only what the new image carries. Because the whole `ArkApi/` dir is removed first, no file from a prior version can survive. Round-2 delta: none affecting this — the `.pdb` strip means the new image's `ArkApi/` contains no `.pdb` files, so the deployed tree on the volume will also be `.pdb`-free after a version bump. This is a strict improvement to the AC's "no stale files" promise (`.pdb` blobs from prior versions won't linger either).
Reason: The remove-then-copy idiom (Decision Ledger row #12) guarantees a clean slate for `ArkApi/` and the explicitly listed loader binaries. Any file present in a prior version's `ArkApi/` tree that is absent from the new version's tree is eliminated by the `rm -rf`. The stash-restore loop preserves only operator config.json files (not binaries), so it cannot reintroduce stale binaries.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "Pinned versions are recorded (Dockerfile `ARG`s + plan notes); no auto-latest fetch"
Verdict: MET
Evidence: Dockerfile:32-33 — `ARG ASAAPI_VERSION=1.21` and `ARG ARKSHOP_VERSION=1.4` are explicit default-pinned ARGs. Dockerfile:36 — URL is `?version=${ASAAPI_VERSION}` (not `?version=latest`). Dockerfile:48 — URL is `?version=${ARKSHOP_VERSION}` (not `?version=latest`). Dockerfile:34 — `ARG PERMISSIONS_VERSION=1.1` with inline doc-pin comment: "doc-pin only — Permissions ships bundled in the AsaApi zip; no separate download, no URL interpolation. Records which Permissions version AsaApi 1.21 carries." notes.md (Phase 2 distribution channel section and decisions section) records all three pinned versions, the URL patterns, and the Permissions bundling rationale. Round-2 delta: this is the AC the coordinator asked to specifically re-verify. The round-2 fix *adds* the doc-pin comment to PERMISSIONS_VERSION clarifying it drives no download. This does NOT weaken AC5 — the two enforced pins (ASAAPI_VERSION, ARKSHOP_VERSION) still gate their downloads via `?version=${ARG}`. PERMISSIONS_VERSION was always a documentation pin; the comment now makes that explicit rather than leaving it as a silent dead ARG. The AC says "pinned versions are recorded … no auto-latest fetch." All three versions are recorded. The two that drive downloads use versioned URLs. The one that doesn't drive a download is annotated to explain exactly why. The no-auto-latest guarantee is enforced by the `?version=${ASAAPI_VERSION}` and `?version=${ARKSHOP_VERSION}` URL interpolations, which have not changed.
Reason: Both download-driving ARGs resolve to versioned (not latest) URLs. PERMISSIONS_VERSION is explicitly documented as a doc-pin with no URL role — this is MORE evidence, not less, that the three pinned versions are recorded with full fidelity. The round-2 comment addition strengthens the paper trail for AC5 by surfacing a subtle implementation fact that was previously only in notes.md.
--- END AC ENTRY ---

---

### Overall Verdict

OVERALL VERDICT: PASS — all 5 ACs MET; round-2 delta introduced no regressions; PERMISSIONS_VERSION doc-pin comment strengthens AC5 rather than weakening it

---

### Required Fixes

None — all ACs MET.

---

### Bottom Line

Chief, all five ACs survived the round-2 delta without a scratch. The `.pdb` strip is a strict improvement on AC4 ("no stale files" now includes debug symbols), and the PERMISSIONS_VERSION doc-pin comment makes AC5's evidence cleaner, not murkier. The two enforced download-gating ARGs still use `?version=${ARG}` URLs. Nothing regressed.
