# Rules Compliance Review: m2-shared-economy-store Phase 3 Round 2

## Verdict: PASS

---

## Diff Scope

- Files changed: 5 (in-scope); bookkeeping files (`plan.md`, `notes.md`, `state.md`) excluded per coordinator scope note
- Lines added/removed: +213 / -1 (in-scope files)
- Diff source: `git diff 1f9f1b7 -- Dockerfile entrypoint.sh .claude/rules/build-time-vs-runtime.md docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md .claude/design-sources.md`

---

## Rule Sources Loaded

- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded (not applicable — shell/Dockerfile/markdown, no TypeScript in diff)
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded (applies to `.sh` via frontmatter `**/*.sh` path)
- `~/.claude/memory/graveyard.md`: loaded (all corpses scanned)
- `<project>/CLAUDE.md`: N/A — project CLAUDE.md is at `/home/patrick/docs/CLAUDE.md` (docs root, covers the life hub, not this project)
- `<project>/rules/build-time-vs-runtime.md`: loaded (sole project rule file; matched by diff content)
- Conditional global rules: `security.md` — N/A (no endpoints/auth/SQL in diff); `testing.md` — N/A (no test files in diff); `integrations.md` — N/A (no third-party SDK patterns); `branching.md` — N/A (no PR/branch work in diff)
- Domain memory files: none triggered (no Sequelize, no TypeScript, no trading patterns in diff)

---

## Round-1 BLOCK Resolution: Confirmed

Round-1 flagged `[entrypoint.sh:141]` — `install_vcredist`'s Big-O block was missing the `Space:` annotation (Hard Rule 7 / comments.md line 361).

**Status: RESOLVED.** The diff now contains:

```
# Time: O(1)  Space: O(1)  — missing[] bounded to 3 elements (constant)
# Side effects: writes VC++ DLLs into ${STEAM_COMPAT_DATA_PATH}/pfx/ on the volume.
#               Writes .vcredist-installed marker to the volume dir.
```

Format matches Hard Rule 7 precisely: `Time: O(n)  Space: O(1)` (double-space separator, variable named, side effects documented). The annotation correctly categorizes this as O(1) because `missing[]` is bounded to exactly 3 elements (constant), not N. Satisfies the rule. BLOCK cleared.

---

## Required Fixes (BLOCK only)

None — no rule violations found.

---

## Full Compliance Scan

### coding-style.md

Not applicable. Diff contains only shell script (`.sh`), Dockerfile, and markdown (`.md`). No TypeScript/JavaScript patterns to check. Rules about `any`, `enum`, `?:` optionality, discriminated unions, etc. have no surface here.

### comments.md (applies to `entrypoint.sh` via `**/*.sh` path)

**Banned changelog phrases**: Scanned all `+#` comment lines added to `entrypoint.sh`. No instances of: `Replaces`, `Previously`, `Refactored from`, `Now uses`, `Switched to`, `Migrated from`, `Old version`, `New version`, `Removed`, `Eliminated`, `Fix for #N`. Clean.

**`// TODO` / `// FIXME` / `// HACK` / `// XXX`**: None present in any added lines. Clean.

**Commented-out code**: None. No `# const`, `# function`, `# import` pattern added. Clean.

**WHAT vs WHY comments**: All added comments in `install_vcredist` describe WHY (rationale for DLL-presence check vs bare marker, rationale for `|| rc=$?` capture, side-effects declaration). No WHAT comments visible. Clean.

**Big-O annotation (Hard Rule 7)**: `install_vcredist` has no loops or recursion — it's a linear sequence of `[[ -f ... ]]` file-existence checks and `missing+=()` array accumulation. The array is bounded to exactly 3 elements (constant set: `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`). The executor classified this correctly as O(1) and annotated it. The annotation is present, well-formatted, and correct. Hard Rule 7 satisfied.

**Section banners**: None added. Clean.

**Author tags**: None added. Clean.

**Magic numbers**: `3010` and `1638` appear in comments — both have parenthetical explanation inline: `3010 (reboot suppressed)` and `1638 (another version already installed)`. These are Windows MSI installer return codes; their meanings are stated at the point of use and in the log output. No unexplained magic numbers.

### no-duct-tape.md (scanned all diff additions across all in-scope files)

Scanned for all banned phrases:
- "acceptable for now" — not present
- "works in current state" — not present
- "fine until we add X" — not present
- "we can revisit when Y happens" — not present
- "current code only has one consumer" — not present
- "we'll make it configurable later" — not present
- "this case can't happen yet" — not present
- "intentional approximation" — not present
- "minor — acceptable to leave" — not present
- "good enough for the MVP" — not present

**Note on "This is acceptable" in ADR 0002**: The phrase "This is acceptable: Microsoft's 14.x redistributable is ABI-stable and backward-compatible by their compatibility contract" appears in `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`. This is NOT the banned phrase "acceptable for now" — it is followed by a colon and a concrete technical justification (ABI stability contract). The ADR also documents the named tradeoff explicitly (cost paid: a rebuild on a different date may produce a marginally different binary; cost avoided: custom CDN/vendoring infrastructure). This meets the no-duct-tape standard for a documented deferral with named costs.

### verification.md

