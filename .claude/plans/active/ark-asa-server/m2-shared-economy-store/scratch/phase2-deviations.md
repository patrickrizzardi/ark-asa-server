# m2-shared-economy-store Phase 2 Deviations — captured 2026-06-20 (round 2)

D_count: 3

## Scope Deviations (verbatim from executor report)

- **Round-2 scope edits (Fix 4, orchestrator-directed)**: `plan.md` Decision Ledger row #12 added + `notes.md` duplicate trimmed to a one-line pointer — re-homing the clean-replace decision to its durable contract home (judge #1 BLOCK remedy). Plus the original round-1 scope deviation persists: `notes.md` carries the Step-1 channel-resolution record.

## Approach Deviations (verbatim from executor report)

- **Deviation D1 (stash-rm-cp clean-replace)**: plan said `rsync --delete` (or remove-then-copy); executor used stash-rm-copy. Unchanged in round 2 except a comment reword at entrypoint.sh:119 (Fix 3). judge PASSed round 1.
- **Deviation D2 (versioned URLs + PERMISSIONS_VERSION doc-pin)**: versioned `?version=${ARG}` URLs; round-2 Fix 1 added an explicit doc-pin comment to the unused `PERMISSIONS_VERSION` ARG (judge #3 BLOCK remedy).

## Resolved spawn list (orchestrator's parsed view)

### Deviation #1 (was judge #2 — PASS round 1)
- **type**: approach
- **rationale**: rsync may not be present in the parkervcp/steamcmd:proton base image; under set -euo pipefail a missing rsync binary aborts with a confusing error; stash-restore uses only cp/rm (POSIX builtins guaranteed present) and achieves the same stale-file elimination guarantee
- **diff hunks**: entrypoint.sh:55-126
- **judge identity hash**: 2b1f102b5f6ac7af936ba840db69874306451bc3
- **carry status**: re-judged — hunk file entrypoint.sh changed (line-119 comment reword, Fix 3); identity hash unchanged from round 1

### Deviation #2 (was judge #3 — BLOCK round 1, fix applied)
- **type**: approach
- **rationale**: ?version=latest always fetches current stable regardless of ARG value — confirmed live that ark-server-api.com supports ?version=<N> for both resources; using the ARG in the URL makes the pin mechanically enforced rather than just documented; PERMISSIONS_VERSION is a doc-pin only (round-2 comment), drives no URL
- **diff hunks**: Dockerfile:34, Dockerfile:36, Dockerfile:48
- **judge identity hash**: 5e8b7babf6dc332f7371197fafaab4fdfaec93b1
- **carry status**: re-judged — round-1 BLOCK (dead PERMISSIONS_VERSION pin); Fix 1 added explicit doc-pin comment; verify resolution

### Deviation #3 (was judge #1 — BLOCK round 1, fix applied)
- **type**: scope
- **rationale**: clean-replace decision re-homed from notes.md churn to plan.md Decision Ledger row #12 (durable contract); notes.md retains channel-resolution facts + a one-line pointer per Rule 00 one-home
- **diff hunks**: .claude/plans/active/ark-asa-server/m2-shared-economy-store/plan.md:119, .claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md:76
- **judge identity hash**: c176b2d9d216c673b395f84c17a64ea0ea380003
- **carry status**: re-judged — round-1 BLOCK (decision homed in churn); Fix 4 moved it to plan.md row #12; verify resolution
