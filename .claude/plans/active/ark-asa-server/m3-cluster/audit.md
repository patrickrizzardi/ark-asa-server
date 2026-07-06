---
name: "m3-cluster-audit"
plan-id: "ark-asa-server-m3-cluster"
metadata:
  type: "plan-audit"
---
# Audit trail — ark-asa-server-m3-cluster

Append-only. *How the plan got here.* Read by the AAR, auditors, and the execution conductor's
Step-3a / Step-0 reconcile; never by executors (they read the current-truth plan.md slice).

## Session log
- 46d42803-00ea-46b6-9744-f1dd992ba974 — 2026-06-22..2026-07-06 — plan authored + revised through Gate 4 approval.
- d7c269b0-2ae5-436b-b487-ea3d1b8ef35d — 2026-07-06 — Phase 1 initial execution (cluster wiring).
- 74db45a6-a185-4885-a2b3-f3045dba37fa — 2026-07-06 — Phase 1 fix round 1 (blocker: nested-mount permission bug; should-fix: ARK_CLUSTER_ID optionality, CLUSTER_DIR env wiring; minors).
- 74db45a6-a185-4885-a2b3-f3045dba37fa — 2026-07-06 — Phase 1 fix round 2 (ADR 0003 Decision item 3 corrected to the shallow-mount+symlink mechanism; CLUSTER_DIR charset/shape guard added; ARK_CLUSTER_ID FATAL message no longer echoes the raw value; FRAGO application — Dockerfile added to Files expected scope).
- 74db45a6-a185-4885-a2b3-f3045dba37fa — 2026-07-06 — Phase 1 fix round 3 (should-fix: CLUSTER_DIR containment/traversal guard closing the `..`-segment and ARK_DIR-collision holes; whole-plan stale-citation sweep; FRAGO application — `.claude/design-sources.md` + `.claude/rules/build-time-vs-runtime.md` added to frontmatter `files:`).
- 74db45a6-a185-4885-a2b3-f3045dba37fa — 2026-07-06 — Phase 1 fix round 4 (BLOCKER, reproduced live: round 3's regex-shape guard missed trailing/doubled-slash and bare-dot spellings colliding with ARK_DIR; fixed via `realpath -m` canonicalization; exhaustive whole-plan `entrypoint.sh` line-citation sweep, including Phase 2's un-executed anchors shifted +4).
- 74db45a6-a185-4885-a2b3-f3045dba37fa — 2026-07-06 — Phase 1 fix round 5 (BLOCKER, reproduced live: round 4's `realpath -m` followed the warm-boot CLUSTER_DIR symlink and false-rejected a legitimate restart; fixed via `realpath -m -s` lexical-only canonicalization; exhaustive whole-plan citation sweep across `entrypoint.sh`, `docker-compose.yml`, and `shop.md`).
- 74db45a6-a185-4885-a2b3-f3045dba37fa — 2026-07-06 — Phase 1 fix round 6, tightly-scoped 5-item final pass (should-fix, code-reviewer AND security via live reproduction: added a symlink-following parent-containment guard closing the intermediate-path-component escape the lexical-only guard couldn't see; 4 targeted citation fixes: entrypoint.sh query-string/`-flags` line refs, docker-compose.yml volume-block ref, shop.md §11 end-line; backfilled this audit's Session log for rounds 2-5).

## FRAGO log

## FRAGO 001 — 2026-07-06 — session-id: (conductor, execute-plan)
Base:      m3-cluster @ Phase 1
Trigger:   deviation-judge review of Phase 1's fix-round-1 diff found the executor touched `Dockerfile`
           (pre-create + chown of `/home/container/cluster-data`) to fix code-reviewer's blocker
           (nested-volume-mount permission bug: Docker auto-creates a missing mount-point directory as
           `root:root`, denying the non-root `container` user write access). `Dockerfile` was NOT in
           Phase 1's "Files (expected scope)" sub-list (plan.md ¶Phase 1), though it IS in the plan's
           top-level frontmatter `files:` list. deviation-judge verified independently (grepped
           entrypoint.sh for privilege-escalation paths — none found; confirmed `USER container` is set
           before ENTRYPOINT in the Dockerfile) that no entrypoint-only fix exists: a non-root runtime
           cannot retroactively chown a root-owned mount point it lacks permission to touch, and Docker's
           named-volume ownership seeding is a build-time-only mechanism. The fix is a 2-line addition
           exactly mirroring the already-audited pre-existing `arkserver` pre-create/chown pattern.
           Ruled: JUSTIFIED, risk-neutral (no new secrets, no new attack surface, no irreversible/destructive
           op added, mirrors an audited pattern) — recommend auto-apply + log, no signature required.
Changes:
  - Phase 1 "Files (expected scope)": CHANGED to ADD `Dockerfile`, because the blocker fix (shallow-mount
    + Dockerfile pre-create/chown + entrypoint symlink, mirroring `config_link`) structurally requires it —
    no entrypoint-only path closes the permission bug.
  - ¶1 Risk Assessment: NO CHANGE (risk-neutral; does not raise any residual).
Unchanged: everything not listed.
Override:  n/a — risk-neutral, no signature required.

## FRAGO 002 — 2026-07-06 — session-id: (conductor, execute-plan)
Base:      m3-cluster @ Phase 1
Trigger:   deviation-judge review of Phase 1's round-3 diff found `.claude/design-sources.md` is touched
           by Phase 1's own Step 8 ("Register the ADR `[locked]` in `.claude/design-sources.md`") and its
           Documentation Deliverables row, and genuinely was touched (the ADR 0003 `[locked]` row exists
           at `.claude/design-sources.md:9`) — but `.claude/design-sources.md` is absent from both Phase
           1's "Files (expected scope)" sub-list and the plan's top-level frontmatter `files:` list. Same
           shape of gap as FRAGO 001 (a planning-declaration omission, not executor drift — the plan's own
           Step 8 mandated the touch). The plan's frontmatter `files:` list is also separately missing
           `.claude/rules/build-time-vs-runtime.md`, which Phase 1's own Step 6 mandates amending.
           Ruled: JUSTIFIED, risk-neutral (declaration-only correction, no code/behavior change, mirrors
           FRAGO 001's already-ratified reasoning) — auto-apply + log, no signature required.
Changes:
  - Phase 1 "Files (expected scope)": CHANGED to ADD `.claude/design-sources.md`, because the phase's own
    Step 8 mandates registering the ADR there.
  - Plan frontmatter `files:` list: CHANGED to ADD `.claude/design-sources.md` and
    `.claude/rules/build-time-vs-runtime.md`, for the same reason (Steps 6 and 8 both mandate touching
    them, and both genuinely were touched).
  - ¶1 Risk Assessment: NO CHANGE (risk-neutral; declaration-only, does not raise any residual).
Unchanged: everything not listed.
Override:  n/a — risk-neutral, no signature required.

## FRAGO 003 — 2026-07-06 — session-id: (conductor, execute-plan)
Base:      m3-cluster @ Phase 2
Trigger:   deviation-judge review of Phase 2's diff found the plan's Steps text + 2 Acceptance
           Criteria + 1 Quality-gate item assumed the Permissions ArkApi plugin's config.json uses a
           NESTED `Mysql` key (mirroring ArkShop's schema), with the AC explicitly requiring
           `entrypoint.sh:436`'s `has("Mysql")` guard to fire and `jq .Mysql` to show the injected
           block on both plugin configs. The executor captured the REAL Permissions plugin config.json
           from an actual built image (`ark-asa:gate-check`) and found the real schema is FLAT
           (root-level `UseMysql`/`MysqlHost`/`MysqlUser`/`MysqlPass`/`MysqlDB`/`MysqlPort` — no nested
           `Mysql` object). `jq 'has("Mysql")'` on the real shipped default is `false`. deviation-judge
           independently re-verified this by reading both `config/permissions.config.json` (flat,
           confirmed) and `config/arkshop.config.json` (nested, confirmed), and confirmed
           `entrypoint.sh`'s `_inject_mysql_block()`/`inject_plugin_db_config()` correctly dispatch a
           `nested` vs `flat` schema per plugin, with the guard correctly renamed to
           `has("UseMysql")` (which fires true on the real seed) and a loud WARN added on guard-failure
           (a hardening over the plan's original silent-skip design). Following the plan's literal
           wording would have produced a guard that could never fire against the real plugin —
           reproducing the exact silent-DB-less-boot failure mode the AC was written to prevent.
           Ruled: JUSTIFIED (the plan's assumption was factually wrong, verified against real captured
           data), risk-neutral-to-lowering (the implementation is already correct and verified; the
           FRAGO only re-words criteria to match a working, hardened implementation — recommend
           auto-apply + log, no signature required).
Changes:
  - Phase 2 Acceptance Criteria ("DB inject still works on the real-file path... jq .Mysql... on the
    Permissions config" and "committed config/permissions.config.json seed contains a Mysql key so the
    has(\"Mysql\") guard at entrypoint.sh:436 fires"): CHANGED to reference the real flat schema —
    verification command becomes `jq '{UseMysql,MysqlHost,MysqlUser,MysqlPass,MysqlDB,MysqlPort}'` on
    the Permissions config, and the guard reference becomes `has("UseMysql")` at its current line in
    entrypoint.sh (re-verify the exact line at reword time, given known citation drift — see the
    existing Deferred follow-up below).
  - Phase 2 Quality-gate ("Permissions seed committed is secret-free... seed carries a Mysql block so
    the inject guard fires"): CHANGED to "...seed carries the flat UseMysql/Mysql* root-level keys so
    the has(\"UseMysql\") inject guard fires."
  - ¶1 Risk Assessment: NO CHANGE (risk-neutral-to-lowering; the working implementation already exists
    and is verified — this is a documentation correction, not a behavior change).
Unchanged: everything not listed.
Override:  n/a — risk-neutral, no signature required.

## FRAGO 004 — 2026-07-06 — session-id: (conductor, execute-plan)
Base:      m3-cluster @ Phase 2
Trigger:   deviation-judge + acceptance-verifier review of Phase 2's second fix round found that
           FRAGO 003's narrow scope (2 ACs + 1 QG item) correctly left FOUR named plan-text locations
           still describing the falsified nested-Mysql-schema assumption for the Permissions plugin:
           ¶1 Risk Assessment table row (references `has("Mysql")`/`:436`), Phase 2 Step 6 narrative
           ("the new Permissions seed must carry a `Mysql` block" — the literal OPPOSITE of ADR 0004's
           explicit warning against nesting it), the post-Step-6 CHECKPOINT ("`jq .Mysql` shows the
           injected block on both plugin configs"), and Phase 2 Step 12's regression-guard step text
           (same `jq .Mysql`-on-both assumption). The executor correctly declined to self-expand
           FRAGO 003's ratified scope to cover these (narrow-charter discipline) and surfaced them
           instead. acceptance-verifier independently judged this "should-fix, not a blocker — should
           close before Phase 2's status flips" because Step 6's stale wording is actively
           MISLEADING (tells a future reader to do the opposite of what the real plugin needs), not
           merely stale line-citation drift. Ruled: JUSTIFIED (same forcing reality FRAGO 003 already
           verified), risk-neutral (text-only correction, no behavior change — the working
           implementation is already correct) — auto-apply + log, no signature required.
Changes:
  - ¶1 Risk Assessment table row: CHANGED to describe the real flat schema / `has("UseMysql")` guard
    at its current line (re-verify exact line at reword time).
  - Phase 2 Step 6 narrative: CHANGED "the new Permissions seed must carry a `Mysql` block" → describes
    the real flat root-level keys and the `has("UseMysql")` guard.
  - Phase 2 post-Step-6 CHECKPOINT: CHANGED "`jq .Mysql` shows the injected block on both plugin
    configs" → schema-split verification command (nested for ArkShop, flat for Permissions).
  - Phase 2 Step 12 regression-guard text: CHANGED same `jq .Mysql`-on-both assumption → schema-split
    verification command, matching the Verification block FRAGO 003 already corrected.
  - Phase 2 Objective + Step 4 capture instruction: CHANGED (found by this FRAGO's own mandated
    "grep every remaining stale instance" clause, not separately named at ratification time — 6
    total instances fixed, not the 4 originally enumerated; Step 4's fix mattered most: the old text
    told an executor to "strip any Mysql secret block," which for the real flat schema means
    stripping the credential KEYS themselves and defeating the `has("UseMysql")` guard entirely —
    corrected to "blank the flat root-level credential VALUES, keep the keys").
  - ¶1 Risk Assessment (the risk SCORE, not the table row's description): NO CHANGE (risk-neutral;
    text-only, implementation already correct and verified).
Unchanged: everything not listed.
Override:  n/a — risk-neutral, no signature required.

## FRAGO 005 — 2026-07-06 — session-id: (conductor, execute-plan)
Base:      m3-cluster @ Phase 2
Trigger:   deviation-judge's third-pass review of Phase 2 found `.gitignore` is touched by Phase 2's
           own Step 8 ("remove the `plugins-config/**` line from `.gitignore:7`") and IS listed in
           Phase 2's own "Files (expected scope)" sub-list (plan.md:829) — and genuinely was touched
           (verified: the `plugins-config/**` entry is gone) — but `.gitignore` is absent from the
           plan's top-level frontmatter `files:` list. Identical shape to FRAGO 001 (Dockerfile) and
           FRAGO 002 (.claude/design-sources.md + .claude/rules/build-time-vs-runtime.md) — a
           planning-declaration omission, not executor drift. Ruled: JUSTIFIED, risk-neutral
           (declaration-only correction, no code/behavior change) — auto-apply + log, no signature
           required.
Changes:
  - Plan frontmatter `files:` list: CHANGED to ADD `.gitignore`, because Phase 2's own Step 8 mandates
    editing it and it genuinely was touched.
  - ¶1 Risk Assessment: NO CHANGE (risk-neutral; declaration-only, does not raise any residual).
Unchanged: everything not listed.
Override:  n/a — risk-neutral, no signature required.

**Also noted (non-blocking, folded into the existing deferred follow-up below, not a new FRAGO):**
two narrative/overview mentions in Phase 2's Context & Why (plan.md:86) and Research Findings
config-matrix (plan.md:126) still use loose "injected Mysql (block)" shorthand for Permissions.
deviation-judge judged these fine to leave — they drive no AC, no QG item, no step (unlike the six
FRAGO 003/004 locations, which drove actual verification commands and, in Step 4's case, an actively
dangerous instruction). Filed as an addendum to the plan.md line-citation drift deferral, since it's
the same class of "narrative accuracy, zero functional/AC impact" residue.

## Deferred follow-ups

## Deferred follow-up — 2026-07-06 — plan.md line-citation drift
- **WHAT**: plan.md's inline `entrypoint.sh:<N>` and `docker-compose.yml:<N>` line-number citations (in Background prose, Current-state anchors, Steps text, and Phase 2's un-executed anchors) have accumulated drift across 6 fix-loop rounds as each round's guard-code insertions shifted subsequent lines. Every "exhaustive sweep" attempt (rounds 4, 5, 6) fixed what it found but was re-staled by that same round's own edits, and each sweep's scope narrowed rather than widened.
- **WHY**: chasing full citation accuracy has cost 6 fix-loop rounds without ever closing it, while every reviewer (code-reviewer, acceptance-verifier, deviation-judge, graveyard-auditor across all 6 rounds) has independently confirmed the drift is PURELY navigational — it never affects any Acceptance Criterion's truthfulness, the delivered entrypoint.sh/docker-compose.yml code's correctness, or any security finding. Continuing to chase it now would be gold-plating an already-bounded, non-functional issue at the cost of further delaying Phase 1's actual commit.
- **COST**: one dedicated pass (est. 1 session) doing a genuinely complete grep-and-verify sweep of every `\.sh:[0-9]`, `\.yml:[0-9]`, `\.md:[0-9]` citation in the ENTIRE plan.md against the FINAL, post-all-rounds entrypoint.sh/docker-compose.yml/shop.md — done once, after all of Phase 1's code changes are truly frozen (not mid-fix-loop, which is why every prior attempt kept getting re-staled).
- **TRIGGER**: before Phase 2 begins execution (Phase 2's own Steps text cites several of these same files and would inherit any remaining drift), OR immediately if a future reviewer finds a citation error that DOES affect correctness/AC-honesty (upgrading this from cosmetic to a real should-fix).