No bug-fix code in this diff. The `install_vcredist` function is new functionality, not a bug fix. No Paper-Trace requirement triggered.

**rc-capture pattern correctness**: The `|| rc=$?` construct is the canonical bash idiom for capturing an exit code under `set -e` without aborting. `local rc=0` initializes to success; `proton run ... || rc=$?` captures non-zero exit codes; `if [[ ${rc} -ne 0 ]]; then ... fi` logs benign non-zero codes. The subsequent DLL-presence check is the actual success arbiter, as stated in comments. This is correct, verified shell behavior — not speculative.

### security.md

N/A. No new endpoints, auth paths, SQL, or secrets handling in diff. Not triggered.

### testing.md

N/A. No test files in diff. Not triggered.

### build-time-vs-runtime.md (project-local rule)

**3-question test compliance for new Dockerfile RUN block** (the VC++ curl download):
1. Depends on runtime state (mounted volumes, env vars, network reachability)? — **No.** The curl simply downloads to `/opt/vcredist/`, which is an image layer path, not a volume. This is correct Dockerfile placement.
2. Does the thing it produces change often? — **No.** The installer is frozen at build time.
3. Must it re-run on every container start? — **No.** It's a one-time bake.

All three: No → Dockerfile. Placement is correct per the 3-question test. The installer binary itself is correctly in the image; the _installation into the prefix_ (which needs the volume) is correctly in the entrypoint.

**Table row correction in build-time-vs-runtime.md**: The `Wine prefix + VC++ redist install` row was updated from `Dockerfile` to `entrypoint (volume-backed prefix — see note)`. The note correctly explains the architectural reason (Q1 yes: prefix is on the mounted volume). This is a correction of a stale rule, not a rule violation.

**Changelog phrasing in the note ("was originally", "was stale")**: The note in `.claude/rules/build-time-vs-runtime.md` contains: "the table row above was originally 'Dockerfile' when this rule was first written" and "the Dockerfile row was stale." These phrases describe history. However:
- `.claude/rules/` is explicitly exempted from the graveyard Executor Laziness corpse's changelog-phrase check ("Markdown documentation files inside `~/.claude/`, `docs/`, `README.md`, `CHANGELOG.md`")
- `comments.md` frontmatter paths (`**/*.ts`, `**/*.sh`, etc.) do NOT include `**/*.md`, so the formal banned-phrase rule does not apply to this markdown file
- This is consistent with the agent memory feedback entry `feedback_ledger_prose_not_code_comments.md` and `feedback_shell_comment_in_md_doc.md`

No violation.

### graveyard.md — corpse scan

All corpses scanned against the diff:

1. **Test-Weakening (2026-04-28)**: N/A — no test files in diff.
2. **Silent Wrong-Output Bugs (2026-04-28)**: N/A — no `Intl.DateTimeFormat`, `toLocaleDateString`, `parseFloat`, paired-field refs in diff.
3. **Optional Object Fields `?:` (2026-04-30)**: N/A — no TypeScript in diff.
4. **Ambiguous Sentinel Values (2026-04-30)**: N/A — no typed fields with sentinel semantics in diff. The shell array `missing=()` is a standard accumulator, not a sentinel.
5. **Integration Tests Racing on Shared Filesystem Paths (2026-05-12)**: N/A — no test files.
6. **Redundant State Duplicating Existing Invariants (2026-05-13)**: N/A — no DB schema changes.
7. **Executor Laziness — Smuggled TODOs, Duct-Tape Framings, Changelog Comments (2026-05-18)**: Scanned. No TODO/FIXME/HACK/XXX in code-file additions. No duct-tape framings. No changelog phrases in `.sh` additions (only in `.md`/doc files, which are exempted by the corpse's Scope exemption). Clean.
8. **Untracked Deferrals (2026-05-19)**: Scanned for: `defer`, `deferred`, `punt`, `postpone`, `revisit later`, `come back to`, `leave for now`, `skip for now`, `do later`, `will do later`, `we'll revisit`. None present in any in-scope added lines. Clean.
9. **Build-Twice — Cheap-Now-Then-Rebuild-Right-Later (2026-06-05)**: N/A — no throwaway vs proper implementation pattern in diff. The design is building the right thing (bake installer, deploy at runtime per the project rule).
10. **Adversarial Reviewer Mutating LIVE Production File (2026-06-08)**: N/A — no `// GUARD-DROP` or adversarial mutation patterns in diff.
11. **Transaction-Rollback Isolation Silently Neuters Concurrency Tests (2026-06-09)**: N/A — no test files.
12. **Hand-Listed Test Over Closed Enumerable Domain (2026-06-13)**: N/A — no test files.
13. **Plan-File Edit Deletes Sibling Phase's Section (2026-06-15)**: N/A — plan.md excluded from scope per coordinator scope note; not checked here.
14. **Silent Error Swallowing (stub)**: N/A — stub corpse has no Detection checks (explicitly noted as skip-by-reviewers).

No corpse matches.

---

## Project-vs-Global Overrides

None — no project rule contradicted a global rule on this diff.

---

## Bottom Line

Round-1 BLOCK resolved correctly. Big-O annotation is present with correct format, rc-capture is canonical bash, zero banned phrases or changelog comments in any in-scope code file. PASS.
