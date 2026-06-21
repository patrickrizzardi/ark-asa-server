# Deviation Judge: m2-shared-economy-store Phase 2 Deviation #1 (Round 2)

## Deviation Judge: m2-shared-economy-store Phase 2 Deviation #1

### Verdict: PASS

### Deviation summary (one line)
`deploy_plugins()` uses stash → explicit `rm -rf` of named AsaApi-owned paths → `cp -r` fresh from `/opt/asaapi` → restore, instead of `rsync --delete`.

### Round-2 change confirmation
The round-2 diff against base commit 21fe5a8 shows ALL lines in `deploy_plugins()` are additions (`+`). There are no deletion (`-`) lines anywhere in the function. The comment at entrypoint.sh:119 reads:
```
  # Seed the AsaApi framework config.json only if absent — never overwrite, so operator/injector edits survive restarts.
```
The logic block immediately following (`if [[ ! -f "${asaapi_cfg}" ]]; then cp "${src}/config.json" "${asaapi_cfg}"; fi`) is identical. Round-2 change is confirmed comment-only; stash/rm/cp logic is unchanged.

### Adversarial input(s) constructed

1. **Root-level DLL with future-version new filename not on the rm list**: AsaApi ships a new root-level DLL in a future version (e.g., `libssl-3-x64-1.dll`) not named in the `rm -rf` list at entrypoint.sh:85-91. First deploy of new image: `cp` drops it into `${win64}/`. Next version bump image: rm list doesn't include the old `libssl-3-x64-1.dll` — stale lingers.

2. **Plugin with underscore in folder name**: plugin named `My_Plugin` stashes as `My_Plugin_config.json`; restore strips `_config.json` suffix via `${plugin_name%_config.json}` → recovers `My_Plugin` correctly. Targeted at the stash-naming collision.

3. **First-boot-absent config.json (win64/ArkApi/Plugins missing entirely)**: stash guard `[[ -d "${win64}/ArkApi/Plugins" ]]` is false → stash skips → rm -rf of absent ArkApi dir is no-op → cp -r drops fresh tree → restore glob `${cfg_stash}/*_config.json` matches nothing → `[[ -f "${stashed}" ]] || continue` exits → seed-if-absent for `${win64}/config.json` fires: absent → cp from src → correct.

4. **Game file named identically to an AsaApi-owned DLL**: impossible — the rm list names specific AsaApi DLLs; the cp list copies only from `/opt/asaapi/`; no game-owned file in `${win64}/` is touched unless it appears on the explicit rm list. `ArkAscendedServer.exe` is not on the rm list. Structural impossibility.

### Trace

**Adversarial input #1** (strongest candidate — traced in full):

