# Rules Compliance Review: m2-shared-economy-store Phase 5 Round 2

### Verdict: PASS

### Diff Scope
- Files changed: 2 (entrypoint.sh, docker-compose.yml)
- Lines added/removed: +172 / -2 (approximate; excludes plan.md + state.md per instructions)
- Diff source: `git diff 4f19274` — working tree vs Phase-4 BASE commit (plan.md + state.md prior-phase chore deltas excluded per coordinator instruction)

---

### Rule Sources Loaded
- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded (Bash + Docker — TypeScript-specific rules do not apply; DRY and magic-number rules are language-agnostic and apply to shell)
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded
- `~/.claude/memory/graveyard.md`: loaded (all 12 corpses reviewed; see Graveyard section)
- Project `CLAUDE.md`: N/A — no `CLAUDE.md` at `/home/patrick/docs/development/ark-asa/CLAUDE.md`
- Project `rules/build-time-vs-runtime.md`: loaded — governs Dockerfile-vs-entrypoint placement decisions
- Conditional global rules: `security.md` loaded — diff touches DB password injection and credential env var handling
- Domain memory files: N/A — no domain-matched topic files beyond graveyard

---

### Required Fixes (BLOCK only — empty if PASS)

None — no rule violations found.

---

### Round 1 BLOCK Resolution — Confirmed RESOLVED

**Round 1 BLOCK**: `entrypoint.sh` had the 6-line jq `.Mysql.*` filter block duplicated verbatim at two call sites (ArkShop + Permissions) inside `inject_plugin_db_config()`. Violation: `~/.claude/rules/coding-style.md` DRY rule.

**Round 2 verification** (grep evidence):
```
entrypoint.sh:63  — _inject_mysql_block() {    ← defined ONCE
entrypoint.sh:135 — _inject_mysql_block "${arkshop_cfg}"   ← called for ArkShop
entrypoint.sh:143 — _inject_mysql_block "${perms_cfg}"     ← called for Permissions
```
The jq filter block appears exactly once — inside `_inject_mysql_block`. Both ArkShop and Permissions call the helper. The duplication is gone. **BLOCK is resolved.**

---

### Full Scan — New Violations in Changed Regions

#### coding-style.md (DRY, magic numbers, function style)

- **DRY**: `_inject_mysql_block` is the single authoritative jq caller. No duplicated blocks in the new diff. PASS.
- **Magic numbers**: `955333` (ASA API Utils CurseForge mod ID) is used in the mod-deduplication logic at entrypoint.sh:~420. It carries a comment explaining it: `# ASA API Utils (CurseForge mod 955333) is required by ArkShop — without it AsaApi logs "Singleton not found" and ArkShop's economy hooks don't fire.` The magic number is a third-party external ID; the comment names its origin and required purpose. Passes the magic-number provenance check. PASS.
- **Function style**: Bash — arrow-function rule does not apply. PASS.
- **Type strictness**: Bash/Docker — no type system. PASS.

#### comments.md

**Big-O annotations on Tier-2+ functions** (Hard Rule 7):

| Function | Has Loop? | Big-O Present | Format correct? |
|---|---|---|---|
| `setup_plugin_configs()` | Yes — `for plugin in ArkShop Permissions` | `Time: O(p) where p = plugin count (2 in practice — ArkShop + Permissions)  Space: O(1)` | ✓ states the variable |
| `_inject_mysql_block()` | No loops | `Time: O(1)  Space: O(1)` | ✓ correct for constant op |
| `inject_plugin_db_config()` | No loops (calls helper twice) | `Time: O(1)  Space: O(1)` | ✓ correct |

All three new Tier-2+ functions carry Big-O annotations. PASS.

**Durable-not-changelog comment check**: Scanned all added comment lines (`^+.*#`) for banned changelog phrases: `Replaces`, `Previously`, `Used to`, `Was`, `Removed`, `Eliminated`, `Refactored from`, `Migrated from`, `Now uses`, `Switched to`, `Old version`, `New version`. Zero matches. PASS.

**TODO/FIXME/HACK/XXX in code**: Zero instances. PASS.

**Commented-out code**: Zero instances. PASS.

