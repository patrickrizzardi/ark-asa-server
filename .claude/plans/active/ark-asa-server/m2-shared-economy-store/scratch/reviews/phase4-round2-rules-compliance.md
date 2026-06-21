# Rules Compliance Review: m2-shared-economy-store Phase 4 Round 2

### Verdict: BLOCK

### Diff Scope
- Files changed: 5 (`entrypoint.sh`, `docker-compose.yml`, `Dockerfile`, `.env.test.example`, `.env.prod.example`)
- Lines added/removed: +113 / -6 (entrypoint.sh dominates; other files are trivial config additions)
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example`

### Rule Sources Loaded
- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded
- `~/.claude/memory/graveyard.md`: loaded (all entries, including stubs)
- Project CLAUDE.md: N/A — not present at `ark-asa/` root; project CLAUDE.md found at `/home/patrick/docs/CLAUDE.md` (docs root, not this subproject) — not applicable
- Project rules: `ark-asa/.claude/rules/build-time-vs-runtime.md` loaded (diff touches Dockerfile/entrypoint split — direct match)
- Conditional global rules: none additionally triggered (no TypeScript, no SQL, no test files, no third-party SDK integrations in this diff)
- Domain memory files: `~/.claude/agent-memory/rules-compliance-reviewer/feedback_m1_m2_milestone_refs.md` loaded (diff contains M1 label references in WHY comments)

---

### Round-1 BLOCK Status: RESOLVED

Round-1 flagged: `main()` contained a `for` loop but had no Big-O annotation (`comments.md` Hard Rule 7).

**Status: RESOLVED.** The fix added a `# Time: O(1) compute; boot is I/O-dominated (...) Space: O(1)` comment as the first line inside the `main()` function body (entrypoint.sh:243–244). This is consistent with every other function in the file (all use first-line-of-body placement, which is the correct Bash analog to JSDoc-above — Bash has no JSDoc syntax). The comment explicitly covers the new `for _ in $(seq 1 50)` Xvfb socket-poll loop added in this phase, naming it in the annotation: "Xvfb socket poll bounded to 50 × 0.1s."

New function `ensure_modded_pdb()` compliance:
- Tier 3 docblock present: Flow section (4 steps listed), Time/Space annotation, Side effects section. Fully compliant with `comments.md` Tier 3 requirements.
- `for attempt in 1 2 3` loop covered by the Time annotation ("up to 3 steamcmd validate calls").
- Magic number "3" is documented in the Flow block ("Attempt steamcmd validate (up to 3 times)") and echoed in the runtime message ("attempt ${attempt}/3…"). Provenance established.
- `|| true` on steamcmd call has an inline WHY comment explaining steamcmd's unreliable exit codes. Not a silent swallow.

---

### Required Fixes (BLOCK)

1. **[entrypoint.sh:297]** WHAT: `Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &` — the geometry literal `1024x768x24` has no inline comment stating why this specific resolution was chosen.
   WHY: violates `~/.claude/rules/coding-style.md` (magic numbers section) — "Magic numbers without provenance (no import, no JSDoc rationale, not universal like Math.PI)". The surrounding comments explain WHY Xvfb is launched (AsaApiLoader needs an X display) but say nothing about WHY `1024x768` specifically — a reader would reasonably wonder if the resolution matters to Wine/ASA or if it's arbitrary.
   FIX: Add an inline comment: `Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &  # any valid X geometry; 1024x768x24 is conventional minimum — Wine/ASA ignore the actual resolution`

---

### All Other Checks — PASS

