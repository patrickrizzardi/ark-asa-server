# M2 Cumulative / Cross-Phase Deviation Judge — Consolidated

Plan: `.claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md`
Scope: cumulative pass across all 15 documented deviations (5 phases). Per-phase judges
already PASSed each deviation at its boundary; this pass reasons ACROSS phases to find
interactions a single-deviation judge structurally cannot see.

Diff base: `git diff 873509a..HEAD` (entrypoint.sh, Dockerfile, docker-compose.yml, .gitignore).

---

## Per-deviation re-confirmation + interaction check

### Phase 1 Deviation #1 (scope — evidence artifact): PASS
Plan-folder churn (`phase1-runtime-evidence.md`). Touches no deliverable code/config; cannot
interact with any other phase's runtime behavior. No cross-phase surface.

### Phase 2 Deviation #1 (approach — stash-rm-cp clean-replace): PASS
This is the deviation with the largest cross-phase surface (interacts with P5 symlink + P5
inject). Traced the SECOND-reboot path the per-phase judge could not see:

- Boot 1: `deploy_plugins` copies a real `config.json`; `setup_plugin_configs` (P5) then
  replaces it with a symlink → host bind; `inject_plugin_db_config` (P5) writes creds to the
  host target.
- Boot 2: `deploy_plugins` stash loop hits `[[ -f "${cfg}" ]]` where `${cfg}` is now a
  **symlink**. `-f` follows the link → true; `cp "${cfg}" stash` copies the host file
  (creds included). `rm -rf "${win64}/ArkApi"` removes the **symlink** (not the host target —
  verified: host file survives). `cp -r src/ArkApi` lays down a fresh image default. Restore
  loop `cp stash → plugin_dir/config.json` writes a **regular file** with creds. Then
  `setup_plugin_configs` re-runs `ln -sfn` (replaces the regular file with the symlink again),
  and `inject` overwrites with env creds via the symlink-resolving `_inject_mysql_block`.

Empirically reproduced the stash→rm→restore→re-symlink cycle in `/tmp` (two harnesses):
creds round-trip intact, host file survives `rm -rf`, DLL siblings always re-supplied from the
image, symlink re-established every boot. The final `inject` is idempotent against env creds,
so even the stash round-trip is belt-and-suspenders. No break.

### Phase 2 Deviation #2 (approach — versioned URLs + PERMISSIONS_VERSION doc-pin): PASS
`?version=${ARG}` interpolation is build-time only (Dockerfile). `PERMISSIONS_VERSION` drives
no URL (doc-pin; Permissions ships inside the AsaApi zip). No runtime seam with any later phase.
Permissions config injection (P5) operates on the deployed file regardless of which version
string baked it. No interaction.

### Phase 2 Deviation #3 (scope — decision re-homed to plan.md ledger): PASS
Plan/notes churn. No runtime surface.

### Phase 3 Deviation #1 (approach — conjunctive `marker AND 3 DLLs` VC++ fast-path): PASS
Cross-phase check vs P4 launch + P5 deploy: `install_vcredist` runs BEFORE the launch gate and
before `ensure_modded_pdb`. Its skip gate keys on the three prefix `system32` DLLs (source of
truth), so a prefix reset re-triggers install — correct for the P4 loader which needs those DLLs
in the prefix. `deploy_plugins` separately drops `msvcp140.dll` into Win64 (Wine app-dir search
path); the two msvcp140 copies are the same MS runtime in different resolution locations — no
conflict. No interaction breaks.

### Phase 4 Deviation #1 (scope — unzip apt layer in Dockerfile): PASS
Build-time dependency for P2's plugin-extraction RUN. P5 later added `jq` to the SAME apt line
(`unzip jq`) — complementary, not conflicting. Pure build-time; no runtime seam.

### Phase 4 Deviation #2 (approach — Xvfb on the loader branch): PASS
Gated to `ENABLE_ASAAPI=1`. Cross-phase check vs P5 plugin-load path: Xvfb provides the X
display the loader needs to create its init window; P5's plugin config injection happens BEFORE
launch and is display-independent. The vanilla branch (`ENABLE_ASAAPI=0`) skips Xvfb AND skips
all P5 plugin setup (`setup_plugin_configs`/`inject`/MODS-append are all inside the same
`ENABLE_ASAAPI==1` block) — so the M1 rollback path stays byte-for-byte clean. The two gated
blocks share one discriminator; no path mixes a modded launch with a vanilla setup or vice
versa. No interaction.

### Phase 4 Deviation #3 (approach — keep ArkAscendedServer.pdb when modded): PASS
Cross-phase check vs P2's `.pdb` strip: P2's Dockerfile `find /opt/asaapi -name '*.pdb' -delete`
removes `AsaApiLoader.pdb` from the baked plugin tree; P4 keeps `ArkAscendedServer.pdb` (the game
server symbol pdb on the volume). **Different files, different trees** — AsaApi SHA-256s the
server pdb for its offset-cache key, not the loader's own pdb. `deploy_plugins` also `rm`s
`AsaApiLoader.pdb` from Win64 and never copies it back (absent from the cp list) — consistent
with it being unneeded. `ensure_modded_pdb` (the vanilla→modded flip recovery) runs before
launch and restores the server pdb via steamcmd validate with a >1MiB truncation guard. No
collision between the two pdb policies.