**New `_inject_mysql_block` comment block** — durable WHY scan:
The function comment explains:
1. Why `--arg` is used (safe — not evaluated as jq filter expression).
2. Why the `|| { … exit 1; }` error handler is load-bearing (`set -e` doesn't fire on a non-final position in an `&&` list — this is a non-obvious bash pitfall and a legitimate WHY comment per `comments.md` "concurrency/ordering that would surprise a casual reader").
3. Side effect (atomic via mktemp + mv).

All WHY-not-WHAT. PASS.

**`inject_plugin_db_config` comment block** — durable WHY scan:
- Documents WHY password is passed via `--arg` vs inline interpolation (security, injection safety).
- Documents WHY password is omitted from the log line (`# Password intentionally omitted from the log line above.`).
- Fail-fast rationale: "a partially-configured ArkShop connects to the wrong host or fails silently, which is harder to diagnose than an explicit boot-time fatal." Durable WHY. PASS.

**`docker-compose.yml` comment block** (new env section): `# ArkShop → MariaDB connection. The entrypoint falls back from ARKSHOP_DB_* to MARIADB_*, so passing the MARIADB_* vars here is all that is needed in the common case. Override ARKSHOP_DB_* only when ArkShop connects as a different DB user or host.` Durable architectural reason. PASS.

#### no-duct-tape.md

**Banned phrase scan** (case-insensitive on diff additions): `acceptable for now`, `works in current state`, `fine until we add`, `we can revisit when`, `only one consumer`, `we'll make it configurable later`, `this case can't happen yet`, `intentional approximation`, `minor — acceptable to leave`, `good enough for the MVP`. Zero matches. PASS.

**Hardcoded plugin list** (carryover concern from round 1): `for plugin in ArkShop Permissions` in `setup_plugin_configs()` remains a hardcoded N=2 list. Evaluated same as round 1: the Big-O annotation explicitly names `p = plugin count (2 in practice)`, so the scope is honest, not a hidden assumption. No "we'll make it configurable later" framing. Not a duct-tape violation. CONCERN (see below).

#### verification.md

**Paper-Trace requirement**: This change is a refactor (DRY extraction), not a bug fix. Paper-Trace does not apply. PASS.

**Speculative code**: No new guards or checks added beyond what the round-1 diff already carried. The `|| { … exit 1; }` guard on jq is explained with a concrete bash-behavioral reason (`set -e` non-final-position non-firing). Not speculative. PASS.

#### security.md (triggered by DB password handling)

**Password never logged**: `inject_plugin_db_config()` echoes: `host=${ARKSHOP_DB_HOST}, db=${ARKSHOP_DB_NAME}, user=${ARKSHOP_DB_USER}`. Password variable is absent. Explicit code comment: `# Password intentionally omitted from the log line above.` grep for `echo.*${ARKSHOP_DB_PASS}` or `echo.*${MARIADB_PASSWORD}` in new additions — zero matches. PASS.

**Error messages** (the three `Required:` / `defaults to` lines in the fail-fast block): These print VAR NAMES as operator hints, not the credential values. `ARKSHOP_DB_PASS` as a name is safe. PASS.

**jq --arg injection**: Password reaches jq via `--arg pass "${ARKSHOP_DB_PASS}"` — treated as a string literal by jq, never evaluated as a jq filter. Safe. PASS.

**Secret committed**: `.env.prod` and `.env.test` are gitignored (confirmed from round 1). No change to .gitignore in this diff. PASS.

#### build-time-vs-runtime.md (project rule)

No changes to Dockerfile in this diff. All new functions are in entrypoint.sh (runtime). Three-question test on new entrypoint content:
- `setup_plugin_configs()` + `inject_plugin_db_config()`: Q1 (depends on runtime volume/env) = yes → entrypoint. Correctly placed. PASS.

---

### Graveyard Corpse Scan — All 12 Entries

**Test-Weakening (2026-04-28)**: No test files in diff. N/A.

**Silent Wrong-Output Bugs (2026-04-28)**: Detection patterns (`Intl.DateTimeFormat`, `toLocaleDateString`, `parseFloat`, paired-field flips) — none match bash/jq context. The `tonumber` coercion of ARKSHOP_DB_PORT is validated up front with `^[0-9]+$` before reaching jq. PASS.

**Optional Object Fields (2026-04-30)**: TypeScript-only scope. No TS files in diff. N/A.

**Ambiguous Sentinel Values (2026-04-30)**: No new sentinel values introduced that require disambiguation. `ARKSHOP_DB_PASS:-` (empty default) is explained and guarded by fail-fast check. PASS.

**Integration Tests Racing on Shared Filesystem (2026-05-12)**: No test files in diff. N/A.

**Redundant State Duplicating Existing Invariants (2026-05-13)**: No new DB columns or model state. N/A.

**Executor Laziness — Smuggled TODOs, Duct-Tape Framings, Changelog Comments (2026-05-18)**: Full scan on diff additions for all detection patterns. Zero matches on any of: `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP`, `PLACEHOLDER`, `@ts-ignore`, `@ts-expect-error`, `eslint-disable`, banned changelog phrases, banned duct-tape phrases. PASS.

**Untracked Deferrals (2026-05-19)**: Scanned for `defer`, `revisit later`, `come back to`, `leave for now`, `skip for now`, `do later`, `for later`, `will add later`, `will do later`, `we'll revisit`. Zero matches. PASS.

**Build-Twice — Cheap-Now-Then-Rebuild-Right-Later (2026-06-05)**: No throwaway-version language in diff. Plugin config injection is built correctly once using extracted helper. PASS.

**Adversarial Reviewer Mutating Live Production File (2026-06-08)**: No `GUARD-DROP` or adversarial-test patterns. N/A.

**Transaction-Rollback Isolation Silently Neuters Concurrency Tests (2026-06-09)**: No test files in diff. N/A.

**Hand-Listed Test Over Closed Enumerable Domain (2026-06-13)**: No test files in diff. N/A.

**Plan-File Edit Deletes Sibling Phase's Section (2026-06-15)**: Excluded per scope instruction (plan.md chore deltas ignored). N/A.

---

### Project-vs-Global Overrides
None — no project rule contradicted a global rule on this diff.

---

### Concerns (non-blocking)

1. **entrypoint.sh: `setup_plugin_configs()` hardcodes `for plugin in ArkShop Permissions`** — same concern from round 1, not introduced in this round's diff. The function Big-O comment honestly names `p = 2 in practice`. Adding a third plugin with a Mysql block requires a code change here. Not duct tape (no deferred promise, no hidden assumption), but worth a comment: `# Add plugins here when they need a host-bound config dir` on the for loop. Non-blocking repeat concern; carry if coordinator wants it addressed in this phase.

---

### Bottom Line

Round 1 BLOCK resolved — `_inject_mysql_block` is defined exactly once and called at both ArkShop and Permissions sites. New comment blocks are durable-WHY, all three new Tier-2+ functions carry Big-O annotations, password never surfaces in logs. Clean diff. PASS.
