# Deviation Judge — Full Report
## Plan: ark-asa-server / m2-shared-economy-store | Phase 5 | Deviation #5

---

## Deviation Judge: m2-shared-economy-store Phase 5 Deviation #5

### Verdict: PASS

### Deviation summary (one line)
Executor chose `./plugins-config/` (separate host dir) over reusing `./config/` for plugin config.json bind-mounts, and implemented it via a `setup_plugin_configs()` function that seeds then replaces each plugin dir with a symlink to the host bind.

### Adversarial input(s) constructed

1. **Warm boot with symlink already in place**: Second (and subsequent) boots where `ArkApi/Plugins/ArkShop` is already a symlink from the prior run — specifically: does `deploy_plugins()`'s stash/rm-rf/cp/restore sequence handle a symlink-as-plugin-dir correctly without corrupting the host bind at `./plugins-config/ArkShop/`?

2. **Empty host dir + absent image default**: `./plugins-config/ArkShop/` exists (Docker bind created it) but contains no `config.json`, AND `ArkApi/Plugins/ArkShop/config.json` is also absent in the deployed image — seed guard fires false, symlink still created, `inject_plugin_db_config()` hits the "config.json not found" FATAL. This probes whether the fail-fast guard correctly catches the "no config anywhere" degenerate case rather than silently proceeding with a misconfigured ArkShop.

3. **Third plugin in ArkApi tree (e.g. ASAUtils) not in the `for plugin in ArkShop Permissions` loop**: `setup_plugin_configs()` hardcodes the loop to those two plugins. A third plugin dir exists as a real dir. Does this interfere with `deploy_plugins()`'s stash/restore for that dir?

4. **Round-trip: operator-edited + db-injected config survives `deploy_plugins()` on next boot**: `host_dir/config.json` has operator edits (e.g., point values, shop categories) AND db creds injected by `inject_plugin_db_config()`. On next boot `deploy_plugins()` stash-globs through the symlink, finds the file, stashes it, rm-rf's ArkApi (symlink removed, host dir untouched), cp fresh ArkApi, restores stash to new real dir. Then `setup_plugin_configs()` runs: `host_dir/config.json` exists → seed skipped. `rm -rf` real plugin dir. `ln -sfn host_dir plugin_dir`. `inject_plugin_db_config()` re-injects through symlink into host dir. Does operator content survive?

### Trace

#### Input 1: Warm-boot symlink-already-in-place trace

**Setup**: Prior boot left `${win64}/ArkApi/Plugins/ArkShop` as a symlink → `/home/container/plugins-config/ArkShop/` (host bind).

**Step 1**: `deploy_plugins()` fires at `entrypoint.sh:399`.

**Step 2**: `entrypoint.sh:93-99` — stash loop: `for cfg in "${win64}/ArkApi/Plugins"/*/config.json`. Shell glob traversal follows symlinks, so `ArkShop → host_dir` resolves and finds `host_dir/config.json`. It's stashed at `cfg_stash/ArkShop_config.json`.

**Step 3**: `entrypoint.sh:104` — `rm -rf "${win64}/ArkApi"`. This removes the entire `ArkApi/` directory tree. The symlink `ArkShop` is inside `ArkApi/Plugins/`, so it gets removed as a symlink entry — `rm -rf` on a directory removes symlinks as file entries, does NOT follow them and does NOT delete the symlink target. Host dir `./plugins-config/ArkShop/` is untouched.

**Step 4**: `entrypoint.sh:113` — `cp -r "${src}/ArkApi" "${win64}/"`. Fresh real directories created, including `ArkApi/Plugins/ArkShop/` (real dir, image-default config.json inside).

