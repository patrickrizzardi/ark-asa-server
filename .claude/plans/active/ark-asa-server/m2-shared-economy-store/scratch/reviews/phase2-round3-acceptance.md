## Acceptance Verifier Report: m2-shared-economy-store Phase 2 Round 3

### Diff Scope
- Files changed: 2 (Dockerfile, entrypoint.sh)
- Lines added/removed: +109 / -0 (cumulative from Phase 1 SHA 21fe5a8; no lines removed since round 2)
- Diff source: `git diff 21fe5a8 -- Dockerfile entrypoint.sh` (working tree vs Phase 1 committed SHA)

### Round 3 Delta (what changed since Round 2 PASS)

Two comment-only changes since round 2:
1. **entrypoint.sh:66** — Big-O annotation added to `deploy_plugins()` docblock: `# Time: O(n)  Space: O(n) where n = plugin count (2-5 in practice)`. Complies with `comments.md` Hard Rule 7 (Tier 2+ functions must state Big-O). Zero functional impact.
2. **Dockerfile:34** — `PERMISSIONS_VERSION=1.1` doc-pin comment reworded: `"Records which Permissions version AsaApi 1.21 carries."` → `"Records which Permissions version the pinned AsaApi (ASAAPI_VERSION) carries."`. Replaces a hardcoded version reference with the ARG name, making the comment self-updating on future version bumps. Zero functional impact — the ARG itself is unchanged, and the comment still drives no download.

Neither change touches any logic, copy path, URL, version pin, or idempotency guard. All five AC subjects (image contents, boot-time deploy, idempotency, version-bump clean-replace, pinned-version recording) are structurally identical to round 2.

---

### Per-AC Audit (structured — coordinator parses this to write Evidence sub-bullets into plan file)

--- AC ENTRY ---
AC: "Image contains `/opt/asaapi/AsaApiLoader.exe` + `/opt/asaapi/ArkApi/Plugins/{ArkShop,Permissions}/` at pinned versions (verify in the built image)"
Verdict: MET
Evidence: Dockerfile:32-54 — `ARG ASAAPI_VERSION=1.21`; `ARG ARKSHOP_VERSION=1.4`; `curl -fsSL "https://ark-server-api.com/resources/asa-server-api.31/download?version=${ASAAPI_VERSION}"` → `cp -r /tmp/asaapi_src/ArkApi /opt/asaapi/` (carries `Plugins/Permissions/Permissions.dll`) + `cp /tmp/asaapi_src/AsaApiLoader.exe … /opt/asaapi/`; `curl -fsSL "…asa-arkshop.34/download?version=${ARKSHOP_VERSION}"` → `cp -r /tmp/arkshop_src/ArkShop/. /opt/asaapi/ArkApi/Plugins/ArkShop/`; `.pdb` strip; `chown -R container:container /opt/asaapi`. Coordinator pre-gate probe (notes.md §coordinator probes): live curl+unzip confirmed HTTP 200 / PK-ZIP magic / all six root files / `Permissions/Permissions.dll` + `ArkShop/ArkShop.dll` (DLL-name==folder-name). Round-3 delta: Dockerfile:34 comment reword is cosmetic — does not alter ARG default, download URL, or copy paths. AC1 subject unchanged.
Reason: The Dockerfile's `RUN` block unconditionally builds the `/opt/asaapi/` tree at the pinned ARG versions. The coordinator probe independently confirmed both download URLs are scriptable and return correct ZIP content with matching DLL/folder names. The round-3 comment reword on PERMISSIONS_VERSION tightens the doc-pin annotation but does not touch any functional line. AC1 is MET on the same evidence as round 2.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "After a boot, the volume's `…/Binaries/Win64/` contains `AsaApiLoader.exe` + `ArkApi/Plugins/{ArkShop,Permissions}/` with each plugin's DLL name matching its folder"
Verdict: MET
Evidence: entrypoint.sh:91 `cp -r "${src}/ArkApi" "${win64}/"` deploys the full `ArkApi/Plugins/` tree (Permissions + ArkShop with matching DLL/folder names); entrypoint.sh:94-99 `cp "${src}/AsaApiLoader.exe" … "${win64}/"` deploys the loader. `deploy_plugins()` called unconditionally from `main()` at entrypoint.sh:152 after `install_or_update`. Round-3 delta: entrypoint.sh:66 Big-O annotation is in the docblock comment section — does not touch copy paths, file list, or call site. AC2 subject unchanged.
Reason: The deploy function's copy operations are structurally identical to round 2. The Big-O annotation documents existing behavior; it introduces no new code path. DLL-name==folder-name is preserved by the `cp -r` of the image-baked tree (coordinator-probe-confirmed). Runtime boot receipt deferred to Phase 4 (dell) — same static-evidence ceiling as round 2.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "The deploy step is idempotent — a second boot re-syncs without error and without duplicating/clobbering game files"
Verdict: MET
Evidence: entrypoint.sh:82-88 `rm -rf` scoped exclusively to AsaApi-owned paths (listed explicitly; no game-owned paths); entrypoint.sh:91 `cp -r "${src}/ArkApi" "${win64}/"` (fresh copy each boot); entrypoint.sh:104-113 stash-restore loop no-ops on second boot when no operator-edited config.json exists (`[[ -f "${cfg}" ]] || continue` skip); `set -euo pipefail` (entrypoint.sh:6) aborts on any `rm`/`cp` error; `rm -rf` on absent paths is a safe no-op. Round-3 delta: Big-O annotation (entrypoint.sh:66) is in the leading comment block — zero impact on the idempotency logic at lines 82-122.
Reason: Clean-replace (rm-owned-then-cp-fresh) is inherently idempotent; N runs converge to the same state. Only AsaApi-owned paths in the `rm` list means game files are structurally excluded. The Big-O annotation adds documentation value but changes nothing about how the function executes on second boot.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "A version bump (changed `ASAAPI_VERSION`/plugin `ARG`) cleanly REPLACES the deployed tree — no stale files from the prior version remain in `ArkApi/`/loader paths"
Verdict: MET
Evidence: entrypoint.sh:82 `rm -rf "${win64}/ArkApi"` removes the entire `ArkApi/` subtree unconditionally; entrypoint.sh:83-88 root-level loader/DLLs individually listed in the same `rm -rf`; entrypoint.sh:91 `cp -r "${src}/ArkApi" "${win64}/"` places only what the new image carries. Dockerfile:36 `find /opt/asaapi -name '*.pdb' -delete` ensures the new image carries no `.pdb` blobs — so a version bump also cannot introduce stale debug symbols. Round-3 delta: Big-O annotation (entrypoint.sh:66) is in the comment block; Dockerfile:34 comment reword is on the doc-pin ARG. Neither touches the `rm -rf` block or the copy paths.
Reason: The remove-whole-ArkApi-then-copy idiom guarantees a clean slate. No file from a prior version's `ArkApi/` tree can survive because the entire directory is removed before the fresh copy. Stash-restore loop only restores operator `config.json` files, not binaries. Round-3 changes do not alter any line in this logic path.
--- END AC ENTRY ---

