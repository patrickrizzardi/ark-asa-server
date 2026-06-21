# Rules Compliance Review: m2-shared-economy-store — Cumulative (whole milestone)

### Verdict: PASS

### Diff Scope
- Diff command: `git diff 873509a..HEAD`
- Focus files reviewed: `entrypoint.sh`, `Dockerfile`, `docker-compose.yml`, `.env.prod.example`, `.env.test.example`, `.gitignore`, `README.md`, `docs/internal/decisions/0001-db-engine-mariadb.md`, `docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md`, `.claude/rules/build-time-vs-runtime.md`
- Ignored per instruction: `.claude/plans/**/scratch/**`, `.claude/state.md`, all `scratch/reviews/*`, plan/notes churn
- Stack: Bash + Docker + Markdown (no TypeScript — arrow/enum/`any`/optional-field rules N/A)
- Lines added/removed across focus files: ~+450 / -10 (entrypoint dominant at +411)

### Rule Sources Loaded
- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded (type-strictness rules N/A — no typed-language code; DRY + naming checked against bash)
- `~/.claude/rules/verification.md`: loaded (no bug-fix diff in scope requiring Paper-Trace; ADRs carry their own evidence)
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded (`.sh` is in paths glob → applies to entrypoint.sh)
- `~/.claude/memory/graveyard.md`: loaded (full file, both pages)
- `~/.claude/rules/security.md`: loaded (diff commits DB creds handling + .env templates → applicable)
- `~/.claude/rules/documentation.md`: loaded (README + ADRs touched → applicable)
- `~/.claude/rules/migrations.md`: loaded — N/A (no schema migration files; MariaDB schema is owned by ArkShop plugin, not this repo)
- `<project>/CLAUDE.md` (`~/docs/CLAUDE.md`): loaded — life-hub librarian rules, not code rules; N/A to this diff
- `<project>/.claude/rules/build-time-vs-runtime.md`: loaded (this file is BOTH a rule source AND in the diff — reviewed both ways)
- Project `rules/*.md` (other): N/A — only build-time-vs-runtime.md present
- Project memory / project graveyard: N/A — neither exists for ark-asa
- Conditional global rules (testing/integrations/branching/vue): none triggered — no tests, no third-party SDK code, no branch/PR work in focus set

### Required Fixes (BLOCK only — empty if PASS)
None — no rule violations found.

---

### Detailed findings (all clear — recorded for audit trail)

**comments.md — PASS.**
- entrypoint.sh comments are exemplary durable-WHY: every function explains the WHY/failure-mode, not the diff. No banned changelog phrases in code comments. The two grep hits for banned tokens were false positives — `"standard MySQL wire protocol"` (ADR prose describing current protocol, not "Migrated from") and `"seeded from the image default by setup_plugin_configs()"` (describes current data provenance, a load-bearing constraint, not "Was/Previously").
- Big-O (Hard Rule 7): every loop-bearing function carries a Time/Space annotation — `deploy_plugins` (O(n), n=plugin count), `ensure_modded_pdb` (O(1) compute + ≤3 I/O calls), `setup_plugin_configs` (O(p)), `install_vcredist` (O(1), missing[] bounded to 3), `main` (O(1), Xvfb poll bounded to 50×0.1s). The 5 `for` loops all sit inside annotated functions.
- No `// TODO` / `// FIXME` / `// HACK` / `// Phase N` in code. No commented-out code. No section banners. No author tags.
- Sentinel disambiguation: `ENABLE_ASAAPI` 0/1 meaning is stated inline; `MysqlPort` integer-coercion documented; pdb >1 MiB threshold documented as truncation-rejection sentinel. Clear.

**security.md — PASS.**
- DB password is never logged: `inject_plugin_db_config()` logs host/db/user but explicitly omits the password (`# Password intentionally omitted from the log line above`).
- Password passed to `jq --arg` (not interpolated into a jq filter) — injection-safe; the comment names the residual `/proc/<pid>/cmdline` transient exposure and justifies it as acceptable in a single-user game container. That's a named, bounded exposure with a real rationale, not a hidden risk.
- `.env.prod.example` / `.env.test.example` ship ONLY placeholder secrets (`use-a-long-random-*-secret`) with an explicit "replace them, never use as-is" warning. Real `.env*` files are gitignored (`!.env.*.example` allowlist). No real secret committed (`git ls-files | grep .env` → only `.example` templates).
- `plugins-config/**` gitignored (where the injected-password config.json lands) with only `.gitkeep` tracked. The injected runtime config never reaches git.
- MariaDB internal to compose network, no host port published — attack surface reduced (documented in ADR 0001 Consequences).
- Compose uses `${MARIADB_PASSWORD:?...}` fail-loud on missing required secret. Good.

