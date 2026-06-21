# Rules Compliance Review: m2-shared-economy-store Phase 4 Round 1

## Verdict: BLOCK

## Diff Scope
- Files changed: 5 (`entrypoint.sh`, `docker-compose.yml`, `Dockerfile`, `.env.test.example`, `.env.prod.example`)
- Lines added/removed: +51 / -4
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example`

---

## Rule Sources Loaded

- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded (N/A — bash/Docker project; TypeScript rules don't apply)
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded
- `~/.claude/memory/graveyard.md`: loaded (all corpses read in full, both pages)
- `/home/patrick/docs/development/ark-asa/.claude/rules/build-time-vs-runtime.md`: loaded
- `~/.claude/agent-memory/rules-compliance-reviewer/MEMORY.md`: loaded
- `~/.claude/agent-memory/rules-compliance-reviewer/feedback_m1_m2_milestone_refs.md`: loaded
- Project `CLAUDE.md` (`/home/patrick/docs/CLAUDE.md`): loaded (life-hub root; no additional code rules)
- Project `rules/*.md`: `build-time-vs-runtime.md` loaded (above)
- Conditional global rules: `security.md` — N/A (no new endpoints/auth/SQL); `testing.md` — N/A (no test files in diff); `integrations.md` — N/A (no SDK changes in this diff layer)
- Domain memory files: `feedback_m1_m2_milestone_refs.md` loaded (M1/M2 label ruling applies); `feedback_dash_banner_variant.md` — N/A; `feedback_phase_5_leaves_it_pattern.md` — checked, no "Phase N leaves it" pattern in diff

---

## Required Fixes (BLOCK only)

### 1. Big-O annotation missing on `main()` after introducing a loop

**[entrypoint.sh:249]** WHAT: `for _ in $(seq 1 50); do [[ -S /tmp/.X11-unix/X0 ]] && break; sleep 0.1; done`

WHY: violates `~/.claude/rules/comments.md` Hard Rule 7 — `"Big-O on Tier 2+ functions — any function with loops, recursion, or accumulating data states time + space complexity."` Phase 4 introduces the first true `for` loop inside `main()`. The function has no `Time:` / `Space:` annotation. `main()` is unambiguously Tier 3 (orchestrates external I/O: file system, steamcmd, proton, tail). Hard Rule 7 says `Tier 2+` includes external I/O functions — the tier commentary explicitly lists "I/O-bound work: separate compute from I/O." The existing functions `deploy_plugins()` and `install_vcredist()` both carry `# Time: O(n)  Space: O(n)` / `# Time: O(1)  Space: O(1)` — `main()` is now the odd one out.

FIX: Add a `# Time: O(1) compute, N I/O ops  Space: O(1)` annotation (or equivalent accurate form) at the top of `main()`. The Xvfb wait loop itself is `O(50)` = `O(1)` (bounded constant). The dominant cost is external I/O (proton launch, steamcmd, tail). Accurate shape: `# Time: O(1) compute — Xvfb poll bounded to 50 iterations; I/O-bound (steamcmd + proton launch)  Space: O(1)` — place it as a comment block immediately after the `main() {` line, consistent with the style of `deploy_plugins()` and `install_vcredist()`.

---

## Project-vs-Global Overrides

None — no project rule contradicted a global rule on this diff.

---

## Notes on Non-Violations (reviewer transparency)

The following were checked and cleared:

**`build-time-vs-runtime.md` compliance — all three new placements pass the 3-question test:**

- **`unzip` in Dockerfile**: Q1 runtime state? No. Q2 changes often? No. Q3 must re-run each boot? No. → All "no" → Dockerfile ✓
- **pdb conditional deletion in `install_or_update()` (entrypoint)**: The deletion operates on game files that live on the volume. Q1 depends on runtime state (env var `ENABLE_ASAAPI` + mounted volume)? Yes → entrypoint ✓. The comment at entrypoint.sh:79–82 is a durable WHY explaining the AsaApi "Failed to read pdb" failure mode — not changelog language.
- **Xvfb startup in `main()` (entrypoint)**: Q3 must re-run on every container start? Yes (Xvfb must be alive each time the loader runs) → entrypoint ✓. The WHY comment at entrypoint.sh:101–104 correctly explains the `nodrv_CreateWindow` Wine failure mode.

**`M1` references in comments — per memory `feedback_m1_m2_milestone_refs.md`, allowed:**

Three occurrences of "M1" appear in added lines:
1. `entrypoint.sh:62` — `"0 = vanilla ArkAscendedServer (M1 rollback)"` — describes the current code's meaning (what `ENABLE_ASAAPI=0` does today); names the existing design state, not a future delivery.
2. `entrypoint.sh:96` — `"ENABLE_ASAAPI=0 restores the M1 vanilla path with no rebuild"` — architectural context (the path IS the current M1-era behavior).
3. `entrypoint.sh:104` — `"its launch stays byte-for-byte M1"` — same; clarifies the scope of the Xvfb skip.

All three name the CURRENT STATE of the code (what the `0` branch is). None promise future delivery. Per the Phase-5/Round-3 ruling: current-state architectural-context labels are allowed. ✓

**Graveyard corpse scan — no matches:**

- Test-Weakening: N/A (no test files)
- Silent Wrong-Output: N/A (no locale/timezone/monetary computation)
- Optional Object Fields (`?:`): N/A (bash, no TypeScript)
- Ambiguous Sentinel Values: `ENABLE_ASAAPI` uses `1`/`0` — boolean-style flag, both values documented inline in every occurrence (`.env.*.example`, `entrypoint.sh` default line). Exempt per comments.md sentinel rule ("Booleans — true/false are inherently two-valued and the field name carries the meaning").
- Integration Tests Racing: N/A (no test files)
- Redundant State: N/A (new toggle is not a duplicate of an existing invariant)
- Executor Laziness (TODOs / banned phrases / changelog comments): No `// TODO`, `// FIXME`, no `as any`, no banned changelog phrases in any added line. Checked explicitly.
- Untracked Deferrals: No deferral-language tokens (`defer`, `punt`, `revisit later`, `leave for now`, etc.) in any added line.
- Build-Twice: No throwaway/rebuild pattern proposed.
- Adversarial Reviewer Mutating Live File: N/A (this is the diff itself, not a reviewer action).
- Transaction-Rollback Isolation: N/A (no DB tests).
- Hand-Listed Enumerable Domain: N/A (no tests).
- Plan-File Edit Deletes Sibling Phase: N/A (plan.md not in this diff).

**no-duct-tape.md scan — clean:**

No banned phrases anywhere in the diff. The pdb retention decision names a concrete cost (AsaApi aborts with "Failed to read pdb") and a concrete mechanic (the `if [[ "${ENABLE_ASAAPI}" != "1" ]]` gate). This is a real tradeoff with a named cost, not duct tape.

**verification.md — N/A:**

Phase 4 is not a bug fix — it's a feature flip. No Paper-Trace required.

---

## Bottom Line

One finding: `main()` gains its first `for` loop this phase but still has no `# Time: / Space:` annotation, while every other function in the file carries one. Single-line fix at the `main() {` header. Everything else — build-vs-runtime placements, M1 labels, pdb retention logic, Xvfb idempotency — is clean.