- Image rebuilt for AsaApi v1.21 (current pinned): `/opt/asaapi/` contains `ArkApi/`, `AsaApiLoader.exe`, `AsaApiLoader.pdb` (none), `msdia140.dll`, `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `msvcp140.dll`, `config.json`.
- `rm -rf` list (entrypoint.sh:85-91) covers exactly these filenames. Deploy is correct for v1.21.
- **Version bump to hypothetical v1.22**: image adds `libssl-3-x64-1.dll` to `/opt/asaapi/`. Rebuild + redeploy:
  - rm list (still hardcoded) does NOT include `libssl-3-x64-1.dll`.
  - cp drops `libssl-3-x64-1.dll` into `${win64}/`.
  - All good on first v1.22 deploy.
- **Version bump to v1.23**: v1.22 dropped `libssl-3-x64-1.dll` from its dist. Rebuild + redeploy:
  - rm list STILL doesn't include `libssl-3-x64-1.dll` (it was never on the list).
  - cp doesn't drop `libssl-3-x64-1.dll` (not in v1.23 `/opt/asaapi/`).
  - `libssl-3-x64-1.dll` from v1.22 remains in `${win64}/`.
  - **Stale file from prior version lingers** — the stated guarantee is violated.

**Why this doesn't trigger BLOCK:**

The adversarial mandate is to find where the fix is **WIDER** than the stated problem. This input shows the fix is **narrower** than the stated guarantee for future versions — it undershoots, it doesn't overshoot. No behavior today (v1.21 pinned, rebuild-to-update policy) is broken. The gap is a future maintenance risk, not a current overshoot.

For the overshoot question specifically: does `rm -rf "${win64}/ArkApi"` do MORE damage than `rsync --delete` scoped to ArkApi? No — rsync --delete would also remove operator-installed manual files in ArkApi/ not tracked by /opt/asaapi/ArkApi/. The behaviors are equivalent. The stash/restore for config.json is actually SAFER than a naive rsync (rsync --delete would overwrite operator configs; stash preserves them).

**Adversarial input #2** trace (entrypoint.sh:107-115):

Plugin folder `My_Plugin` → `cfg="${win64}/ArkApi/Plugins/My_Plugin/config.json"` → `plugin_name=$(basename "$(dirname "${cfg}")")` = `My_Plugin` → stash as `${cfg_stash}/My_Plugin_config.json`. Restore: `stashed="${cfg_stash}/My_Plugin_config.json"` → `plugin_name="${stashed##*/}"` = `My_Plugin_config.json` → `plugin_name="${plugin_name%_config.json}"` = `My_Plugin` (bash `%` strips shortest suffix match; `_config.json` literal = exactly one occurrence; `My_Plugin_config.json` - `_config.json` = `My_Plugin`). Plugin dir `${win64}/ArkApi/Plugins/My_Plugin` exists after cp-r → config restored correctly. No break.

**Adversarial input #3** trace: fully correct per stash-guard + seed-if-absent logic described above.

### Where the fix overshoots (BLOCK only)

N/A — no overshoot found across all adversarial inputs. The fix is accurate for the stated problem scope (v1.21 pinned, POSIX-builtins-only). The undershooting gap (root-level DLL rm list is static) is a future maintenance concern, not a current behavioral overshoot.

### Strategies attempted

- **Mixed inputs**: Stash + restore for a plugin that doesn't exist on the new image (e.g., a plugin was removed between versions). Restore loop at entrypoint.sh:113: `if [[ -d "${win64}/ArkApi/Plugins/${plugin_name}" ]]` guards the restore — if the new image's cp -r didn't include that plugin dir, the guard is FALSE and the stale config is NOT restored (it's cleaned with the stash via `rm -rf "${cfg_stash}"`). Correct: removed-plugin config is not restored. No break.

- **Boundary inputs**: First-boot-absent (no ArkApi/Plugins dir at all) — traced in full above. Correct. Zero plugins (ArkApi/Plugins exists but empty) — stash glob `${win64}/ArkApi/Plugins/*/config.json` matches nothing; `[[ -f "${cfg}" ]] || continue` handles empty glob gracefully under `set -euo pipefail` (bash expands to the literal glob string when no match; `-f` check on the literal fails; continue fires). No break.

- **Existing-primitive check**: Searched for an rsync invocation or a dynamic file-list approach in the codebase. `grep -r rsync entrypoint.sh Dockerfile` → zero hits. No existing primitive that does rsync-equivalent. The narrower fix for root-level completeness would be dynamic: `find "${src}" -maxdepth 1 -type f | xargs -I{} basename {} | xargs -I{} rm -f "${win64}/{}"` before the explicit cp — this removes whatever was previously deployed that the image no longer ships. However this only covers files present in the new image; a file present in v1.21 but absent in v1.22 AND also absent from the rm list would still not be removed. The ONLY full-fidelity rsync --delete equivalent for root-level files requires knowing what the PRIOR image deployed, which neither rm-list nor dynamic-find provides without a manifest. The ArkApi tree is fully covered by rm -rf; the root-level DLL gap is real but bounded.

- **Second-caller check**: N/A — `deploy_plugins()` is called once (entrypoint.sh:153, inside `main()`). No second caller exists or is plausible given the entrypoint architecture.

- **Trace-through**: Traced v1.21 first boot, v1.21 warm boot (idempotent: rm removes same files, cp overwrites with same content — correct), and hypothetical v1.22 version-bump boot. All paths correct for current scope.

- **Round-trip / serialization**: The stash uses flat naming `${plugin_name}_config.json` in a tmp dir, not a path hierarchy. Round-trip: plugin name → stash filename → restore plugin name via suffix strip. Verified correct for single-word and underscore-containing names. JSON config content is not inspected or modified — raw `cp`. No mutation. Round-trip fidelity: exact.

### Bottom Line

The round-2 change is comment-only — confirmed cold from the diff, zero logic lines modified. The stash/rm/cp logic is sound for the pinned v1.21 scope; the rm list undershoot for future new root-level DLLs is a maintenance note, not an overshoot, and not a current break.
