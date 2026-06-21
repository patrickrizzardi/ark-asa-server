# Deviation Judge — Phase 5 Round 3 Deviation #6
# Plan: m2-shared-economy-store | jq --arg cred injection

## Verdict: PASS

---

## Deviation summary (one line)

`_inject_mysql_block()` resolves symlinks before `mv` so the host-bind symlink is preserved when jq-written output replaces the config file; all creds pass through `jq --arg`, port coerces via `tonumber`.

---

## Adversarial input(s) constructed

1. **Broken 1-hop symlink**: `cfg` is a symlink → nonexistent file whose parent directory exists (e.g., `plugins-config/ArkShop/config.json` → `/host-dir/config.json` where `/host-dir/` doesn't exist yet). `readlink -f` returns the target path with exit 0. jq then tries to open `${cfg}` (the symlink) for reading → fails because the target doesn't exist → `|| { rm -f "${tmp}"; exit 1; }` fires correctly. No partial write, no leaked tmp.

2. **Circular symlink / deep chain**: `cfg` → `link2` → `link1` (circular). `readlink -f "${cfg}"` exits nonzero and returns empty string. Under `set -euo pipefail`, the construct `[[ -L "${cfg}" ]] && dest="$(readlink -f "${cfg}")"` — the RHS of `&&` exits nonzero → the compound exits nonzero → `set -e` aborts the script immediately. `mktemp` hasn't been called yet (it's on line 323, after line 321 where readlink fires) → no tmp file created, no leaked temp. Operator gets silent exit 1 (no diagnostic message), but no data corruption.

3. **Regular file (not a symlink)**: `[[ -L "${cfg}" ]]` is false → `dest="${cfg}"` (unchanged). The round-2 behavior is fully preserved — jq reads `${cfg}`, writes to `${tmp}`, mv replaces `${cfg}` in place. No regression.

4. **Cross-filesystem mv** (`/tmp` is tmpfs; `dest` is on the Docker bind-mount at `/home/container/plugins-config/`): `mv` across filesystems falls back to copy+unlink, which is non-atomic. A power-loss or OOM-kill mid-copy leaves a partially-written `config.json`. This is a real concern, but: (a) it predates the round-3 change — the same tmp+mv pattern existed in round 2 before symlink resolution was added; (b) the deviation's stated scope is cred injection safety (`jq --arg` vs sed) + port type correctness, not write atomicity; (c) the atomic fix (use `mktemp -p "$(dirname "${dest}")"` to keep tmp on the same filesystem) is a narrower concern orthogonal to this deviation. Not a BLOCK for this deviation's scope.

5. **`dest=""` reaching `mv`**: Demonstrated impossible via the input space. `readlink -f` returns empty with nonzero exit only for circular/too-many-hops (aborting via `set -e` before `mktemp`). `readlink -f` on an empty-string argument also returns nonzero. The only non-empty `dest` values that reach `mv` are valid paths where `mv` either succeeds or fails+aborts (leaking the tmp file, but not corrupting an existing config).

6. **jq failure with new `dest` variable**: The `|| { rm -f "${tmp}"; echo "FATAL..."; exit 1; }` handler references only `${tmp}`, not `${dest}`. `dest` is irrelevant to jq failure handling. The round-2 fix is unaffected by the round-3 symlink change.

---

## Trace

