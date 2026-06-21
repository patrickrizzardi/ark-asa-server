# Rules Compliance Review: m2-shared-economy-store Phase 4 Round 3

### Verdict: PASS

### Diff Scope
- Files changed: 5 (`entrypoint.sh`, `docker-compose.yml`, `Dockerfile`, `.env.test.example`, `.env.prod.example`)
- Lines added/removed: +155 / -7 (entrypoint.sh dominates; other files are trivial additions)
- Diff source: `git diff 29735d2 -- entrypoint.sh docker-compose.yml Dockerfile .env.test.example .env.prod.example`

---

### Rule Sources Loaded

- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded
- `~/.claude/memory/graveyard.md`: loaded (all entries through 2026-06-15)
- Project CLAUDE.md: N/A — not present at `ark-asa/` root; `/home/patrick/docs/CLAUDE.md` is the docs-root CLAUDE.md, not a subproject CLAUDE.md, not applicable
- Project rules: `ark-asa/.claude/rules/build-time-vs-runtime.md` loaded (diff directly touches Dockerfile + entrypoint split)
- Conditional global rules: security.md — N/A (no endpoints, no auth, no SQL); testing.md — N/A (no test files); integrations.md — N/A (no third-party SDK integrations in diff); branching.md — N/A (no PR/branch work)
- Domain memory files: `~/.claude/agent-memory/rules-compliance-reviewer/feedback_m1_m2_milestone_refs.md` loaded (diff contains "M1 rollback" label in WHY comments — matches M1/M2 milestone refs pattern)

---

### Round-2 BLOCK Resolution

**Round-2 BLOCK**: `[entrypoint.sh:297]` — Xvfb geometry literal `1024x768x24` had no inline comment stating why this specific resolution was chosen. Violated `~/.claude/rules/coding-style.md` magic-number / `~/.claude/rules/comments.md` (non-obvious constant without provenance).

**Resolution status: CONFIRMED RESOLVED.**

The round-3 fix added the following comment immediately above the `Xvfb` invocation:

```
# Geometry 1024x768x24 is an arbitrary conventional minimum: the loader only needs a valid display
# to create its init window; ASA/Wine render nothing (headless), so the actual resolution is ignored.
```

This is a durable-WHY comment (explains WHY this specific value was chosen), not a changelog phrase. It passes `comments.md § Durable, not changelog`. The provenance is established: arbitrary conventional minimum, actual resolution ignored in headless context. BLOCK is cleared.

---

### New Code Compliance Check

#### `1048576` literal in `pdb_ok()`

The `pdb_ok()` helper introduces `1048576` (1 MiB) as the size threshold. Magic-number rule (`coding-style.md`) requires provenance via comment, import, or JSDoc.

**Provenance check**: Three lines above the literal, the comment states:

```
# The real pdb is ~6GB; require >1 MiB to reject truncated files while never rejecting a real one.
```

The comment explicitly names:
- The origin of the threshold: `>1 MiB` (to reject truncated files)
- The engineering rationale: a truncated pdb (e.g., from disk exhaustion mid-download) would pass a bare `-f` test but fail AsaApi's SHA-256 step; 1 MiB is large enough to guarantee a non-trivial file without risking rejection of a valid ~6GB pdb
- The units: `1048576 = 1 MiB = 2^20 bytes` — standard binary prefix, immediately derivable from the "1 MiB" prose

**Verdict**: Provenance established. Not a magic number per the rule. PASS.

#### `pdb_ok()` helper — Big-O annotation requirement

`pdb_ok()` is a one-liner inline function (`[[ -f ... ]] && [[ ... -gt ... ]]`) with zero loops, no recursion, and no accumulating data. It is unambiguously Tier 1 (pure predicate). `comments.md` Hard Rule 7 requires Big-O annotation on **Tier 2+ functions** — "any function with loops, recursion, or accumulating data." `pdb_ok()` has none of these. The rule does not apply here.

