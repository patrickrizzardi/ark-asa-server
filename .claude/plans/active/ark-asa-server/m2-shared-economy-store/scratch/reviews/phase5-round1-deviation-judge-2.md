# Deviation Judge — ark-asa-server m2-shared-economy-store Phase 5 Deviation #2

## Deviation Judge: ark-asa-server / m2-shared-economy-store Phase 5 Deviation #2

### Verdict: PASS

### Deviation summary (one line)
Added `plugins-config/**` + `!plugins-config/.gitkeep` to `.gitignore` to prevent runtime-injected DB credentials from being accidentally committed by operators.

### Adversarial input(s) constructed

1. **Mixed input — Permissions plugin also injects credentials**: `plugins-config/Permissions/config.json` is a second credential-bearing file written by `inject_plugin_db_config()` (entrypoint.sh:351-368), not mentioned in the rationale (which only names ArkShop). Does `plugins-config/**` catch it?
   - Empirical: `git check-ignore -v "plugins-config/ArkShop/config.json"` → `.gitignore:1:plugins-config/**  plugins-config/ArkShop/config.json`. Pattern is confirmed to match nested subdirs at any depth. Both `ArkShop/config.json` and `Permissions/config.json` are suppressed. PASS.

2. **Negation re-include probe — does `!plugins-config/.gitkeep` accidentally un-suppress a credential file?**: The negation is a LITERAL path (`plugins-config/.gitkeep`), not a glob. It can only reinstate exactly that one file. `plugins-config/.gitkeep` is verified zero-byte (`wc -c` = 0). There is no credential content to expose. PASS.

3. **Future-plugin scope — a third plugin added to the `for plugin in ArkShop Permissions` loop**: entrypoint.sh:272. A hypothetical `Economy2` plugin would write to `plugins-config/Economy2/config.json`. The `**` in the gitignore matches any depth and any future subdir — coverage is forward-compatible. PASS.

4. **Boundary — `./config/` bind mount (line 84 of docker-compose.yml)**: The second host-side bind (`./config:/home/container/config` → WindowsServer INIs) does NOT receive credential injection. `ARK_ADMIN_PASSWORD` is passed only as a CLI query-string parameter to the launch command (entrypoint.sh:421), never written to a file. No gitignore protection needed for `./config/` and the fix correctly omits it. PASS.

5. **Round-trip — mktemp write in `inject_plugin_db_config()`**: The `mktemp` at entrypoint.sh:331 creates a temp file inside the container at the OS temp dir (`/tmp`), which is not a host-side bind path and is not in git scope. The `mv` at line 344 writes the result into `ARK_DIR` (`/home/container/arkserver`) — also container-internal, not a host bind. No credential escapes to the host-side tracked tree via this path. PASS.

### Trace

Active adversarial input: Permissions plugin credential write (input #1 — the case the rationale didn't name, only ArkShop was cited).

1. `inject_plugin_db_config()` is called at entrypoint.sh:404.
2. At entrypoint.sh:351-368, if `plugins-config/Permissions/config.json` exists and has a `Mysql` block, the function injects `ARKSHOP_DB_PASS` into it via `jq` and overwrites the file via `mv`.
3. The write target resolves through the symlink created at entrypoint.sh:287 (`ln -sfn "${host_dir}" "${plugin_dir}"`), so the actual on-disk write lands at `./plugins-config/Permissions/config.json` on the host.
4. `git check-ignore -v "plugins-config/ArkShop/.sometoken"` → `.gitignore:1:plugins-config/**  plugins-config/ArkShop/.sometoken` (empirically confirmed). The `**` glob in gitignore matches any path component at any depth below `plugins-config/`, so `plugins-config/Permissions/config.json` is suppressed by the same rule.
5. The negation `!plugins-config/.gitkeep` is a literal path — it reinstates exactly one zero-byte placeholder file. It does not affect `plugins-config/Permissions/config.json` or any other credential-bearing file.

The fix is correctly scoped. It suppresses everything under `plugins-config/` (all runtime-written content) while tracking exactly the one placeholder needed to preserve the bind-mount directory in git. The glob is no wider than necessary — the entire `plugins-config/` subtree is the runtime credential zone by design (docker-compose.yml:88).

### Where the fix overshoots (BLOCK only)

N/A — verdict is PASS.

### Strategies attempted

- **Mixed inputs**: Constructed input #1 — Permissions plugin also receives credential injection and lands at `plugins-config/Permissions/config.json`. The rationale only named ArkShop. Empirically confirmed `plugins-config/**` covers this path. No break.

- **Boundary inputs**: Tested `plugins-config/` directory itself (not ignored — correct, you can't ignore the dir or .gitkeep vanishes with it). Tested zero-byte `.gitkeep` (confirmed empty — no credential content to expose via the negation). Tested dotfiles inside nested subdirs (`plugins-config/ArkShop/.sometoken`) — covered by `**`. No break.

- **Existing-primitive check**: Searched for any narrower gitignore pattern (e.g., `plugins-config/*/config.json` targeting only injected configs). None exists — the current `plugins-config/**` approach is the only pattern present. A narrower pattern (`plugins-config/*/config.json`) would work but would miss future non-config credential files and mktemp artifacts; the broader `**` is defensible given the stated "runtime contents are not tracked" design intent documented in the comment at .gitignore:6-7.

- **Second-caller check**: Checked whether `./config/` (second host-side bind, docker-compose.yml:84) also requires gitignore protection. Confirmed: no credential injection writes to `./config/` — `ARK_ADMIN_PASSWORD` goes to CLI args only (entrypoint.sh:421), not to any file. The fix correctly leaves `./config/` unprotected (operators should track their INI files). No break.

- **Round-trip / serialization**: Traced `inject_plugin_db_config()`'s mktemp usage (entrypoint.sh:331-344). Temp file created in container OS temp dir (not a host bind), moved into `ARK_DIR` (also container-internal). No credential leaks to host-side git-tracked paths via this route. No break.

### Bottom Line

Five adversarial probes across five strategies, including the Permissions credential-injection path the rationale didn't name — the glob eats all of them correctly. The fix is as wide as it needs to be and not one bit wider.