--- AC ENTRY ---
AC: "Pinned versions are recorded (Dockerfile `ARG`s + plan notes); no auto-latest fetch"
Verdict: MET
Evidence: Dockerfile:32 `ARG ASAAPI_VERSION=1.21`; Dockerfile:33 `ARG ARKSHOP_VERSION=1.4`; Dockerfile:36 URL uses `?version=${ASAAPI_VERSION}` (not `latest`); Dockerfile:48 URL uses `?version=${ARKSHOP_VERSION}` (not `latest`); Dockerfile:34 `ARG PERMISSIONS_VERSION=1.1` with updated doc-pin comment: "doc-pin only — Permissions ships bundled in the AsaApi zip; no separate download, no URL interpolation. Records which Permissions version the pinned AsaApi (ASAAPI_VERSION) carries." notes.md §distribution-channel records all three pinned versions + anti-latest rationale. Round-3 delta: the PERMISSIONS_VERSION doc-pin comment now references `ASAAPI_VERSION` instead of the hardcoded `1.21` — a strict improvement; the comment stays accurate on future version bumps without a manual edit. The two enforced download-gating ARGs and their `?version=${ARG}` URLs are unchanged.
Reason: All three versions are recorded. The two that drive downloads use versioned (not latest) URLs. The one that doesn't drive a download is annotated to explain exactly why — and the round-3 update makes that annotation self-maintaining. "No auto-latest fetch" is enforced structurally by the `?version=${ASAAPI_VERSION}` and `?version=${ARKSHOP_VERSION}` interpolations, which are identical to round 2. AC5 is MET and marginally stronger after the round-3 comment improvement.
--- END AC ENTRY ---

---

### Overall Verdict

OVERALL VERDICT: PASS — all 5 ACs MET; round-3 delta (2 comment-only changes) introduced zero regressions; AC5 evidence is marginally stronger after the PERMISSIONS_VERSION comment self-maintenance fix

---

### Required Fixes

None — all ACs MET.

---

### Bottom Line

Chief, two comment tweaks — a Big-O annotation and a self-referential doc-pin reword — and nothing moved under any AC. The five verdicts from round 2 carry forward without a scratch.
