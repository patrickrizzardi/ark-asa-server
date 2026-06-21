# Deviation Judge — Phase 5, Round 3, Deviation #5
# Plan: m2-shared-economy-store
# Deviation type: approach

## Verdict: PASS

---

## Deviation Summary

Instead of bind-mounting the entire plugin directory to a host path (which deleted plugin DLLs),
the fix symlinks ONLY `config.json` (the file) into the deployed plugin dir, leaving the DLL
intact. A separate `./plugins-config/` host dir provides the operator-editable surface. The
`_inject_mysql_block` function resolves the symlink with `readlink -f` before `mv`-ing the jq
output to avoid replacing the symlink with a regular file.

---

## Adversarial Inputs Constructed

1. **Warm boot where `config.json` is already a symlink** — `deploy_plugins()` clean-replace runs
   first; does it stash the symlink's content correctly, then does `setup_plugin_configs()` restore
   the symlink without stomping the operator-edited host file?

2. **Cross-device `mv` in `_inject_mysql_block`** — `mktemp` produces `/tmp/tmp.XXXXX` (container
   overlay/tmpfs); `dest` resolves via `readlink -f` to
   `/home/container/plugins-config/ArkShop/config.json` (host bind mount, different filesystem).
   Does `mv` across device boundaries fail with EXDEV, and if so does it leave an empty or
   partially-written file at `dest`?

3. **Operator deletes host `config.json` between boots** — `./plugins-config/ArkShop/config.json`
   absent when boot N+1 starts. Does the sequence leave a dangling symlink, skip the seed, or crash
   gracefully?

4. **Plugin with NO default `config.json` in the image** — `plugin_dir/config.json` doesn't exist
   after `deploy_plugins()`. Does `setup_plugin_configs()` create a dangling symlink to a
   non-existent host file?

---

## Traces

### Input 1 — Warm boot, existing symlink

Boot N left `ArkShop/config.json` as a symlink → `/home/container/plugins-config/ArkShop/config.json`.

**deploy_plugins() on boot N+1:**

Line 95: `for cfg in "${win64}/ArkApi/Plugins"/*/config.json` — glob resolves the symlink path as
a filesystem entry. The symlink IS enumerated.

Line 96: `[[ -f "${cfg}" ]]` — `-f` follows symlinks. Host file exists → TRUE. Stash proceeds.

Line 99: `cp "${cfg}" "${cfg_stash}/${plugin_name}_config.json"` — `cp` follows the symlink,
reads the host file's content, writes it to the stash. The operator-edited config (including any
injected DB creds from the prior boot) is stashed correctly.

Line 105: `rm -rf "${win64}/ArkApi"` — removes the plugin dir including the symlink. The host
file at `plugins-config/ArkShop/config.json` is NOT removed (it is not inside `ArkApi/`).

Line 114: `cp -r "${src}/ArkApi" "${win64}/"` — fresh real `config.json` placed at
`ArkApi/Plugins/ArkShop/config.json`.

Line 134: `cp "${stashed}" "${target}"` — stashed operator content overwritten onto the real
file. Operator's config restored.

**setup_plugin_configs():**

Line 290: `[[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` — host file
IS present (operator's content still there from prior boots, untouched by rm-rf since it's on the
bind mount). Condition FALSE → seed step skipped. Correct — operator edit preserved.

Line 296: `ln -sfn "${host_dir}/config.json" "${plugin_dir}/config.json"` — replaces the
restored real file with the symlink again. `ln -sfn` (force) handles the existing real file.

**inject_plugin_db_config() / _inject_mysql_block:**

Line 321: `[[ -L "${cfg}" ]] && dest="$(readlink -f "${cfg}")"` — cfg is now a symlink →
resolves to `/home/container/plugins-config/ArkShop/config.json`.

Line 323: `tmp="$(mktemp)"` — `/tmp/tmp.XXXXX`.

Line 335: `jq ... "${cfg}" > "${tmp}"` — reads through symlink (host file content). Writes to
tmp. OK.

Line 336: `mv "${tmp}" "${dest}"` — `/tmp/tmp.XXXXX` → `/home/container/plugins-config/ArkShop/config.json`.

**Cross-device mv analysis:** `/tmp` is the container's tmpfs. `/home/container/plugins-config/`
is a bind mount from the host filesystem (ext4 or NTFS via WSL2 drvfs). These ARE different
devices. `mv` on Linux: POSIX `rename(2)` returns `EXDEV` for cross-device moves; the `mv` utility
detects this and falls back to `cp` + `unlink` (copy contents then remove source). This is
STANDARD POSIX mv behavior — it does NOT fail. The file at `dest` is overwritten atomically
enough for this use case (not transactional, but the `tmp` is fully written before `mv` is
called). The symlink at `plugin_dir/config.json` is unaffected — only the real file at `dest`
was written to.

Result: warm boot path is clean. DLL unaffected. Symlink re-established. Operator config preserved
and DB creds re-injected.

---

### Input 2 — Cross-device mv (traced within Input 1 above)

`mv /tmp/tmp.XXXXX /home/container/plugins-config/ArkShop/config.json` across device boundary:

- Linux `mv` falls back to copy+unlink on EXDEV.
- `tmp` is fully written (jq success already confirmed by the `||` guard at line 335).
- `dest` is the REAL file (resolved via `readlink -f`), not the symlink.
- The symlink at `plugin_dir/config.json` continues to point at `dest` uninterrupted.
- No data loss, no symlink replacement, no partial write.

**PASS.**

---

### Input 3 — Operator deletes host config.json between boots

State: `./plugins-config/ArkShop/config.json` deleted on host before boot N+1.

**deploy_plugins():**

Line 96: `[[ -f "${cfg}" ]]` on the symlink where the target is deleted → `-f` follows symlinks;
dangling symlink returns FALSE. Stash loop skips this plugin. Correct.

`rm -rf "${win64}/ArkApi"` removes the dangling symlink too.

Fresh copy from image places real `config.json` in plugin dir.

Stash restore: nothing to restore for ArkShop. Image default survives.

**setup_plugin_configs():**

Line 290: `[[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` — host file
ABSENT (operator deleted it), plugin_dir/config.json is a REAL file from image copy → both sides
TRUE → seed executes. `cp plugin_dir/config.json host_dir/config.json`. Host file re-created from
image default.

Line 296: `ln -sfn` — symlink re-established to the newly-seeded host file. No dangling link.

**inject_plugin_db_config():** Config exists (host was just re-seeded). DB creds injected. Clean
boot.

**PASS.**

---

### Input 4 — Plugin with NO default config.json in the image

State: `/opt/asaapi/ArkApi/Plugins/ArkShop/` exists (DLL present) but has no `config.json`.
After `deploy_plugins()`, `plugin_dir/config.json` does not exist.

**setup_plugin_configs():**

Line 283: `[[ ! -d "${plugin_dir}" ]]` — the plugin_dir itself exists (it has the DLL). Condition
FALSE → does NOT skip.

Line 290: `[[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` — host file
absent AND `plugin_dir/config.json` absent → second condition FALSE → seed skipped.

Line 296: `ln -sfn "${host_dir}/config.json" "${plugin_dir}/config.json"` — creates a symlink
pointing to a file that does NOT exist on the host. DANGLING SYMLINK created.

**inject_plugin_db_config():**

Line 374: `if [[ ! -f "${arkshop_cfg}" ]]` — `-f` on dangling symlink returns FALSE → "FATAL:
ArkShop config.json not found" → `exit 1`.

Container crashes with a clear error message. The DLL is untouched. No silent data loss.

**Assessment:** The dangling symlink is created but is immediately caught by the fail-fast guard in
`inject_plugin_db_config()`. The container does not continue with a missing config. However, this
scenario CANNOT occur in practice in this codebase: the image bakes `config.json` alongside every
plugin DLL in `/opt/asaapi/ArkApi/Plugins/*/`, so `plugin_dir/config.json` is always present
after `deploy_plugins()`. The scenario requires a broken image build where a plugin DLL was added
without its config.json — that's a Dockerfile defect, not a runtime path. The fail-fast at inject
time provides a safety net even if it occurs.

**PASS** — dangling symlink is transient and immediately detected by the existing fail-fast gate.

---

## Strategies Attempted

**Mixed inputs:** Attempted "warm boot where config.json is ALREADY a symlink" — the stash loop's
`-f` test follows symlinks correctly, so the operator-edited content is stashed and restored
without the symlink semantics leaking into the stash. No break.

**Boundary inputs:** Attempted "no default config.json in the image" (the plugin exists but has no
config to seed from). Creates a transient dangling symlink that is caught by the fail-fast guard in
`inject_plugin_db_config()` before the server starts. The DLL is never at risk. No silent break.

**Existing-primitive check:** Searched for any alternate `readlink`, `realpath`, or symlink
resolution pattern in the codebase — only one resolution site exists, in `_inject_mysql_block`
line 321. No parallel implementation.

**Round-trip / serialization:** Traced the full jq-write → tmp → mv → dest cycle across the
cross-device filesystem boundary (container tmpfs → host bind mount). `mv` falls back to
copy+unlink on EXDEV per POSIX; the symlink at `plugin_dir/config.json` is unaffected. DB creds
written to the real host file correctly on every boot.

**Second-caller check:** `_inject_mysql_block` is called by `inject_plugin_db_config()` for both
ArkShop and (conditionally) Permissions. The Permissions call passes a path that is also
potentially a symlink after `setup_plugin_configs()`. The same `readlink -f` resolution at line
321 applies to both callers — no asymmetry. Both work correctly.

**Trace-through:** Walked all four inputs through the full boot sequence
(deploy_plugins → setup_plugin_configs → inject_plugin_db_config). All paths either succeed
cleanly or fail fast with a clear error before the server starts. No path leaves the DLL at risk
or writes creds to the wrong file.

---

## Bottom Line

The stash-and-restore in `deploy_plugins()` handles the symlink correctly on warm boot because
`-f` follows links and `cp` follows links; the symlink is just a deployment artifact that
disappears in the rm-rf and gets re-created post-deploy. The cross-device `mv` is POSIX-handled.
Chief, this one's tight — PASS across all six probes.
