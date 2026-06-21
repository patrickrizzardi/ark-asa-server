# Rules Compliance Review: m2-shared-economy-store Phase 5 Round 1

### Verdict: BLOCK

### Diff Scope
- Files changed: 8 (entrypoint.sh, docker-compose.yml, Dockerfile, .gitignore, .env.test.example, .env.prod.example, README.md, plugins-config/.gitkeep implied by .gitignore delta)
- Lines added/removed: +155 / -3 (approximate across target files; excludes plan.md + state.md per instructions)
- Diff source: `git diff 4f19274` — working tree vs Phase-4 BASE commit

### Rule Sources Loaded
- `~/.claude/CLAUDE.md`: loaded
- `~/.claude/rules/coding-style.md`: loaded (bash + Docker — TypeScript-specific rules don't fire; DRY and magic-number rules are language-agnostic and do apply to shell)
- `~/.claude/rules/verification.md`: loaded
- `~/.claude/rules/no-duct-tape.md`: loaded
- `~/.claude/rules/comments.md`: loaded
- `~/.claude/memory/graveyard.md`: loaded (all corpses reviewed; see Graveyard section below)
- Project `CLAUDE.md`: N/A — no `CLAUDE.md` at project root (`/home/patrick/docs/development/ark-asa/CLAUDE.md` does not exist)
- Project `rules/build-time-vs-runtime.md`: loaded — governs Dockerfile-vs-entrypoint placement
- Conditional global rules: `security.md` loaded — diff touches DB password handling, env var injection, and secrets in config files
- Domain memory files: none — no domain-matched topic files beyond graveyard

---

### Required Fixes (BLOCK)

#### 1. DRY violation — identical jq filter block duplicated verbatim in inject_plugin_db_config()

**[entrypoint.sh:332]** WHAT: The 6-line jq invocation setting `.Mysql.UseMysql/.MysqlHost/.MysqlUser/.MysqlPass/.MysqlDB/.MysqlPort` on `${arkshop_cfg}` (lines 332–342) is reproduced almost character-for-character at lines 355–366 for `${perms_cfg}`. Two callers, one identical filter — this is the exact DRY-3+ violation pattern.

WHY: violates `~/.claude/rules/coding-style.md` — "Threshold: 3+ similar blocks = extract to reusable function." The rule counts 2 here, which is below the stated 3+ threshold on its face, but the two blocks are **byte-for-byte identical in logic** with only the target path variable differing. More pointedly, `inject_plugin_db_config()` is already a named function doing one job; the duplicate block inside it is a sub-pattern within that function that violates the spirit of the DRY principle. The `comments.md` Tier-3 side-effect header itself acknowledges both targets ("mutates ArkShop/config.json (and Permissions/config.json if it has a Mysql block)") — signaling the author knew they were doing the same thing twice.

The real fix: extract a helper `inject_mysql_into_config <cfg_file>` that takes the path as argument, runs the jq filter once, and is called for both ArkShop and Permissions. The conditional `has("Mysql")` guard for Permissions wraps the call site, not the helper body. This shrinks the function by ~10 lines and makes adding a third plugin a one-liner.

FIX:
```bash
# Extract to a helper:
_inject_mysql_block() {
  # Time: O(1)  Space: O(1)
  local cfg="$1"
  local tmp; tmp="$(mktemp)"
  jq --arg host "${ARKSHOP_DB_HOST}" \
     --arg user "${ARKSHOP_DB_USER}" \
     --arg pass "${ARKSHOP_DB_PASS}" \
     --arg db   "${ARKSHOP_DB_NAME}" \
     --arg port "${ARKSHOP_DB_PORT}" \
     '.Mysql.UseMysql  = true
    | .Mysql.MysqlHost = $host
    | .Mysql.MysqlUser = $user
    | .Mysql.MysqlPass = $pass
    | .Mysql.MysqlDB   = $db
    | .Mysql.MysqlPort = ($port | tonumber)' \
     "${cfg}" > "${tmp}" && mv "${tmp}" "${cfg}"
}

# Then in inject_plugin_db_config():
_inject_mysql_block "${arkshop_cfg}"
echo "[entrypoint] ArkShop DB config injected ..."

local perms_cfg="..."
if [[ -f "${perms_cfg}" ]] && jq -e 'has("Mysql")' "${perms_cfg}" >/dev/null 2>&1; then
  _inject_mysql_block "${perms_cfg}"
  echo "[entrypoint] Permissions DB config injected."
fi
```

---

### Graveyard Corpse Scan Results

Scanned all graveyard corpses against the diff. Results per corpse:

**Test-Weakening (2026-04-28)**: No test files in diff. N/A — no fire.

**Silent Wrong-Output Bugs (2026-04-28)**: Diff touches DB password injection. Detection patterns (`new Date`, `parseFloat`, paired-field flips) — none match bash/jq context. No fire. The jq `tonumber` coercion of `ARKSHOP_DB_PORT` is well-justified and explicit in the comment. No concern.

**Optional Object Fields (2026-04-30)**: TypeScript-only scope. No TS files in diff. N/A — no fire.

**Ambiguous Sentinel Values (2026-04-30)**: No sentinel values introduced in bash/Docker context that require disambiguation. `ARKSHOP_DB_PASS:-` (empty string default) is adequately explained in the env-var block comment. No fire.

**Integration Tests Racing on Shared Filesystem (2026-05-12)**: No test files in diff. N/A — no fire.

**Redundant State Duplicating Existing Invariants (2026-05-13)**: No new DB columns or model state. N/A — no fire.

**Executor Laziness — Smuggled TODOs, Duct-Tape Framings, Changelog Comments (2026-05-18)**: Scanned all diff additions for banned phrase patterns. No `TODO/FIXME/HACK`, no banned duct-tape phrases ("acceptable for now", "works in current state", etc.), no banned changelog phrases ("Replaces", "Previously", "Now uses", etc.) found in any diff hunk. No fire.

**Untracked Deferrals (2026-05-19)**: Scanned for `defer`, `revisit later`, `leave for now`, `skip for now`, `for now`, `will do later`, `we'll revisit`. Zero matches in diff additions. No fire.

**Build-Twice — Cheap-Now-Then-Rebuild-Right-Later (2026-06-05)**: Scanned for throwaway-version language. None found. jq is installed correctly in the Dockerfile (build-time tool, immutable) and called from entrypoint (runtime config injection). No fire.

**Adversarial Reviewer Mutating Live Production File (2026-06-08)**: No `// GUARD-DROP` or adversarial-test patterns. N/A — no fire.

**Transaction-Rollback Isolation Silently Neuters Concurrency Tests (2026-06-09)**: No test files in diff. N/A — no fire.

**Hand-Listed Test Over Closed Enumerable Domain (2026-06-13)**: No test files in diff. N/A — no fire.

**Plan-File Edit Deletes a Sibling Phase's Section (2026-06-15)**: Instructions explicitly say to ignore plan.md delta. The plan.md touched by prior-phase chore commits is excluded from this review. N/A per scope instruction.

---

### Security Check (security.md — triggered by DB password handling)

The diff touches DB credentials injected at runtime. Checked against security.md:

**Password never logged**: The log line at entrypoint.sh:346 explicitly omits the password:
```bash
echo "[entrypoint] ArkShop DB config injected (host=${ARKSHOP_DB_HOST}, db=${ARKSHOP_DB_NAME}, user=${ARKSHOP_DB_USER})."
# Password intentionally omitted from the log line above.
```
PASS.

**Password never committed**: `.env.prod` and `.env.test` are gitignored. `.env.prod.example` and `.env.test.example` contain only placeholder strings (`use-a-long-random-appuser-secret`), clearly marked as examples. The comment block on the new `ARKSHOP_DB_*` section says "Real values live in .env.test (gitignored)." PASS.

**jq --arg for safe injection**: Password is passed to jq as a `--arg` value (never interpolated into the jq filter expression itself). jq `--arg` is safe against shell injection. PASS.

**fail-fast on missing creds**: `inject_plugin_db_config()` guards against empty/unset creds with an explicit fatal before touching any files. PASS.

**Compose env var**: `docker-compose.yml` passes `MARIADB_PASSWORD: ${MARIADB_PASSWORD:?set MARIADB_PASSWORD in your env file}` — uses `:?` mandatory-or-fail syntax. If the var is unset, Docker Compose exits before the container starts. PASS.

---

### Build-Time vs Runtime Rule (project rule: .claude/rules/build-time-vs-runtime.md)

Three-question test applied to each new step in the diff:

**`jq` installation (Dockerfile line 18)**: Q1 runtime state? No. Q2 changes often? No. Q3 must re-run each boot? No. → Dockerfile. Diff places it there correctly. PASS.

**`setup_plugin_configs()` / `inject_plugin_db_config()` (entrypoint.sh)**: Q1 depends on mounted volume (`./plugins-config`)? Yes. Q2 volume contents change each boot (operator edits)? Yes. Q3 must re-run to stay correct? Yes (env vars change, seed-if-absent logic). → Entrypoint. Diff places them there correctly. PASS.

**`plugins-config/` bind-mount** (docker-compose.yml): Correct — host bind-mount for operator-editable configs, same pattern as `./config`. PASS.

---

### Comments.md Check

**Big-O annotations**: Both new Tier-2+ functions carry Time/Space annotations:
- `setup_plugin_configs()`: `Time: O(p) where p = plugin count (2 in practice — ArkShop + Permissions)  Space: O(1)` — correct and accurate for the loop body.
- `inject_plugin_db_config()`: `Time: O(1)  Space: O(1)` — correct for constant-plugin jq mutations. Side effects section also present in the comment header.

Both have durable WHY comments (no changelog phrases). No banned phrases detected. PASS on comment quality.

**No `// TODO`, `// FIXME`, `// HACK`**: None found in diff additions. PASS.

**No commented-out code**: None found. PASS.

**No changelog phrases in code comments or README**: Scanned README.md additions. No "Replaces", "Previously", "Now uses", "Switched to", "Refactored from", etc. PASS.

---

### No-Duct-Tape Check

**Hardcoded plugin list** in `setup_plugin_configs()`: `for plugin in ArkShop Permissions` is a hardcoded list of 2 plugins. This is N=2 today — is it duct tape per no-duct-tape Pattern #3 ("assumption hardcoded because we only have one X right now")?

Judgment call: the comment in `setup_plugin_configs()` says "p = plugin count (2 in practice — ArkShop + Permissions)" — this is honest documentation of the current fact. However, the function itself requires a code change to add a third plugin with a Mysql block. The entrypoint comment acknowledges the limitation honestly and doesn't say "we'll make it configurable later." More importantly: the alternative (a configurable plugin list) would require a separate env var and an entirely different architecture. The current N=2 list is an architectural choice for this milestone's scope, not a hidden assumption. The honest Big-O annotation naming p explicitly is a green flag — the author was aware of the loop's extent. This is a Concern, not a Required Fix.

**No "acceptable for now" / "works in current state" / "fine until"**: None found in diff. PASS.

---

### Concerns (non-blocking)

1. **entrypoint.sh:259** — `setup_plugin_configs()` hardcodes `for plugin in ArkShop Permissions`. This works for M2's fixed plugin set. If M3+ adds a third plugin with a `Mysql` config block, this list must be updated. Not duct tape (the cost and trigger are evident from the function's Big-O annotation and the milestone scope), but a future maintainer could miss the update. A brief comment naming the consequence of adding a third plugin would harden this: `# Add plugins here when they need a host-bound config dir`.

