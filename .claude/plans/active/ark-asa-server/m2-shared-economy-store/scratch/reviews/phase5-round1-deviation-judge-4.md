# Deviation Judge — Full Report
## Plan: m2-shared-economy-store | Phase 5 | Deviation #4

**Deviation type**: scope (file touched outside expected scope)
**File**: `.claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md:146-174`

---

## Deviation Judge: m2-shared-economy-store Phase 5 Deviation #4

### Verdict: PASS

### Deviation summary (one line)
Executor appended Phase 5 execution decisions and coordinator probes to notes.md (the plan's churn log), which is outside the `Files (expected scope)` list in plan.md's Phase 5 block.

### Adversarial input(s) constructed

1. **Contract-level decision recorded only in notes.md**: The `plugins-config/` directory choice (separate from `./config/`) is a structural decision with downstream implications (operator mental model, bind-mount naming, mirror pattern). If it landed ONLY in notes.md and was absent from the plan.md Decision Ledger, it would be hidden from the plan contract and the reviewer gate.

2. **Secret value embedded in churn log**: The line `**ASA API Utils mod ID confirmed**: \`955333\`` records a numeric ID. If this were a password or credential rather than a public CurseForge mod ID, its presence in notes.md would constitute a secret-in-plaintext violation.

3. **"Harmless" behavioral observation that masks a contract gap**: The `deploy_plugins()` stash-restore warm-boot observation (notes.md:160) describes existing Phase 2 code as "redundant but harmless" — if that observation were quietly recording a known-broken or debt-carrying behavior, it would be disguising a contract-level issue as churn.

### Trace

**Input 1 — plugins-config/ directory choice:**

notes.md:156: "Plugin-config host home = `./plugins-config/` (separate from `./config/` which holds INI files)."

Cross-checking plan.md:

- plan.md:487 (Phase 5 Files expected scope): "`config/**` (or a new `plugins-config/` bind)" — the plan explicitly named the two alternatives and anticipated this decision as a Phase 5 execution-time choice.
- plan.md:493 (Phase 5 Step 1): "Decide the plugin-config host home: a host-bound dir (reuse `./config` or add `./plugins-config`) symlinked into `…/ArkApi/Plugins/<name>/` per the entrypoint.sh:62-69 pattern."

The plan explicitly deferred this to execution-time ("Decide at Phase 5") — this is exactly the kind of decision that belongs in notes.md as a churn-log resolution of an open execution question, not in the plan contract. The contract had already scoped both options. The notes entry records which one was chosen. That's churn, not a contract mutation.

**Input 2 — mod ID 955333:**

notes.md:153: `**ASA API Utils mod ID confirmed**: \`955333\``

This is a public CurseForge mod ID, not a credential. plan.md:137 explicitly pre-documented the question: "ASA API Utils CurseForge mod ID: needed at Phase 5 execution — I'll look it up then and record it." plan.md:495 (Step 3) says "Record the ID in plan notes." The notes entry fulfills a plan-directed requirement. Zero secret content; the value is a public game mod identifier that appears in ArkShop warning logs.

**Input 3 — deploy_plugins() stash-restore observation:**

notes.md:160: "`deploy_plugins()` stash-restore is now a warm-boot no-op for symlinked plugins... Left as-is (Phase 2 code, not in Phase 5 scope); the redundancy is harmless."

Cross-checking plan.md Decision Ledger #12 (plan.md:119): the stash-configure-restore pattern is already a contract-level decision with full rationale. The notes.md entry does not establish or change this decision — it observes that the existing implementation (already reviewed and passed in Phase 2) interacts benignly with the Phase 5 symlink approach. This is an execution observation about a pre-existing Phase 2 design, not a new contract-level decision hiding in churn.

**Coordinator probes (notes.md:164-166):**

Both probe entries are documented pre-gate investigations with commands, hypotheses, and REFUTED results. These are exactly what coordinator probes should be in a churn log — they are not decisions, not contracts, and contain no secrets. The format matches prior phases' established pattern exactly.

**ARKSHOP_DB_* fallback chain (notes.md:159):**

Records the `${VAR:-${MARIADB_VAR:-default}}` bash expansion form choice over `:=`. This is an implementation-detail legibility decision during Phase 5 coding, not a contract-level architectural choice. The plan (plan.md:494) specified the outcome ("inject DB secrets from MARIADB_*/dedicated ARKSHOP_DB_* env") without prescribing the bash expansion syntax. An execution-time syntax legibility choice belongs in churn.

**gitignore addition (notes.md:158):**

`plugins-config/**` added to `.gitignore` with `! .gitkeep` exception. This is a security hygiene implementation detail (prevent committing live injected creds). plan.md:530 (Quality Checklist) already states "Secrets only in gitignored `.env*`; entrypoint never logs the password." The gitignore coverage detail is an execution decision satisfying that checklist item, not a contract amendment.

### Where the fix overshoots (BLOCK only)

N/A — verdict is PASS.

### Strategies attempted

**Mixed inputs**: Constructed the most dangerous mix — a decision that LOOKS contract-level (the `plugins-config/` directory choice, which affects bind-mounts, operator UX, and README) — and traced whether it was also in plan.md. Result: plan.md:493 explicitly named it as a Phase 5 execution-time decision between two stated alternatives. notes.md records the resolution. No overshoot.

**Existing-primitive check (secret detection)**: Scanned all four new notes.md entries for credential patterns — passwords, tokens, keys. The only specific value recorded is `955333` (CurseForge mod ID), which is a public game identifier, plan-directed to be recorded there (plan.md:495 Step 3). The gitignore entry correctly documents that passwords are NOT stored in notes (they go into gitignored `.env`); notes.md is documenting the gitignore rule, not storing the creds.

**Second-caller / contract-mutation check**: Verified that none of the notes.md entries establish a new rule or constraint that would bind future phases. The `deploy_plugins()` warm-boot observation says "left as-is, harmless" — it closes a question, it doesn't open a new contract. Every entry either fulfills a plan-directed execution-time decision or records an observation about pre-existing code.

**Trace-through (churn vs. contract discriminator)**: Applied the discriminator: a decision belongs in plan.md's Decision Ledger when it is architectural, hard-to-reverse, or when future phases need to know the answer. All five notes.md decision entries are:
- Either explicitly deferred to Phase 5 execution in plan.md (plugins-config/ choice, mod ID)
- Or implementation-detail legibility/hygiene choices (bash expansion syntax, gitignore path, jq over sed)
None meet the "architectural / hard-to-reverse / future-phase-load-bearing" bar for Decision Ledger promotion.

### Bottom Line

Every entry in the hunk is exactly what the churn log is for: execution-time resolutions of plan-deferred choices, implementation-legibility decisions, and coordinator probe records. The adversarial inputs that would constitute a real BLOCK (contract decision hiding in churn, credential in plaintext) don't survive contact with the diff. PASS.
