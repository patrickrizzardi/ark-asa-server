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

## Deferred follow-ups

## Deferred follow-up — 2026-07-06 — plan.md line-citation drift
- **WHAT**: plan.md's inline `entrypoint.sh:<N>` and `docker-compose.yml:<N>` line-number citations (in Background prose, Current-state anchors, Steps text, and Phase 2's un-executed anchors) have accumulated drift across 6 fix-loop rounds as each round's guard-code insertions shifted subsequent lines. Every "exhaustive sweep" attempt (rounds 4, 5, 6) fixed what it found but was re-staled by that same round's own edits, and each sweep's scope narrowed rather than widened.
- **WHY**: chasing full citation accuracy has cost 6 fix-loop rounds without ever closing it, while every reviewer (code-reviewer, acceptance-verifier, deviation-judge, graveyard-auditor across all 6 rounds) has independently confirmed the drift is PURELY navigational — it never affects any Acceptance Criterion's truthfulness, the delivered entrypoint.sh/docker-compose.yml code's correctness, or any security finding. Continuing to chase it now would be gold-plating an already-bounded, non-functional issue at the cost of further delaying Phase 1's actual commit.
- **COST**: one dedicated pass (est. 1 session) doing a genuinely complete grep-and-verify sweep of every `\.sh:[0-9]`, `\.yml:[0-9]`, `\.md:[0-9]` citation in the ENTIRE plan.md against the FINAL, post-all-rounds entrypoint.sh/docker-compose.yml/shop.md — done once, after all of Phase 1's code changes are truly frozen (not mid-fix-loop, which is why every prior attempt kept getting re-staled).
- **TRIGGER**: before Phase 2 begins execution (Phase 2's own Steps text cites several of these same files and would inherit any remaining drift), OR immediately if a future reviewer finds a citation error that DOES affect correctness/AC-honesty (upgrading this from cosmetic to a real should-fix).