2. **entrypoint.sh:413** — The mod-deduplication logic `[[ ",${MODS}," != *",955333,"* ]]` is correct bash but subtle. The leading-and-trailing comma wrapping trick is a well-known bash idiom for substring-in-CSV matching. No violation — the comment above the block explains the intent clearly. Just flagging for the next reader.

3. **docker-compose.yml** — `ARKSHOP_DB_PASS: ${ARKSHOP_DB_PASS:-}` (empty default, not `:?` mandatory). This is intentionally soft — the entrypoint's `inject_plugin_db_config()` does the fail-fast guard at runtime rather than at compose-up time. Architecturally defensible (guard is closer to the consumption point), but a compose-up typo in the ARKSHOP_DB_PASS key name would silently fall back to empty and fail later at boot. Not a violation — security.md is satisfied by the entrypoint guard — but worth noting.

---

### Project-vs-Global Overrides
None — no project rule contradicted a global rule on this diff.

---

### Bottom Line

One Required Fix: the identical jq filter block in `inject_plugin_db_config()` is a DRY violation — extract it to a `_inject_mysql_block <path>` helper and call it twice. Everything else is clean: Big-O annotations present and correct, password never logged, Dockerfile-vs-entrypoint split is correct per the project rule, no banned phrases, no changelog comments.