**Strongest input: Broken 1-hop symlink (input #1)**

Entry: `inject_plugin_db_config()` calls `_inject_mysql_block "${arkshop_cfg}"` at entrypoint.sh:395.

`arkshop_cfg` = `/path/Win64/ArkApi/Plugins/ArkShop/config.json` — this is the path `setup_plugin_configs()` replaced with a symlink via `ln -sfn "${host_dir}/config.json" "${plugin_dir}/config.json"` (entrypoint.sh:291). The symlink points to the host bind at `/home/container/plugins-config/ArkShop/config.json`.

Assume the host bind directory `/home/container/plugins-config/ArkShop/` does NOT exist (e.g., volume not yet initialized, or a first-boot edge where `mkdir -p` in `setup_plugin_configs` failed silently after the symlink was already in place from a prior boot).

Step 1 — entrypoint.sh:319: `cfg="$1"` → cfg = symlink path.
Step 2 — entrypoint.sh:320: `dest="${cfg}"` (initial value).
Step 3 — entrypoint.sh:321: `[[ -L "${cfg}" ]]` → TRUE (it's a symlink).
Step 4 — entrypoint.sh:321: `dest="$(readlink -f "${cfg}")"`. The symlink target's parent exists (the host bind dir path exists on the filesystem — the volume IS mounted, just the file is absent). `readlink -f` exits 0, returns `/home/container/plugins-config/ArkShop/config.json` (non-empty). `dest` is set correctly.
Step 5 — entrypoint.sh:323: `tmp="$(mktemp)"` → tmp = `/tmp/tmpXXXXXX`.
Step 6 — entrypoint.sh:324-335: `jq ... "${cfg}" > "${tmp}"`. jq opens `${cfg}` (the symlink) → follows symlink → target `/home/container/plugins-config/ArkShop/config.json` does not exist → jq exits 2 with "Could not open file: No such file or directory".
Step 7 — entrypoint.sh:335: `|| { rm -f "${tmp}"; echo "[entrypoint] FATAL: jq failed..."; exit 1; }` fires. Tmp cleaned. Script exits 1.

Result: clean abort with diagnostic message. No partial write, no leaked tmp, no mv to an unexpected destination. The symlink itself is untouched.

**Input #2 — Circular symlink trace**

Step 1-2: same as above.
Step 3: `[[ -L "${cfg}" ]]` → TRUE.
Step 4: `readlink -f "${cfg}"` → exit 1, empty stdout. The command-substitution assignment `dest="$(...)"`  exits nonzero. Under `set -euo pipefail`, the `&&` compound's RHS exit nonzero propagates → compound exits nonzero → `set -e` fires → script aborts at entrypoint.sh:321.
`mktemp` (line 323) never called → no tmp file created.

Result: script abort at line 321. No diagnostic. Operator sees exit 1, container restarts. Not ideal UX, but no data corruption.

---

## Where the fix overshoots (BLOCK only)

N/A — verdict is PASS.

---

## Strategies attempted

- **Mixed inputs**: Tested symlink (the case the round-3 rationale names) mixed with an absent target (the case it didn't name). jq's failure to open `${cfg}` catches it before `mv` fires. No overshoot.

- **Boundary inputs**: Empty `dest` string — demonstrated unreachable through any input path because `readlink -f ""` exits nonzero, aborting via `set -e` before `mv`. Single-hop broken vs circular symlink tested explicitly — behaviors differ (1-hop: rc=0 non-empty dest → jq catches it; circular: rc=1 → set-e aborts first).

- **Existing-primitive check**: Checked whether a same-filesystem `mktemp` via `mktemp -p "$(dirname "${dest}")"` would be a narrower fix for the cross-filesystem atomicity concern. It would be, but that concern predates the round-3 change and is orthogonal to the deviation's stated scope (cred injection safety + port type). Not a BLOCK.

- **Second-caller check**: `_inject_mysql_block` is called twice: once for ArkShop (entrypoint.sh:395), once for Permissions (entrypoint.sh:401, guarded by `jq -e 'has("Mysql")'`). Both callers supply a `cfg` path produced by `setup_plugin_configs()`'s `ln -sfn` (entrypoint.sh:291). Both paths are symlinks under the same pattern. The symlink-resolution logic applies identically to both callers — no divergence.

- **Trace-through**: Walked jq failure path with new `dest` variable — `|| { rm -f "${tmp}"; exit 1; }` only references `${tmp}`, not `${dest}`. Round-2 fix intact.

- **Round-trip**: Cred values containing special characters (spaces, `$`, `"`, `\n`, `#`, `@`) passed via `jq --arg` are treated as literal strings in jq — no shell expansion, no jq filter injection. `tonumber` on a port string validated upstream by the regex guard `^[0-9]+$` (entrypoint.sh:368) before `_inject_mysql_block` is ever called. Round-trip is clean.

---

## Bottom Line

Every adversarial path I could construct either aborts cleanly before writing anything or hits the existing `|| { rm -f "${tmp}"; exit 1; }` guard. The symlink-resolution change threads the needle correctly: jq reads through the symlink, mv targets the real file, the link survives. PASS.
