# Code Review: m2-shared-economy-store Phase 4 (round 2)

### Verdict: PASS

### Diff Scope
- Files changed: 5 (entrypoint.sh, docker-compose.yml, Dockerfile, .env.test.example, .env.prod.example)
- Lines added/removed: +73 / -5 (full phase diff vs 29735d2)
- Phase commits reviewed: staged/uncommitted working tree (diff base `29735d2`); round-2 delta is entrypoint.sh only

### What's Solid
- **Round-1 BLOCK is genuinely resolved.** `ensure_modded_pdb()` (entrypoint.sh:194-240) fires at the launch gate (main() line 271-273) gated on `ENABLE_ASAAPI=1`, NOT on the `.installed` marker. Traced the vanilla→modded flip cold: volume first-installed with `ENABLE_ASAAPI=0` sheds the pdb + writes `.installed` → reboot with `ENABLE_ASAAPI=1` → `install_or_update` short-circuits on the marker (line 33/58) → main() still reaches the unconditional pdb gate → `ensure_modded_pdb` finds pdb absent → steamcmd validate restores it. The silent-zero-plugin failure mode the round-1 BLOCK named is closed. dell evidence confirms ("pdb restored on attempt 1", both plugins loaded).
- **Artifact-trust discipline is consistent.** The function trusts the pdb file's *presence* over steamcmd's exit code (line 226 `|| true`, line 227 presence check, line 234 fatal-exit) — same pattern as the existing `install_vcredist` DLL check and the `install_or_update` SERVER_EXE check. No new convention invented.
- **3-attempt retry with fatal-exit is the right shape.** steamcmd's documented transient-failure-with-exit-0 footgun ("Timed out waiting for update to start") is handled by retry; permanent failure (CDN down, disk full) terminates the boot loudly rather than launching into the silent failure. Named in the fatal message.
- **Xvfb fail-fast guard (round-1 concern #1) is real, not cosmetic.** Post-readiness-loop socket re-check (line 306-310) converts a silent timeout into a loud `exit 1`. Verified the `&&`-break loop and the cleanup line do not trip `set -e`.
- **Vanilla path stays byte-for-byte M1.** `ENABLE_ASAAPI=0` skips `ensure_modded_pdb` (line 271 guard), skips Xvfb, sets `launch_exe=SERVER_EXE`. AC3 on dell confirms vanilla still boots with zero AsaApi load.
- **Big-O comment on main() (rules-compliance BLOCK) present** (line 243-244), correctly separating O(1) compute from the I/O-dominated boot (bounded steamcmd calls + bounded Xvfb poll).

### Required Fixes (BLOCK only — empty if PASS)
None — phase ready to commit.

### Concerns (non-blocking, but will bite later)
1. **entrypoint.sh:44** — the install-time shed comment reads `Movies/ is always safe to drop (~?GB of intros)`. The literal `~?GB` is a placeholder where a size estimate should be — a "didn't fill it in" artifact in a durable comment. Either drop the parenthetical or put the real number (the evidence file says the pdb is ~2.0GB / the original comment said ~6GB; Movies is a separate unstated size). Comment-only, no behavior impact.
2. **ensure_modded_pdb pdb integrity** — the restore guard is presence-only (`[[ -f "${pdb}" ]]`). A truncated/partial pdb would pass the guard, AsaApi would SHA-256 a corrupt file → wrong cache key → silent zero-plugin load again. In practice steamcmd `validate` is integrity-checking by contract (that is precisely what `validate` does — it re-pulls corrupt files), and the codebase's existing artifact checks (`install_vcredist`, install SERVER_EXE) all use presence-only, so this is consistent and the realistic risk is low. Noting it because the function's entire reason to exist is preventing a silent-load failure; if a future change swaps `validate` for a plain `app_update`, the integrity assumption breaks. Not a BLOCK.
3. **Xvfb orphan on fail-fast exit** — when the Xvfb socket check fails (line 306-310), the script `exit 1`s while the backgrounded Xvfb (`xvfb_pid` already set) is left running. Harmless — the container is dying on that exit — but worth noting if the script ever gains a non-fatal recovery path here.

### Laziness Pattern Audit
- Placeholder / mock pollution: FAIL (minor) — `~?GB` placeholder in the entrypoint.sh:44 comment (Concern #1). No placeholder in executable code paths.
- Half-finished implementations: PASS — `ensure_modded_pdb` handles the absent-pdb branch, the retry-exhaustion branch (fatal-exit), and the already-present early-return. Xvfb branch handles both bind-success and bind-failure. No happy-path-only logic.
- Type escape hatches (code-quality angle): PASS — N/A for bash; no `eval`, no unquoted expansions that hide a bug (the deliberate unquoted `${force_windows}`/`${flags}` word-splits are documented and intentional).
- Smuggled TODOs (code-quality angle): PASS — no TODO/FIXME/Phase-N references in code. The pdb/Phase-5 deferral (AsaApiUtils optional mod) is documented in the plan + evidence, not smuggled in a comment.
- Magic constants without provenance: PASS — the `1 2 3` retry count and `seq 1 50`/`sleep 0.1` (~5s) Xvfb cap are both documented inline with rationale ("Xvfb is local and comes up in well under 1s"). The `1024x768x24` Xvfb geometry is a throwaway framebuffer for a headless window — no provenance needed.
- Documented deviations — adversarial inputs constructed (NOT the case executor named): PASS — the executor's named case was "delete pdb, boot modded, it self-heals." Adversarial inputs attempted across strategies: (a) **second-config** — `UPDATE_ON_BOOT=1 + ENABLE_ASAAPI=1` on a vanilla-shed volume: `install_or_update` takes the delta-update branch (no validate, won't re-pull the shed pdb), but the launch-gate `ensure_modded_pdb` still fires unconditionally → restores it. Holds. (b) **boundary/integrity** — partial pdb write passing the presence-only guard (Concern #2): theoretically breaks but mitigated by `validate`'s integrity contract. (c) **second-caller/rollback** — `ENABLE_ASAAPI=0` regression: pdb gate skipped, Xvfb skipped, vanilla launch byte-for-byte M1 (AC3 confirms). Holds. None of the adversarial inputs broke the fix; the one theoretical break (partial pdb) is gated by steamcmd's own contract. Deviation validated.

### Test Coverage Audit
N/A — not a bug-fix or Tier A code plan. This is infra (Dockerfile/entrypoint/compose); the verification artifact is the real `docker build` + boot on dell (`phase4-runtime-evidence.md`), which is the correct evidence form for a Proton-under-Docker stack that cannot run in the review environment. AC1/AC2/AC3 each have concrete log receipts (AsaApi "API was successfully loaded" + both plugins; "successfully started" + "advertising for join" under AsaApiLoader; vanilla rollback with AsaApi count 0). Round-2 fix re-verified by deleting the pdb to simulate a vanilla-shed volume and booting modded → "pdb restored on attempt 1" → clean load.

### Bottom Line
Chief, the executor actually closed the hole this time — pdb self-heal fires at the launch gate, not the install marker, and the Xvfb guard barks instead of dying quiet. Two cosmetic nits (a `~?GB` placeholder comment and a presence-only pdb check that steamcmd's own validate already backstops) — neither blocks the commit.
