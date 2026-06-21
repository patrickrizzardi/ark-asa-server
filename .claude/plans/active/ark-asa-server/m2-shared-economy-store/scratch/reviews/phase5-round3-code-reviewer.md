# Code Review: m2-shared-economy-store Phase 5 (Round 3)

### Verdict: PASS

### Diff Scope
- Files changed (code, this round's focus): `entrypoint.sh` (+164 net since Phase-4 BASE), `Dockerfile` (+jq), `docker-compose.yml`, `.gitignore`, `.env.*.example`, `README.md` — plan.md/state.md/notes.md/scratch ignored per instructions.
- Two new runtime-fix commits since rounds 1+2: `042bef4` (config.json file-symlink + readlink-resolve), `96e3813` (Xvfb stale-lock cleanup).
- Phase commits reviewed: 72171a9, 042bef4, 96e3813 (working tree vs 4f19274). Focus: entrypoint.sh.

### What's Solid
- FIX 1 is a genuine root-cause fix, not a patch over a symptom. The prior version's `rm -rf plugin_dir + symlink-to-config-only-host-dir` deleted `ArkShop.dll`; the new shape symlinks ONLY `config.json` (the file), leaving the DLL in the deploy_plugins()-managed dir. Verified end-to-end below.
- The `readlink -f` + `mv`-to-resolved-dest is the correct fix for the "mv replaces symlink with regular file" trap. Traced empirically: symlink preserved, creds land on the host bind target, idempotent across restart.
- FIX 2's safety reasoning is correct and the comment states the real WHY (PID-namespace teardown on `docker compose restart` guarantees old Xvfb dead; /tmp is on the writable layer not a volume, so artifacts persist — hence the stale lock). Clearing them before re-launch is safe and closes the false-pass race.
- `jq --arg` choice (Approach Deviation #2/#6, adjudicated rounds 1-2) is the right call — special chars in DB passwords can't break the JSON, and `tonumber` keeps MysqlPort integer-typed.
- The `|| { rm -f tmp; echo FATAL; exit 1; }` on the jq write is load-bearing and correct: jq sits in a non-final position of an `&&` list where `set -e` does NOT abort; the explicit exit closes the swallowed-failure hole. Good catch by the executor and accurately documented.

### Required Fixes (BLOCK only — empty if PASS)
None — phase ready to commit.

### Concerns (non-blocking, but will bite later)
1. `phase5-runtime-evidence.md` cited in the review prompt does NOT exist on disk — only `phase1-runtime-evidence.md` and `phase4-runtime-evidence.md` are present in the plan folder. The runtime claims (plugins load, tables created, restart survives) are asserted in the prompt but have no persisted evidence artifact. This is acceptance-evidence territory — **cross-flag to acceptance-verifier** to confirm the evidence is captured before the phase closes. My code-quality verdict does not depend on it: I verified FIX 1 by tracing the symlink/readlink/mv chain in a live shell rig (config preserved + creds on host + idempotent) and FIX 2 by confirming PID-namespace/restart semantics and the rm being no-op-safe — that is stronger than a self-reported markdown file.
2. `mktemp` defaults to `/tmp` (container writable layer) while the injected `dest` is on the `./plugins-config` bind mount — `mv` is therefore cross-device and falls back to copy+unlink (non-atomic). For a single-user game container booting serially this is inconsequential (no concurrent reader during boot, before the loader launches), so not a fix — noting it so a future maintainer who adds concurrency knows the write isn't atomic.

### Laziness Pattern Audit
- Placeholder / mock pollution: PASS — no dummy values; all creds sourced from env (ARKSHOP_DB_* → MARIADB_* fallback), never a literal in-script.
- Half-finished implementations: PASS — both new functions handle the not-deployed branch (warn+skip), the missing-config branch (FATAL fail-fast for mandatory ArkShop, soft `has("Mysql")` gate for optional Permissions), and the jq-failure branch (explicit exit). No happy-path-only logic.
- Type escape hatches (code-quality angle): N/A — bash, not TypeScript.
- Smuggled TODOs (code-quality angle — incomplete work shipped): PASS — no TODO/FIXME/Phase markers; comments describe current constraints, not deferred work.
- Magic constants without provenance: PASS — `955333` (ASA API Utils mod ID) and `3306` (default MariaDB port) both carry inline provenance comments; geometry `1024x768x24` documented as an arbitrary headless minimum.
- Documented deviations — adversarial inputs constructed (NOT the case executor named): PASS — see below. The 7 deviations were adjudicated in rounds 1-2; this round's two FIXES were validated with adversarial inputs:
  - FIX 1 adversarial input (RESTART, not fresh boot — the case the executor's "preserves DLL" story did NOT name): traced boot-2 where the host config ALREADY holds injected creds and `ArkShop/config.json` on the volume is ALREADY a symlink from boot 1. deploy_plugins() `cp`s through the symlink into its stash (creds preserved), `rm -rf ArkApi/` removes the symlink, copies fresh image tree, restores stash as a regular file; setup_plugin_configs() sees host config present → no re-seed (operator edits preserved) → `ln -sfn` replaces the regular file with the symlink (verified `ln -sfn` over a regular file works); inject re-runs idempotently. No DLL loss, no orphaned config, no double-seed. Survives.
  - FIX 1 second adversarial input (image default ships NO `.Mysql` key): `jq '.Mysql.UseMysql = true'` CREATES the intermediate object (verified) and MysqlPort stays integer via tonumber. Injection robust regardless of image-default shape.
  - FIX 2 adversarial input (FIRST boot, artifacts absent — not the restart case the executor named): `rm -f` of two absent paths exits 0 under `set -euo pipefail` (verified), plus a redundant `2>/dev/null || true`. No regression on the fresh-container path.
  - Strategies attempted: restart-state / boundary (absent files) / missing-key shape / mv-symlink-preservation trace. None broke either fix.

### Test Coverage Audit
N/A — not a bug-fix-first TDD plan or Tier A correctness plan; this is infra/shell (Dockerized game server entrypoint) with no unit-test harness. Verification standard for this plan is runtime evidence on the dell test box (see Concern #1 — cross-flag to acceptance-verifier for the missing phase5 evidence artifact). Code-quality verification done by direct shell-rig tracing of both fixes (FIX 1 symlink/readlink/mv chain across fresh+restart boots; FIX 2 rm safety + restart PID-namespace semantics). No existing test weakened (no tests in repo).

### Bottom Line
Both fixes hold, chief — FIX 1's readlink-resolve keeps the DLL and lands creds on the host file even across a restart with a pre-injected config, and FIX 2's lock-clear is safe because the old Xvfb is guaranteed dead when /tmp's stale crumbs aren't. Only loose thread is the phantom phase5-runtime-evidence.md — that's acceptance-verifier's bone to chew, not a code-quality block.