**Step 5**: `entrypoint.sh:126-135` — stash restore: `ArkShop_config.json` restored to `win64/ArkApi/Plugins/ArkShop/config.json` (real dir now holds the host's content).

**Step 6**: `entrypoint.sh:403` — `setup_plugin_configs()` runs. `host_dir/config.json` exists → seed guard `[[ ! -f "${host_dir}/config.json" ]]` is false → seed skipped. `rm -rf "${plugin_dir}"` removes the real ArkShop dir (harmless, host config is safe). `ln -sfn "${host_dir}" "${plugin_dir}"` re-establishes symlink.

**Step 7**: `entrypoint.sh:404` — `inject_plugin_db_config()`. Resolves `arkshop_cfg` through symlink to `host_dir/config.json`. jq mutates host file in place.

**Result**: Host config survives every warm boot. No corruption. The stash-restore into the real dir in Step 5 is wasted work but harmless — it's immediately overwritten by the symlink re-establishment in Step 6, and only the host copy matters. PASS.

#### Input 2: Empty host dir + absent image default

**Setup**: `./plugins-config/ArkShop/` mounted but empty. Image ArkShop plugin somehow has no `config.json` (or deploy failed).

**Trace**: seed guard: `[[ ! -f "${host_dir}/config.json" && -f "${plugin_dir}/config.json" ]]` → second condition false → seed skipped. Symlink created. `inject_plugin_db_config()` at line 320: `[[ ! -f "${arkshop_cfg}" ]]` → resolves through symlink → file absent → FATAL exit with explicit message. Correct behavior — loud failure rather than silent misconfiguration. PASS.

#### Input 3: Third plugin (ASAUtils) not in hardcoded loop

**Trace**: `setup_plugin_configs()` loops only `ArkShop Permissions`. `ASAUtils` real dir in `ArkApi/Plugins/ASAUtils/` is never touched by `setup_plugin_configs()`. `deploy_plugins()` on next boot stash-globs `ArkApi/Plugins/*/config.json` — if `ASAUtils` is a real dir with a config.json, it gets stashed and restored normally. No cross-contamination. PASS.

#### Input 4: Round-trip — operator edits + db credentials survive next boot

**Trace**: `host_dir/config.json` contains ArkShop items + db creds from `inject_plugin_db_config()`. On next boot: `deploy_plugins()` stash copies host content (Step 2 above), rm-rf removes symlink (Step 3), cp creates real dir with image default (Step 4), stash restore writes host content back to real dir (Step 5). `setup_plugin_configs()`: seed skipped (host file exists), symlink re-established. `inject_plugin_db_config()` re-writes creds through symlink — jq `.Mysql.*` fields overwritten with env values, but `.Mysql` fields were already injected-identical on prior boots (env is constant per container lifecycle). Non-MySQL operator content (shop items, pricing) is preserved because jq only mutates the `.Mysql.*` keys. PASS.

### Where the fix overshoots (BLOCK only)
N/A — verdict is PASS.

### Strategies attempted

- **Mixed inputs**: Probed the "symlink already in place + deploy_plugins runs first" scenario (Input 1). The `rm -rf "${win64}/ArkApi"` removes the symlink entry without following it; host dir survives. The stash glob traverses through the symlink and correctly stashes host content for restore. No break.

- **Trace-through**: Full execution trace through the 4-call sequence `deploy_plugins → setup_plugin_configs → inject_plugin_db_config` with each adversarial input. Confirmed call order from `entrypoint.sh:398-404`. Key invariant holds: `deploy_plugins()` always ends with real dirs; `setup_plugin_configs()` always ends with symlinks pointing to host bind; `inject_plugin_db_config()` always writes through the symlink to the host bind. The round-trip is clean regardless of boot number.

- **Boundary inputs**: Empty host dir (Input 2) — correctly caught by `inject_plugin_db_config()`'s FATAL guard. Third plugin not in loop (Input 3) — isolated from the mechanism; no interference.

- **Round-trip / serialization**: Operator-edited + db-injected config.json across two boot cycles (Input 4). The stash mechanism in `deploy_plugins()` correctly traverses the symlink and round-trips the host content. `inject_plugin_db_config()`'s jq write is scoped to `.Mysql.*` keys only, preserving operator content. Idempotent across arbitrary boots.

- **Existing-primitive check**: Searched for an existing `./config/` symlink-setup function to see if the executor should have reused it. `entrypoint.sh:387-388` sets up the engine config symlink with `ln -sfn /home/container/config "$config_link"`. That primitive only handles one flat dir; `setup_plugin_configs()` handles N named subdirs with seed-if-absent logic. The more elaborate primitive is justified by the different concern (multiple named plugin dirs vs one engine config dir). No narrower existing primitive found that would have served.

- **Second-caller check**: Only callers of `setup_plugin_configs()` are within `main()` under the `ENABLE_ASAAPI=1` guard. No other caller exists or is implied. PASS.

### Bottom Line
Chief, I tried the warm-boot symlink scenario (the one the orchestrator flagged as the kill-shot candidate), and `rm -rf "${win64}/ArkApi"` correctly eats the symlink without following it — host dir untouched, round-trip clean across every boot. The separate `./plugins-config/` dir is the right call and the implementation holds up.

---

*Strategies: mixed-inputs, trace-through, boundary-inputs, round-trip/serialization, existing-primitive check, second-caller check. Six strategies attempted, zero breaks found.*