**comments.md scan:**
- No banned changelog phrases in any diff addition (`Replaces`, `Previously`, `Removed`, `Refactored from`, `Migrated from`, `Now uses`, `Switched to`, `Old version`, `New version`): CLEAN.
- No `// TODO`, `// FIXME`, `// XXX`, `// HACK`, `// Phase Nx` in additions: CLEAN.
- No commented-out code: CLEAN.
- No "WHAT the code does" comments (all comments explain WHY — e.g., WHY steamcmd exit code can't be trusted, WHY Xvfb is needed, WHY the pdb matters to AsaApi): CLEAN.
- `ensure_modded_pdb()`: Tier 3 — has loop + external I/O. Big-O annotation present. CLEAN.
- `main()`: has loop (Xvfb socket poll). Big-O annotation present (added in this round). CLEAN.

**no-duct-tape.md scan:**
- No banned phrases: "acceptable for now", "works in current state", "fine until we add", "we can revisit when", "only one consumer", "we'll make it configurable later", "this case can't happen yet", "intentional approximation", "minor — acceptable to leave", "good enough for the MVP": CLEAN.
- The retry-and-verify pattern in `ensure_modded_pdb()` is a real fix (not speculative): the pdb is verified via artifact presence, not steamcmd exit code. The WHY comment explains the unreliable exit-code behavior. This is not duct tape.
- `ENABLE_ASAAPI=0` as a kill switch: documented as restoring the M1 vanilla path. Named tradeoff (rebuild not required, identical args accepted). Not duct tape.

**M1 label references (per `feedback_m1_m2_milestone_refs.md` memory ruling):**
- `"M1 rollback"` in env default comment: describes CURRENT CODE PROPERTY (flipping to 0 restores the M1 path right now). Not a forward-delivery promise. ALLOWED.
- `"restores the M1 vanilla path with no rebuild"`: architectural-context label naming current design constraint. ALLOWED.
- `"its launch stays byte-for-byte M1"`: same — current behavior of the kill switch path. ALLOWED.

**verification.md scan:**
- The `ensure_modded_pdb()` retry+verify design is evidence-driven: the function validates success via file presence (`[[ -f "${pdb}" ]]`), not steamcmd's unreliable exit code. The WHY comment cites the actual failure mode ("steamcmd exits 0 even on transient failures"). This is a real-bug fix with named evidence, not speculative code.
- No speculative guards added for conditions not documented. CLEAN.

**coding-style.md scan:**
- Bash file — type-safety rules (no `as any`, no optional fields, no enums) don't apply.
- Magic number "50" in `seq 1 50`: documented via inline comment `# cap ~5s` (50 × 0.1s = 5s). Provenance established. CLEAN.
- Magic number "3" in `for attempt in 1 2 3`: documented in Flow block ("up to 3 times") and runtime echo. CLEAN.
- `1024x768x24`: NO inline rationale. BLOCK (Required Fix #1).

**graveyard.md corpse scan:**
- Test-Weakening: no test files in diff. N/A.
- Silent Wrong-Output Bugs: no locale/timezone/monetary operations. N/A.
- Optional Object Fields: Bash, no TypeScript structs. N/A.
- Ambiguous Sentinel Values: ENABLE_ASAAPI uses 1/0 with inline comments naming each value's meaning. CLEAN.
- Integration Tests Racing: no test files. N/A.
- Redundant State Duplicating Existing Invariants: no new DB columns/state fields. N/A.
- Executor Laziness (Smuggled TODOs, Duct-Tape Framings, Changelog Comments): no TODOs, no banned phrases, no changelog comments in additions. CLEAN.
- Untracked Deferrals: no deferral language ("defer", "punt", "revisit later", etc.) in any addition. CLEAN.
- Build-Twice: no throwaway-then-rebuild proposal. CLEAN.
- Adversarial Reviewer Mutating Live Production File: not applicable (reviewer-process corpse). N/A.
- Transaction-Rollback Isolation: no test suite changes. N/A.
- Hand-Listed Test Over Closed Enumerable Domain: no test files. N/A.
- Plan-File Edit Deletes Sibling Phase Section: plan.md not in diff. N/A.

**build-time-vs-runtime.md project rule scan:**
- `Xvfb` launch in entrypoint (runtime): CORRECT. Xvfb needs a live X socket on the running volume — cannot be pre-started in Dockerfile. Q3 ("must re-run on every container start"): yes. → entrypoint. COMPLIANT.
- `unzip` apt install in Dockerfile: CORRECT. Fixed build dependency, not runtime. → Dockerfile. COMPLIANT.

---

### Project-vs-Global Overrides
None — no project rule contradicted a global rule on this diff.

---

### Concerns
1. The `for _ in $(seq 1 50)` Xvfb poll uses `sleep 0.1` inside a shell `for` loop — spawns a subshell + `sleep` process 50 times in the worst case. For a boot script this is negligible (the comment explains Xvfb "comes up in well under 1s" so the loop almost never runs more than 1-2 iterations in practice). Non-blocking concern; mentioning for completeness.

---

### Bottom Line
Round-1 BLOCK is dead — `main()` Big-O is in, `ensure_modded_pdb()` has full Tier 3 docs and its own Big-O. One new BLOCK: the Xvfb geometry string `1024x768x24` needs a one-liner explaining that any valid X geometry works here. Trivial fix, then this phase is clean.
