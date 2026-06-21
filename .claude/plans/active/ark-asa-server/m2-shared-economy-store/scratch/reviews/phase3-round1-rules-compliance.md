# Rules Compliance Review: m2-shared-economy-store Phase 3 Round 1

### Verdict: BLOCK

### Diff Scope
- Files changed: 8
- Lines added/removed: +193 / -11
- Diff source: `git diff 1f9f1b7` (uncommitted changes relative to phase 2 commit)

### Rule Sources Loaded
- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded
- `~/.claude/memory/graveyard.md`: loaded
- `/home/patrick/docs/development/ark-asa/.claude/` project rules: N/A — no CLAUDE.md found at project root (scope: Docker/shell/docs project)
- `~/.claude/rules/build-time-vs-runtime.md` (project rule): loaded — directly applicable (Dockerfile + entrypoint diff)
- `~/.claude/memory/design-sources.md`: loaded — applicable because diff adds `.claude/design-sources.md`
- Conditional global rules: `~/.claude/rules/security.md` — not triggered (no auth/SQL/endpoint code); `~/.claude/rules/testing.md` — not triggered (no test files); `~/.claude/rules/migrations.md` — not triggered (no DB migration files)
- Domain memory files: none triggered by diff content

---

### Required Fixes (BLOCK — 1 finding)

1. **[entrypoint.sh:141]** WHAT: `# Time: O(1) skips; O(1) installs (single wine process invocation)` — `Space:` annotation is absent from the Big-O block.
   WHY: violates `~/.claude/rules/comments.md` Hard Rule 7 — *"Big-O on Tier 2+ functions — any function with loops, recursion, or accumulating data states time + space complexity. Format: `Time: O(n)  Space: O(1)`."* `install_vcredist` is Tier 3 (external I/O: runs `proton run`, writes DLLs + a marker to the volume) and accumulates data into the `missing` array (`missing+=(...)`). Both Time and Space are required. Only Time is present.
   FIX: Change the annotation line to: `# Time: O(1)  Space: O(1)` (the `missing[]` array is bounded to 3 elements — constant space; the two-case narrative "skips; installs" can be folded into an inline note after the standard format, or kept as a parenthetical: `# Time: O(1)  Space: O(1)  (fast-path exits early; install path runs once per prefix lifetime)`).

---

### Concerns (non-blocking)

1. **[.claude/rules/build-time-vs-runtime.md:28-34]** The explanatory note reads: *"the table row above was originally 'Dockerfile' when this rule was first written … the Dockerfile row was stale."* This is changelog-style framing (historical state of the rule, not a durable property of current architecture). However, the file is a `.md` file under `.claude/rules/` — the Executor Laziness graveyard corpse explicitly exempts *"Markdown documentation files inside `~/.claude/`, `docs/`, `README.md`, `CHANGELOG.md`"* and more broadly files matching `\.claude/` or `\.md$`. The exemption applies; this is non-blocking. Noted as a concern: a future maintainer reading the note may find the "was originally / was stale" framing unnecessarily historical. The load-bearing content — *"Q1 yes: prefix lives on the mounted ark-game volume → entrypoint"* — is durable. Consider whether the historical framing adds value beyond what ADR 0002's Context section already provides.

2. **[entrypoint.sh:141]** The Big-O format deviates from the mandated `Time: O(n)  Space: O(1)` single-line format by splitting into two sub-cases: `O(1) skips; O(1) installs`. This is the same finding as Required Fix #1 (missing Space:) — the fix resolves both the missing Space: and the non-standard two-case format together.

---

### Graveyard Corpse Scan

All corpses checked against diff content:

| Corpse | Match? | Disposition |
|---|---|---|
| Test-Weakening (2026-04-28) | No — no test files in diff | N/A |
| Silent Wrong-Output Bugs (2026-04-28) | No — no monetary/locale/timezone arithmetic | N/A |
| Optional Object Fields `?:` (2026-04-30) | No — shell/markdown, no TypeScript | N/A |
| Ambiguous Sentinel Values (2026-04-30) | No — no TypeScript sentinel fields | N/A |
| Integration Tests Racing (2026-05-12) | No — no test files | N/A |
| Redundant State Duplicating Invariants (2026-05-13) | No — no DB columns/schema | N/A |
| Executor Laziness (2026-05-18) | Scanned — banned changelog phrases present in `.md` files are EXEMPT per corpse's `\.md$` exemption; no TODOs/banned phrases in `.sh`/`Dockerfile` | CLEAR |
| Untracked Deferrals (2026-05-19) | No deferral language in code/shell additions | CLEAR |
| Build-Twice (2026-06-05) | No throwaway-then-rebuild pattern present | CLEAR |
| Adversarial Reviewer Mutating Live File (2026-06-08) | No GUARD-DROP markers | CLEAR |
| Transaction-Rollback Isolation (2026-06-09) | No test files | N/A |
| Hand-Listed Test Over Closed Enumerable Domain (2026-06-13) | No test files | N/A |
| Plan-File Edit Deletes Sibling Phase (2026-06-15) | `plan.md` diff: only SHA update + checkbox flip; no `### Phase N:` headers added or removed | CLEAR |

---

### Code-Specific Checks (shell/Dockerfile context)

**coding-style.md** — TypeScript-specific rules (no `any`, no `enum`, no `function` keyword, no `?:` fields) do not apply to shell/Dockerfile. No violations possible on this file set.

**no-duct-tape.md** — Scanned full diff for banned phrases. None found in `.sh` or `Dockerfile` additions. The explanatory note in `build-time-vs-runtime.md` uses historical framing but is exempt (`.md` file under `.claude/`).

**comments.md** — The `comments.md` frontmatter (`paths: **/*.sh` etc.) applies to `entrypoint.sh`. Violations:
- Hard Rule 7 (Big-O): `install_vcredist` is Tier 3 (external I/O: `proton run`, volume writes). Big-O present but incomplete — missing `Space:`. **BLOCK** (see Required Fix #1).
- Hard Rule 1 (no TODOs): clean.
- Hard Rule 2 (no changelog comments): clean in `.sh` file; the `.md` note is exempt.
- Hard Rule 3 (no commented-out code): clean.
- Hard Rule 6 (no section banners): clean.

**verification.md** — No speculative fixes introduced. All new code (install_vcredist) has a verified mechanical justification: the Proton prefix is volume-backed, installer cannot run at build time. This is a structural constraint, not a theory. No Paper-Trace required (this is a new feature implementation, not a bug fix).

**security.md** — Not triggered. No user input, no auth, no SQL, no secret logging. `proton run` invokes a pre-vetted installer baked in the image; no runtime-network-fetched execution.

**build-time-vs-runtime.md (project rule)** — The diff AMENDS this rule's table (VC++ row changed from Dockerfile → entrypoint) and the code matches. Consistency check:
- Table row: `entrypoint (volume-backed prefix — see note)` ✓
- Dockerfile: bakes installer at `/opt/vcredist/` (does NOT run the installer) ✓
- entrypoint.sh: `install_vcredist()` runs the installer against the volume prefix ✓
- ADR 0002: documents the rationale for the split ✓
- The 3-question test answer (Q1 yes → entrypoint) is correct for the volume-backed Proton prefix architecture ✓
- **Internally consistent. No contradiction.**

**design-sources.md format** — Checked against `~/.claude/memory/design-sources.md` format spec:
- All three entries use valid `- [locked] <path> — <domain note>` form ✓
- Comment lines valid (`# Format spec:`, `# An unjustified...`) ✓
- No parse errors ✓
- ADR 0002 registered in same diff that creates it ✓

---

### Project-vs-Global Overrides

None — no project rule contradicted a global rule on this diff.

---

### Bottom Line

One hard BLOCK: `entrypoint.sh:141` is missing its `Space:` annotation — `install_vcredist` is Tier 3 and accumulates a `missing[]` array, making Space: mandatory per Hard Rule 7. Everything else is clean: the rule-table amendment is internally consistent, the ADR is well-formed, the design-sources registry parses correctly, and no banned phrases hit any code file.
