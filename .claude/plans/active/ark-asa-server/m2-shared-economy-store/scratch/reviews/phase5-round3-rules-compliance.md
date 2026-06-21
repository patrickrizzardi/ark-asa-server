# Rules Compliance Review: m2-shared-economy-store Phase 5 Round 3

### Verdict: PASS

### Diff Scope
- Files changed: 1 (entrypoint.sh)
- Lines added/removed: +158 / -0 (net additions only in the two new regions + Xvfb block)
- Diff source: `git diff 4f19274 -- entrypoint.sh` (working tree; plan.md + state.md chore deltas excluded per coordinator instruction)

---

### Rule Sources Loaded

- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded (Bash script — type rules largely N/A; DRY and naming still apply)
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded
- `~/.claude/memory/graveyard.md`: loaded (all corpses, pages 1–2)
- Project `CLAUDE.md`: N/A — not present at project root (docs/development/ark-asa/)
- Project `rules/build-time-vs-runtime.md`: loaded (only project rules file; scope matches entrypoint)
- Conditional global rules: `~/.claude/rules/security.md` — triggered (diff adds env-var credential handling and jq injection of DB credentials)
- Domain memory files: none triggered (no Sequelize, no ML, no Vue)

---

### Required Fixes (BLOCK only)

None — no rule violations found.

---

### Concerns (non-blocking)

1. **[entrypoint.sh:268]** The comment `(it did — that's the bug this shape fixes)` is borderline changelog-adjacent. The constraint it anchors (don't symlink the whole dir, DLL would vanish) is genuinely durable, and `comments.md` escape-valve covers it ("load-bearing constraint the next maintainer must not 'clean up'"). However, "this shape fixes" is the kind of language that references the diff event rather than the current-code property. Consider trimming to just the failure-mode description without the parenthetical: `# AsaApi would log "Plugin … does not exist" and fail to load it.` The WHY is already implicit: the DLL being present is why we only symlink config.json. Minor.

2. **[entrypoint.sh:358]** The inline `# Fail fast on missing/empty creds — no half-configured shop.` comment at line 358 repeats the same WHY already stated in the function-header JSDoc block (lines 346–347: `# Fail-fast on missing/empty creds: a partially-configured ArkShop connects to the wrong host / or fails silently`). The header is the canonical home; the inline at line 358 is DRY noise. Not a Hard Rule violation (the inline has WHY reasoning — "no half-configured shop" — not just WHAT), but it's a second home for the same concern, which Rule 00 disfavors within a single function's comments. Could be dropped.

3. **[entrypoint.sh:467]** `rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true` — the `|| true` after `2>/dev/null` is belt-and-suspenders: `2>/dev/null` already suppresses stderr, and `rm -f` already returns 0 on missing files. The `|| true` adds no safety value; it's dead. Not a rule violation, but the extra idiom could mislead a reader into thinking `rm -f` can fail non-zero here (it can't on missing paths with `-f`). Harmless, but noisy.

---

### Specific Checks Performed

#### comments.md — Durable-not-changelog + Banned Phrases

Scanned all `+` diff lines:
- `# Now uses` / `# Previously` / `# Replaces` / `# Removed` / `# Refactored from` / `# Migrated from` / `# Switched to` / `# Old version` / `# New version` — **NONE** found. The one `grep -i "now"` hit was `"is now at the host-bound path via the symlink"` — present-tense current-state description, not a changelog phrase. Passes.
- `// TODO` / `# TODO` / `# FIXME` / `# HACK` / `# XXX` — **NONE** found.

#### comments.md — Big-O annotation (Hard Rule 7, Tier 2+ functions)

- `setup_plugin_configs()` — contains a `for` loop (Tier 2+). Annotation present at function header: `# Time: O(p) where p = plugin count (2 in practice — ArkShop + Permissions)  Space: O(1)`. Variable named, current N documented. **PASS.**
- `_inject_mysql_block()` — single jq call + mv (Tier 1/2 boundary). Annotation present: `# Time: O(1)  Space: O(1)`. **PASS.**
- `inject_plugin_db_config()` — O(1) calls (1–2 conditional `_inject_mysql_block` invocations, no loops). Annotation present: `# Time: O(1)  Space: O(1)`. **PASS.**

#### no-duct-tape.md — Banned Phrases

Grep pass over all `+` lines (case-insensitive) for: "acceptable for now", "works in current state", "fine until we add", "we can revisit when", "only one consumer", "configurable later", "can't happen yet", "intentional approximation", "minor — acceptable to leave", "good enough for the MVP". **NONE** found.

#### security.md — Password never logged

`ARKSHOP_DB_PASS`:
- Passed to `jq --arg pass` — value is a command-line arg (transiently in `/proc/PID/cmdline`; acceptable in a single-user game container, per the explicit comment at line 341–343).
- Checked for emptiness with `-z "${ARKSHOP_DB_PASS}"` in the fail-fast guard — the value is NOT echoed, only its variable name appears in the error message.
- The injection success log line at line 381 explicitly omits the password: `host=…, db=…, user=…` with the comment `# Password intentionally omitted from the log line above.`
- **Security check: PASS.** No password value is logged.

#### build-time-vs-runtime.md (project rule)

All three new functions (`setup_plugin_configs`, `inject_plugin_db_config`, `_inject_mysql_block`) run in the entrypoint:
- They depend on env vars (Q1 = yes → entrypoint correct).
- They depend on the volume-backed plugin dirs (Q1 = yes → entrypoint correct).
- They must re-run each boot (Q3 = yes → entrypoint correct).

`rm -f /tmp/.X0-lock /tmp/.X11-unix/X0` similarly:
- Depends on runtime state (`docker compose restart` behavior, /tmp persistence) — entrypoint correct.

**PASS** — no build-time-vs-runtime rule violations.

#### Graveyard — Corpse Pattern Matching

- Test-Weakening: no test files in diff — N/A.
- Silent Wrong-Output: no monetary paths, no `Intl.DateTimeFormat`, no paired-field swaps — N/A.
- Optional Object Fields (`?:`): Bash, not TypeScript — N/A.
- Ambiguous Sentinel Values: variables clearly named (`ARKSHOP_DB_HOST`, `ARKSHOP_DB_PASS`, etc.); `dest="${cfg}"` is not a sentinel. — N/A.
- Integration Tests Racing: no tests in diff — N/A.
- Redundant State: no DB columns, no model fields — N/A.
- Executor Laziness (TODOs, duct-tape, changelog comments): full grep pass completed — NONE found.
- Untracked Deferrals: full deferral-language grep pass — NONE found.
- Build-Twice: no throwaway build pattern — N/A.
- Adversarial Reviewer Mutation / GUARD-DROP: no `// GUARD-DROP` comments, no guard predicate removals — N/A.
- Transaction-Rollback Isolation: no tests in diff — N/A.
- Hand-Listed Test Over Enumerable Domain: no tests — N/A.
- Plan-File Edit Deletes Sibling Phase: plan.md not in this diff scope — N/A.

---

### Project-vs-Global Overrides

None — no project rule contradicted a global rule on this diff.

---

### Bottom Line

Round 3 holds the Phase 5 PASS. The two runtime fixes (`setup_plugin_configs` file-only symlink, `_inject_mysql_block` readlink-f resolution, Xvfb stale-lock cleanup) are structurally clean: Big-O annotated, durable WHY comments, no banned phrases, password never touches a log line. Three minor style concerns flagged, none blocking.