**no-duct-tape.md — PASS.**
- "This is acceptable" in ADR 0002 (VC++ evergreen URL) is a *documented conscious decision* with a real named tradeoff: cost paid (rebuild on a later date may fetch a newer 14.x point release) vs cost avoided (vendoring/custom CDN infra). Backed by Microsoft's ABI-stability compatibility contract + a DLL-presence check that's version-agnostic. This is exactly the legitimate-deferral shape the rule permits, not a duct-tape framing.
- ADR 0001 backup deferral ("Deferred: economy DB backups") carries ALL FOUR required fields (what / why / cost-of-deferring / trigger) AND is anchored to a real capability-ledger row (`Backups: economy DB (mysqldump) | m4-ops-tooling | planned | …`) that exists in the committed ledger, owned by a future roadmap-sequenced milestone. Untracked-Deferrals corpse does NOT fire — tracker is queryable and named.
- SQLite-vs-MariaDB rejection explicitly *invokes* the build-twice anti-pattern (no-duct-tape §11) as the REASON to build MariaDB right the first time — correct application, not a violation.
- No "for now" / "good enough" / "works in current state" framings in any focus file.

**graveyard.md corpse scan — no matches.**
- Build-Twice (2026-06-05): ADR 0001 reasons FROM this corpse to reject the throwaway SQLite path — anti-match.
- Untracked Deferrals (2026-05-19): backup deferral is tracked in the ledger — anti-match.
- Executor Laziness (2026-05-18): no smuggled TODOs, no stub throws, no changelog comments, no unjustified suppressions.
- Redundant State (2026-05-13): no belt-and-suspenders lock columns; the `.vcredist-installed` / `.installed` markers are explicitly documented as *fast-path hints* with DLL/file presence as the source-of-truth arbiter — not duplicate invariants (matches the cache exemption).
- Test-Weakening, Transaction-Rollback, Enumerable-Domain, Plan-Phase-Deletion, Silent-Wrong-Output, Adversarial-Guard-Drop, FS-race: N/A — no tests, no TS unions, no plan-phase edits in focus set.

**build-time-vs-runtime.md (project rule, edited in-diff) — PASS, Rule 00 compliant.**
- The VC++ row flip (Dockerfile → entrypoint) + the added "Note on VC++ redist placement" is a legitimate in-place correction of a stale row, with the full rationale living in ADR 0002 (one authoritative home). The note POINTS at the ADR rather than duplicating the reasoning — exactly Rule 00 behavior. The 3-question test result is shown consistently in the rule, the Dockerfile comments, and ADR 0002 — no drift.

---

### Concern (non-blocking — NOT a Required Fix)

**README.md crossed the documentation.md §(e) growth predicate.**
- `grep -c "^## " README.md` = **9** (was 6 at base `873509a`; M2 added Database, Shared store, Roadmap-expansion → 3 new top-level sections). The primary threshold is ≥6 → the README has formally outgrown a flat file and §(e) signals "promote to a `docs/` tree" (extract sections into `docs/internal/architecture/`, build a `docs/README.md` index, leave README as an entry point).
- Why this is a **Concern and not a BLOCK**: documentation.md §(e) frames the predicate as a *signal that surfaces the docs offer*, not a hard gate that fails a diff. The project already has a `docs/internal/decisions/` tree (the two ADRs), so it has partially adopted the structured layout. Promotion is an offer to the owner, not a mechanical violation of a `[locked]` contract. Flagging per Rule 11 (surface it, don't deflect) — the coordinator/Patrick decides whether to promote now or carry it into M3/M4 doc work. It is not a single-token rule breach the executor must fix to land M2.

### Project-vs-Global Overrides
None — no project rule contradicted a global rule on this diff. `build-time-vs-runtime.md` is a project-specific *addition* (no global counterpart), not a contradiction; its in-diff edit is consistent with global Rule 00.

### Bottom Line
Cleanest milestone diff I've audited, chief — durable WHY comments, Big-O on every loop, password kept out of the logs and out of git, ADRs with real named tradeoffs, deferral anchored to a live ledger row. Zero blocks. One Concern: the README hit 9 `##` sections and tripped the docs-tree promote signal — owner's call, not a gate. Ship M2.