The retry loop (`for attempt in 1 2 3`) is inside `ensure_modded_pdb()`, which already carries a full Tier 3 docblock including:
```
# Time: O(1) compute, up to 3 steamcmd validate calls (I/O-dominated)  Space: O(1)
```
That annotation accounts for the loop and the I/O calls. PASS.

#### Xvfb liveness check additions

The liveness check is a compound of simple conditionals and a single `kill -0` call. No loops. No recursion. No accumulation. Tier 1. No Big-O needed. The outer `main()` function has a Big-O annotation at its first line covering the enclosing scope:
```
# Time: O(1) compute; boot is I/O-dominated (steamcmd update + pdb restore up to 3 calls,
#       Proton game load, Xvfb socket poll bounded to 50 × 0.1s)  Space: O(1)
```
PASS.

#### `"M1 rollback"` milestone reference in comments

Two additions reference M1:
1. `# 1 = launch via AsaApiLoader (modded); 0 = vanilla ArkAscendedServer (M1 rollback)` (env default comment)
2. `# Both binaries accept identical args; ENABLE_ASAAPI=0 restores the M1 vanilla path with no rebuild.` (inline WHY comment in `main()`)

Per loaded memory `feedback_m1_m2_milestone_refs.md`: M1/M2 labels in WHY comments are allowed when they **name the current state** (the existing architectural constraint) rather than **promise future delivery**. The discriminating test: "does the phrase promise something will change, or explain why the current code works this way?"

Both uses name the current state: "M1 rollback" means the kill-switch restores the M1 vanilla binary path that already exists. "M1 vanilla path" names the current prior implementation that ENABLE_ASAAPI=0 falls back to. Neither promises a future change. Both describe current code properties.

**Verdict**: M1 label is architectural-context WHY, not a forward-delivery promise. Allowed per Phase-5/Round-3 ruling and stored memory. PASS.

---

### High-Yield Checks (systematic)

#### coding-style.md
- `any` / `as any` / `Record<string, any>`: N/A — shell script, no TypeScript
- Non-null assertions (`!`): N/A — shell script
- `enum` declarations: N/A — shell script
- `function` keyword: N/A — shell script
- Optional struct fields (`key?: T`): N/A — shell script
- DRY violations: The diff does not introduce 3+ similar repeated blocks. PASS.
- Magic numbers without provenance: `1024x768x24` — RESOLVED (geometry comment). `1048576` — provenance established (1 MiB comment above). `50` (Xvfb socket-poll cap) — documented inline as "cap ~5s — Xvfb is local and comes up in well under 1s." `0.1` (sleep 0.1s) — standard sub-second interval, documented in the timing comment. `3` (retry attempts) — documented in Flow step 2 ("up to 3 times") and echoed in runtime messages ("attempt ${attempt}/3…"). PASS.

#### verification.md
- Speculative code: `pdb_ok()` and the liveness check address confirmed failure modes documented in the surrounding comments (AsaApi logs "[critical] Failed to read pdb" on missing pdb; Wine logs "nodrv_CreateWindow" on missing display). Not speculative. PASS.
- Bug-fix Paper-Trace: No bug response in this diff — this is feature code (new ENABLE_ASAAPI kill-switch + pdb gate). Paper-Trace requirement does not apply (escape hatch: refactor/mechanical edit applies here as new feature). PASS.

#### no-duct-tape.md
- Banned phrases scan: No occurrences of "acceptable for now", "works in current state", "fine until we add", "we can revisit when", "only one consumer", "we'll make it configurable later", "this case can't happen yet", "intentional approximation" (without named cost), "minor — acceptable to leave", "good enough for the MVP" found in diff additions. PASS.
- Hardcoded list/switch assuming N=1: No such pattern. PASS.
- `it.skip` / `xit` / `xdescribe` without re-enable trigger: N/A — no test files. PASS.
- `// @ts-ignore` / `// @ts-expect-error` / `// eslint-disable`: N/A — no TypeScript. PASS.