### Phase 5 Deviation #1 (scope — jq in Dockerfile apt layer): PASS
Same apt line as P4's unzip. Build-time. No runtime seam.

### Phase 5 Deviation #2 (scope — plugins-config/** gitignore + .gitkeep exception): PASS
The gitignore `plugins-config/**` + `!plugins-config/.gitkeep` correctly tracks the bind-mount
dir while excluding the runtime-injected creds. Verified the .gitkeep co-exists with the runtime
config files (no co-landed real file that the glob would wrongly suppress — the only tracked file
is the .gitkeep). The same diff hunk also adds an unrelated `.claude/plans/**/status.json` ignore
(plan-status heartbeat) — orthogonal, no interaction with the plugin path. No break.

### Phase 5 Deviation #3 (scope — plugins-config/.gitkeep): PASS
Ensures the host bind dir exists pre-`up` so Docker doesn't root-create it. Interacts with P5
Deviation #5 (the `./plugins-config` bind in compose) — complementary: the .gitkeep guarantees
the checkout has the dir the compose bind targets. No conflict.

### Phase 5 Deviation #4 (scope — notes.md churn): PASS
Plan churn. No runtime surface.

### Phase 5 Deviation #5 (approach — separate ./plugins-config dir, not ./config reuse): PASS
Cross-phase check vs the P-existing `./config` → WindowsServer symlink: the two binds target
distinct host dirs and distinct symlink targets (engine INI vs plugin config.json). Keeping them
separate is what AVOIDS the collision the per-field reuse would have caused. `setup_plugin_configs`
symlinks ONLY `config.json` (not the plugin dir), so the DLL that `deploy_plugins` lays down
survives. Verified empirically: DLL sibling untouched, only config.json is the symlink. No break.

### Phase 5 Deviation #6 (approach — jq --arg for all creds): PASS
`_inject_mysql_block` resolves the symlink (`[[ -L ]] && readlink -f`) and `mv`s onto the real
host target — does NOT replace the symlink with a regular file (which would orphan the host bind).
This is the exact interaction with P5 Deviation #5's symlink, and it's handled correctly. The
`|| { rm tmp; exit 1; }` handler is in final list position so `set -e` fires on jq failure.
`tonumber` keeps MysqlPort integer-typed. Re-running across boots is idempotent (env creds
constant within a boot; the deploy→re-copy→re-inject cycle reproduces identical content).
Permissions branch is guarded on `jq -e 'has("Mysql")'` — silently skips if the image default
lacks the block (intentional optional). No break.

### Phase 5 Deviation #7 (approach — auto-append 955333 to MODS inside ENABLE_ASAAPI=1, de-dup): PASS
Cross-phase check vs the vanilla path: the append lives inside the `ENABLE_ASAAPI==1` block, so
`ENABLE_ASAAPI=0` never gets 955333 — the M1 vanilla launch passes only the operator's MODS.
De-dup (`,${MODS}, != *,955333,*`) handles the operator-already-listed case. The flag assembly
`[[ -n "$MODS" ]] && flags="${flags} -mods=${MODS}"` runs after the append, so the modded launch
correctly carries the utils mod. No interaction with Xvfb or plugin setup (all in the same gated
block). No break.

---

## Cross-phase seams explicitly probed (adversarial inputs the per-phase judges could not run)

1. **Second-reboot stash/symlink/inject cycle** (P2 D1 × P5 D5 × P5 D6): reproduced in `/tmp` —
   creds survive, host file survives `rm -rf`, symlink re-established, inject idempotent. PASS.
2. **Dual-config (ArkShop + Permissions) injection through symlinks** (P5 D6): both inject to
   host via resolved symlink; DLL siblings untouched. PASS.
3. **Two-pdb policy collision** (P2 D2-pdb-strip × P4 D3): different files/trees — loader pdb vs
   server pdb. No collision. PASS.
4. **VC++ DLL location** (P3 D1 × P4 D2 × P5 deploy): prefix system32 (install_vcredist) vs Win64
   (deploy_plugins) — same runtime, two valid Wine search locations. PASS.
5. **Vanilla-path purity** (P4 D2 Xvfb × P4 D3 pdb × P5 D5/D6/D7 plugin setup): all modded-only
   behavior is gated under one shared `ENABLE_ASAAPI==1` discriminator; no path mixes modded and
   vanilla halves. ENABLE_ASAAPI=0 stays byte-for-byte M1. PASS.

No cross-phase interaction breaks a sibling deviation's assumption. The live-on-dell verification
(ArkShop↔MariaDB, points persist, restart survives) is consistent with the static trace — and the
second-reboot path I traced is exactly the "restart survives" claim, now mechanically confirmed.

---

## OVERALL VERDICT: PASS

All 15 deviations re-confirm individually and compose cleanly. The five highest-risk seams were
each probed with a fresh adversarial input (concentrated on the second-reboot stash/symlink cycle,
which no per-phase judge could see). None break.

### Bottom Line
Fifteen deviations, five seams, one shared `ENABLE_ASAAPI` discriminator holding the modded and
vanilla halves apart — and the nastiest seam (deploy_plugins eating a symlinked config on reboot
#2) round-trips the creds clean. It holds, chief. PASS.
