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
- ec937db0-96ea-4c68-9108-58dafc4fd5f6 — 2026-07-06 — Phase 3 Steps 1-5 (checkpoint segment): `docker-compose.yml` refactored to `&ark-server`/`&ark-common-env` YAML anchors defining `the-center` + `genesis`; `.env.test.example`/`.env.prod.example` per-map port vars added; `README.md` Cluster section added. Validated via `docker compose config` only (no dell access). Checkpointed at the phase's own planned post-Step-5 boundary; `handoff-phase-3.md` written; resume-at `phase-3/step-6` (dell deploy + Patrick in-game testing — gated on Patrick, not this executor).
- 8c4255f4-dc90-4012-9ecd-287cd28f9794 — 2026-07-06 — Phase 3 follow-up (still checkpointed at `phase-3/step-6`, no new steps attempted): applied FRAGO 006 to `plan.md` Phase 3 Step 1 text (rewrote the stale single-anchor prose to describe the real `&ark-server`/`&ark-common-env` two-anchor structure, verified against the live `docker-compose.yml`); fixed the stale `docker compose restart the-center` (singular) reference in `docs/internal/design/economy/shop.md:278` → `the-center genesis`, matching the same staleness class already corrected in `README.md` this phase. No code touched; `docker-compose.yml` unchanged. Left uncommitted for the conductor's CONFIRM-mode commit gate.
- (conductor, live dell session) — 2026-07-06/07 — Phase 3 Steps 6-7 live dell deploy + first-pass in-game testing. Deployed all 4 map services (The Center, Genesis, Ragnarok, Island — the latter two added as extra playable maps outside M3's own transfer/economy scope, per Decision Ledger #10). Two real, live-discovered-and-fixed bugs found along the way, both committed and pushed:
  1. **`ArkAscendedServer.pdb` missing on fresh installs** (Genesis's first-ever boot) — confirmed as an acknowledged upstream Wildcard regression (build 89.38/buildid 24058917 shipped without it — AsaApi/AsaApi#61), not a permanent depot gap. Fixed with a buildid-keyed cross-map pdb cache on the shared `ark-cluster` volume (`entrypoint.sh` commits `5dfa227`/`2b6c2a8`/`115cffa`) plus a crash-loop fix (hold-and-scream instead of `exit 1` under `restart: unless-stopped`). Live-verified end to end, including on Ragnarok/Island's genuinely fresh installs (both pulled from cache automatically, zero manual intervention).
  2. **dell's real in-use `.env` file (not `.env.test`/`.env.prod` — a plain `.env`, pre-dating all M3 work) had no `ARK_CLUSTER_ID` set at all**, so every map had been launching with cluster args silently omitted this whole time. Added a real cluster ID to that file (`docker compose up -d`, not `restart`, needed to actually pick it up — `restart` does not re-read `.env`).
  3. **Real root cause of "travel to another map always rejoins the current one"**, found after ruling out cluster-id, GameUserSettings.ini, and dell's iptables/docker-proxy NAT config (all independently verified correct via live `ss`/`iptables -t nat -L` checks): every instance's engine bound its actual UDP game socket to `7777` regardless of `SERVER_PORT` — `entrypoint.sh`'s launch string only ever set `Port=` inside the quoted map-URL (read later by ARK's own game code, same path RCON uses — which is why RCON was always correct per-instance), never as a standalone `-Port=` command-line switch, which is what the engine's low-level socket subsystem actually binds from. Fixed by adding `-Port=${SERVER_PORT}` as its own flag (commit `666f151`). Verified live via `ss` inside each container post-fix: Genesis/Ragnarok now genuinely listen on their own ports (7779/7781), not 7777.
  All three fixes are pushed to `main` and live on dell. Cluster travel confirmed working by Patrick after fix 3. Remaining Phase 3 ACs (checkable transfer artifact, move-not-dupe, GUS integrity across concurrent shutdown, shared RCON points, loot/shop config consistency, `ENABLE_ASAAPI=0` rollback) still need their evidence filled in via further in-game testing before Phase 3's own AC checkboxes and the plan's final cumulative gate can close.

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

## FRAGO 006 — 2026-07-06 — session-id: (conductor, execute-plan)
Base:      m3-cluster @ Phase 3
Trigger:   deviation-judge review of Phase 3 Steps 1-5 found the executor built the compose refactor
           as TWO YAML anchors (`&ark-server` for build/depends_on/restart/logging + `&ark-common-env`
           for the shared env block) with each service's `volumes:`/`ports:` fully restated, whereas
           Phase 3 Step 1's literal text described ONE anchor (`&ark-server`) capturing "the shared env
           block, the shared volume mounts" as well. deviation-judge independently verified the
           underlying YAML mechanics rather than taking the executor's word for it: `<<:` merge-key
           semantics are non-recursive on mapping-key collision (a service's own `environment:` key
           fully replaces, never selectively merges with, the anchor's `environment:`) and are undefined
           for sequences entirely (`volumes:`/`ports:` have no merge mechanism at all) — so a single flat
           anchor could never have delivered per-service env overrides or partial volume/port
           inheritance as Step 1's prose implied. The two-anchor structure is the only mechanically
           possible way to deliver Step 1/2's actual intent (shared bulk, minimal per-service diffs),
           and `docker compose config` (verified both with `ARK_CLUSTER_ID` unset and set) confirms both
           services resolve correctly. Ruled: JUSTIFIED (the plan's single-anchor phrasing was
           mechanically unexecutable as literally worded, verified against real YAML/Compose merge-key
           semantics, not assumed), risk-neutral (no behavior change, no new secret/attack surface,
           output already verified correct) — auto-apply + log, no signature required. (Process note,
           not part of this FRAGO's substance: the executor initially self-characterized this as "a
           recorded decision, not a deviation" rather than surfacing it distinctly for this FRAGO path;
           the conductor is filing it through the standard mechanism here, matching FRAGO 001-005.)
Changes:
  - Phase 3 Step 1: CHANGED "Refactor `the-center` into a YAML anchor `&ark-server` capturing the
    shared bulk (build/image, depends_on, the shared env block, the shared volume mounts…)" → describes
    the real two-anchor structure: `&ark-server` for build/image/depends_on/stop_grace/restart/logging,
    and a SEPARATE `&ark-common-env` anchor for the shared env block (merged one level deeper inside
    each service's own `environment:` mapping, since `<<:` cannot selectively merge a nested mapping
    key each service also declares); volumes/ports are fully restated per service (YAML `<<:` has no
    merge mechanism for sequences).
  - ¶1 Risk Assessment: NO CHANGE (risk-neutral; the working implementation is already correct and
    verified via `docker compose config`, this is a plan-text correction only).
Unchanged: everything not listed.
Override:  n/a — risk-neutral, no signature required.

## Deferred follow-ups

## Deferred follow-up — 2026-07-06 — ArkAscendedServer.pdb missing from Wildcard build 89.38 (confirmed upstream regression, NOT a permanent depot gap)
- **WHAT**: `entrypoint.sh`'s `ensure_modded_pdb()` (the AsaApi plugin-loader prerequisite check) assumes a missing `ArkAscendedServer.pdb` can be restored via up to 3 `steamcmd validate` retries. Live-tested for the first time ever during Phase 3's dell deploy (every prior environment was an already-seeded volume, never a from-scratch install): Genesis's brand-new `ark-game-genesis` volume FATALed after 3 validate attempts. The retry loop is provably inert — each attempt re-runs the byte-identical `+app_update ... validate` command the initial install already ran, so 3 retries of a command that already failed once can never succeed (confirmed via `entrypoint.sh:284-285`: no different invocation, no different flags). Additionally, the container has no distinct failure-handling for the resulting FATAL: `restart: unless-stopped` just re-runs the identical failing cycle forever (confirmed live — it re-entered the same 3-attempt FATAL loop a second time before being stopped manually).
- **WHY (corrected root cause — verified via `steamcmd +app_info_print` AND AsaApi's own upstream tracker, not assumed)**: Initially suspected as a permanent Steam-depot omission (only one Windows depot exists for app 2430930, `2430931`, 13.5GB, no separate debug-symbols depot in the public or test-realm branches) — that part is true, but the REAL cause is narrower and time-boxed: **AsaApi's own maintainer (`Pelayori`) confirmed on [GitHub issue #61](https://github.com/ArkServerApi/AsaApi/issues/61), dated 2026-07-05 (one day before this deploy): "89.38 has no PDB file, therefore API won't function — roll back to 89.31 until they release a new update that fixes the problems."** Our installed buildid is `24058917` (confirmed via `appmanifest_2430930.acf` on both volumes) — matching this exact regression. The Center's own copy of the pdb is a ~1.9GB leftover from a prior capture (file-dated `Jun 21`, while the exe itself is dated `Jul 5` — i.e. from BEFORE this regression shipped) that `steamcmd validate` never purges because it isn't part of the current tracked manifest, but also never needed to re-verify since `pdb_ok()` only checks presence+size. So this is a **dated, acknowledged, actively-tracked Wildcard bug**, not a structural depot decision — it is expected to resolve itself in a future ARK patch.
- **Immediate unblock applied (deliberately NOT escalated into a permanent fix)**: since both installs share the identical buildid, the pdb was manually copied from `ark-game-center` → `ark-game-genesis` at the same path, ownership set to `container:container`. Genesis then booted clean with all 5 mods valid, no pdb error, "has successfully started!" in 12.47s. **Considered and explicitly rejected**: (a) vendoring/baking this pdb into the Docker image (would mean permanently redistributing a Wildcard debug binary for a bug that's expected to disappear on its own — solving a temporary problem with a permanent architecture change), (b) pinning SteamCMD to the prior build (89.31) via an exact manifest ID (AsaApi's own literal recommendation) — not implemented because the precise manifest ID couldn't be reliably obtained (SteamDB blocks automated fetches; guessing an ID would be exactly the unverified fix this project's own verification discipline forbids). The manual copy is the right-sized fix for a bug this narrow and this likely to self-resolve.
- **COST if this outlives the upstream bug — the concrete recovery procedure, two cases:**
  - **Case A — a same-buildid volume exists somewhere reachable on THIS cluster — AUTOMATED (2026-07-06, same-day follow-up), not just documented.** `ensure_modded_pdb()` now maintains a small buildid-keyed pdb cache at `/home/container/cluster-data/.infra-pdb-cache/<buildid>.pdb` — a subdirectory on the ALREADY-shared `ark-cluster` volume (reused, not a new volume; kept clearly separate from ASA's own cluster-transfer data via the `.infra-pdb-cache` name). Whenever a pdb is confirmed valid (steamcmd-provided or manually restored), it's cached there if not already present; `ensure_modded_pdb()` checks this cache FIRST, before ever touching steamcmd. Effect: the first map that boots successfully at a given buildid silently seeds every OTHER map on the same cluster — a 3rd map, a rebuild-from-clean — with zero SSH, zero manual copy, zero steamcmd calls for them. **Live-verified end to end, not just syntax-checked**: seeded the cache from `genesis`'s real container, confirmed `the-center` (a different container) sees the identical file via the shared volume immediately. This does NOT reach a host with no shared volume to seed from at all (Case B) — nothing to automate there, there's no sibling.
  - **Case B — a truly fresh host with nothing to copy from at all** (the one real gap: the eventual prod VPS, first boot ever, zero prior installs — no `ark-cluster` volume yet either, so the Case-A cache has nothing to seed from). Resolution: **bring the pdb file along as part of the deploy kit** — `scp` it from dell (or wherever a working copy/cache exists) onto the new host's shared volume BEFORE first boot, the same way `.env` secrets are carried over rather than regenerated; once it lands in that host's own `.infra-pdb-cache/<buildid>.pdb`, Case A's automation takes over from there (every map on the NEW host benefits too, not just the first one). This needs no new infrastructure (no GitHub Releases, no Steam manifest-ID hunting, no Dockerfile vendoring) — considered and explicitly rejected as overbuilt for a bug this narrow and this likely to be already-fixed by Wildcard before Case B is ever reached.
- **TRIGGER**: re-check before the plan's own Rollout step 3 (operator deploys to the prod VPS from zero — Case B above). Watch [AsaApi/AsaApi#61](https://github.com/ArkServerApi/AsaApi/issues/61) or a fresh test install for Wildcard shipping a build after `89.38`/buildid `24058917` that restores the pdb — closes this deferral outright once confirmed, and neither case above is ever needed.
- **Addendum — pdb/exe version-matching — CORRECTED (2026-07-06/07): the earlier "resolved, no code change" call below was WRONG.** Original claim: `pdb_ok()` only checks presence+size, never build correspondence, but "real production evidence already answers whether this matters — The Center has been running a mismatched pdb/exe pairing successfully… Genesis replicated it with all 5 mods loading clean." That evidence was never actually verified — "mods loading clean" was Unreal's own CONTENT-mod system (`UShooterEngine::LoadGameMods`), a completely different mechanism from AsaApi's own C++ PLUGIN loading (`PluginManager::LoadAllPlugins()`). They were conflated. **What's actually true, verified live 2026-07-07 across every map, all session:** AsaApi's core loads fine ("API was successfully loaded", hooks "initialized") but `LoadAllPlugins()` — which is only ever invoked from a hook on `UGameEngine::Init` — never fires. Confirmed by (a) zero occurrence anywhere in any log, on any of the 4 maps, all session, of `"Loading plugins.."`, `"Loaded plugin"`, or `"UGameEngine::Init was called"` (the exact lines that hook's own code logs on firing); (b) forcing a fresh pdb-native offset derivation (disabled `AutomaticCacheDownload`, cleared `ArkApi/Cache/`) still produced the identical silent non-fire, ruling out "stale community CDN cache" as the cause. Root cause: the recovered pdb (Jun-21 capture) is a **valid, parseable file for an OLDER build** than the currently-installed exe (buildid `24058917`/89.38) — its derived offsets are real addresses, just for the wrong build, so the critical hook patches the wrong location and never fires, while the outer wrapper still reports success since nothing crashes. **Net effect: ArkShop/Permissions have never actually loaded on any map, all session — every server has been running vanilla-equivalent (no economy) despite `AsaApiLoader.exe` genuinely being the running process.**
  - **Considered and ruled out**: `WINEDLLOVERRIDES="version=n,b"` (a plausible Wine-DLL-load-order theory) — tested live, override confirmed reaching the process via `/proc/<pid>/environ`, zero change in outcome. Reverted (commit follows this entry) — no evidence it does anything for this bug, and shipping an unverified "fix" whose own comment claims to solve something it doesn't is worse than shipping nothing.
  - **Version-match reality check (2026-07-07):** rolling the server back to a build whose pdb genuinely matches (e.g. 89.31, confirmed via ARK patch notes to still include Genesis Part 1 — that map shipped in 89.25, earlier) was reconsidered as a real fix, not just a possibility — but ARK enforces exact client/server version matching (confirmed via community reports of Steam auto-updates breaking connections), and ASA's own Steam depot exposes no legacy-build beta branch (only `public` + `public_test_realm`, confirmed via `app_info_print`) — so pinning the server would ALSO require every connecting player, including the operator, to manually pin their own client to the identical build via a raw manifest ID, with no convenient toggle. Not practically usable.
  - **Decision (2026-07-07): wait for Wildcard's own fix** (their stated plan per AsaApi/AsaApi#61). No further code change pursued — every avenue that could restore AsaApi on the CURRENT build has been tried and genuinely ruled out (fresh pdb-native derivation, Wine DLL override, community cache bypass); the only remaining lever (an exact-matching pdb) doesn't exist until Wildcard ships one.
  - **TRIGGER**: re-test the moment Wildcard ships a build after 89.38 — watch [AsaApi/AsaApi#61](https://github.com/ArkServerApi/AsaApi/issues/61) or just check a fresh `ArkApi_*.log` for `"Loading plugins.."` after any future game update.
- **Fixed same-day (2026-07-06), independent of the fresh-install gap above**: `ensure_modded_pdb()`'s FATAL path used to `exit 1` after 3 failed validate attempts — but `docker-compose.yml`'s `restart: unless-stopped` restarts on ANY exit code, so this FATAL was never a clean stop, it was an unattended, unbounded loop of full ~13.5GB validate passes hammering the Steam CDN forever (confirmed live: Genesis re-entered this exact loop a second time before being stopped by hand). Changed to hold-and-scream: on unrecoverable pdb-missing, log a loud diagnostic (naming the real likely cause — an upstream depot regression, not local CDN/disk — and the manual-copy remedy) and `sleep`-loop indefinitely without re-touching steamcmd, so the container stays visibly failed in `docker compose logs`/`ps` instead of silently storming the CDN. Also corrected two now-provably-stale comments: the claim that `steamcmd validate` unconditionally "restores the pdb" (false when the current build's depot doesn't ship it at all), and the pdb's size (~6GB claimed, ~1.9-2GB actual).

## Deferred follow-up — 2026-07-06 — plan.md line-citation drift
- **WHAT**: plan.md's inline `entrypoint.sh:<N>` and `docker-compose.yml:<N>` line-number citations (in Background prose, Current-state anchors, Steps text, and Phase 2's un-executed anchors) have accumulated drift across 6 fix-loop rounds as each round's guard-code insertions shifted subsequent lines. Every "exhaustive sweep" attempt (rounds 4, 5, 6) fixed what it found but was re-staled by that same round's own edits, and each sweep's scope narrowed rather than widened.
- **WHY**: chasing full citation accuracy has cost 6 fix-loop rounds without ever closing it, while every reviewer (code-reviewer, acceptance-verifier, deviation-judge, graveyard-auditor across all 6 rounds) has independently confirmed the drift is PURELY navigational — it never affects any Acceptance Criterion's truthfulness, the delivered entrypoint.sh/docker-compose.yml code's correctness, or any security finding. Continuing to chase it now would be gold-plating an already-bounded, non-functional issue at the cost of further delaying Phase 1's actual commit.
- **COST**: one dedicated pass (est. 1 session) doing a genuinely complete grep-and-verify sweep of every `\.sh:[0-9]`, `\.yml:[0-9]`, `\.md:[0-9]` citation in the ENTIRE plan.md against the FINAL, post-all-rounds entrypoint.sh/docker-compose.yml/shop.md — done once, after all of Phase 1's code changes are truly frozen (not mid-fix-loop, which is why every prior attempt kept getting re-staled).
- **TRIGGER**: before Phase 2 begins execution (Phase 2's own Steps text cites several of these same files and would inherit any remaining drift), OR immediately if a future reviewer finds a citation error that DOES affect correctness/AC-honesty (upgrading this from cosmetic to a real should-fix).