#### comments.md
- Banned changelog phrases: Scan of all `+` lines — no occurrences of "Replaces", "Previously", "Used to", "Was", "Removed", "Eliminated", "Refactored from", "Migrated from", "Now uses", "Switched to", "Old version", "New version", "Fix for #N". PASS.
- `// TODO`, `// FIXME`, `// XXX`, `// HACK`, `// Phase Nx`, `// will do later`: None found. PASS.
- Commented-out code (`// const`, `// function`, `// import`): None found. PASS.
- Comments explaining WHAT instead of WHY: All new comments explain WHY (AsaApi's pdb SHA-256 requirement, Wine's nodrv_CreateWindow failure mode, steamcmd's unreliable exit code, Xvfb's async socket bind). PASS.
- Tier 2+ functions without Big-O: `ensure_modded_pdb()` has the annotation; `main()` has the annotation; `pdb_ok()` is Tier 1. PASS.
- Section banners (`// ===`, `// ---`): None found. PASS.
- Sentinel values without disambiguating comments: `ENABLE_ASAAPI=1` and `ENABLE_ASAAPI=0` — the env default comment and the `.env.*.example` comments both disambiguate exactly: `1 = launch via AsaApiLoader (modded); 0 = vanilla ArkAscendedServer (kill switch)`. PASS.

#### build-time-vs-runtime.md (project rule, loaded)
- `unzip` package installed in Dockerfile (build time): Correct placement — OS package, fixed dep, cached layer. 3-question test: Q1 no (no runtime state), Q2 no (package version doesn't change often), Q3 no (doesn't re-run on every boot). Dockerfile = correct. PASS.
- `pdb_ok()` / `ensure_modded_pdb()` in entrypoint: Correct placement — depends on runtime volume state (the pdb lives on the ark-game volume). 3-question test Q1 = yes → entrypoint. PASS.
- Xvfb launch in entrypoint: Correct — runtime, params from env, must re-run each boot. PASS.

#### Graveyard Corpses

**Test-Weakening (2026-04-28)**: N/A — no test files in diff. No fire.

**Silent Wrong-Output Bugs (2026-04-28)**: No `Intl.DateTimeFormat`, `parseFloat`, `new Date`, monetary values, or bid/ask field references. Shell script domain. No fire.

**Optional Object Fields (2026-04-30)**: N/A — shell script. No TypeScript interfaces. No fire.

**Ambiguous Sentinel Values (2026-04-30)**: `ENABLE_ASAAPI` sentinel values are disambiguated in both the env default comment and the `.env.*.example` comments. No fire.

**Integration Tests Racing (2026-05-12)**: N/A — no test files. No fire.

**Redundant State Duplicating Invariants (2026-05-13)**: No new state columns or boolean flags mirroring existing invariants. No fire.

**Executor Laziness (2026-05-18)**: No TODO/FIXME/HACK/XXX, no banned phrases, no changelog comments, no `throw new Error("not implemented")`, no `@ts-ignore`. No fire.

**Untracked Deferrals (2026-05-19)**: No deferral language ("defer", "punt", "revisit later", "leave for now", "skip for now") in diff additions. No fire.

**Build-Twice (2026-06-05)**: No "build the simple version now" / "rebuild it right later" language. No silent scope narrowing. No fire.

**Adversarial Reviewer Mutating Live File (2026-06-08)**: N/A — not a reviewer agent editing production code. No fire.

**Transaction-Rollback Isolation (2026-06-09)**: N/A — no test files. No fire.

**Hand-Listed Test Over Closed Enumerable Domain (2026-06-13)**: N/A — no test files. No fire.

**Plan-File Edit Deletes Sibling Phase (2026-06-15)**: N/A — no plan file changes in this diff. No fire.

---

### Required Fixes (BLOCK only)

None — no rule violations found.

---

### Project-vs-Global Overrides

None — no project rule contradicted a global rule on this diff.

---

### Bottom Line

Round-2 BLOCK cleared: `1024x768x24` has its provenance comment, `1048576` has its 1-MiB rationale, and the Xvfb liveness check is clean. This diff is compliant.
