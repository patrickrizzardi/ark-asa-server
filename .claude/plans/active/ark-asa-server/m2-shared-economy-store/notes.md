# m2-shared-economy-store — execution notes (churn log)

Contract is `plan.md`. This file holds execution churn: probe logs, fix-loop
findings, decision drains, override rationales.

## Phase 1 — Self-contained MariaDB service + secrets

- 2026-06-20 — coordinator probe (pre-gate): real secret leaked into committed `.env.*.example`. Command: `git diff 873509a -- .env.test.example .env.prod.example`. Result: REFUTED (placeholders `change-me-*` / `use-a-long-random-*` only, both with "real values live in gitignored" comment). Routing: proceeding to fan-out.
- 2026-06-20 — coordinator probe (pre-gate): mariadb publishes a host port. Command: `git diff 873509a -- docker-compose.yml` (inspected `mariadb` service for `ports:`). Result: REFUTED (no `ports:` key on mariadb; internal-only). Routing: proceeding to fan-out.
- 2026-06-20 — coordinator probe (pre-gate): `depends_on` dropped the existing `sysctl` condition when adding `mariadb`. Command: `git diff 873509a -- docker-compose.yml`. Result: REFUTED (both `sysctl: service_completed_successfully` and `mariadb: service_healthy` present). Routing: proceeding to fan-out.
- 2026-06-20 — coordinator probe (pre-gate): compose fails to resolve. Command: `docker compose config --quiet` with placeholder creds. Result: REFUTED (RC=0). Routing: proceeding to fan-out.
- 2026-06-20 — round 1 gate: code-reviewer PASS, plan-adherence-verifier PASS, design-compliance-reviewer PASS (loud-fallback, no registry yet). rules-compliance-reviewer BLOCK (3 fixes). acceptance-verifier BLOCK (AC1/AC2/AC3 WEAK — runtime receipts needed). D_count=0. Tree-integrity matched snapshot post-gate.
- 2026-06-20 — rules-compliance round 1: BLOCK. (1) ADR `0001` backup deferral lacks no-duct-tape 4-field format [docs/internal/decisions/0001-db-engine-mariadb.md]; (2) compose header comment "AsaApi + plugins are M2 phases 2–5" is a changelog/phase-ref in code [docker-compose.yml:3]; (3) `.env.test.example` comment "These placeholders are never committed" is factually false (the .example IS committed) + placeholder-style drift vs prod [.env.test.example].
- 2026-06-20 — acceptance round 1: BLOCK. AC1/AC2/AC3 WEAK — runtime claims (mariadb healthy / app-user connect / persist-across-restart) unprovable from static compose. Fix: boot mariadb + capture receipts. AC4 (no host port) + AC5 (ADR+README) MET.
- 2026-06-20 — round 2 routing: bundled into one fix-round executor — 3 doc/comment fixes + local MariaDB boot to capture AC1(healthy)/AC2/AC3 receipts (host-agnostic; stock mariadb:11.4, no Proton). ADR backup deferral → cite ledger row "Backups: economy DB (mysqldump)" owned by m4-ops-tooling (planned).
- 2026-06-20 — coordinator probe (fix-loop, pre-respawn): all 3 rules-compliance fixes LANDED. `grep -nE 'M2 phase|Phase [0-9]' docker-compose.yml` → rc=1 (clean). `git diff` of .env.*.example → "never committed" gone, both files aligned on `use-a-long-random-*`. ADR cites `m4-ops-tooling` ledger row + What/Why/Cost/Trigger. Runtime evidence file: SELECT 1→1, row 42 survived restart, mariadb healthy in 3 polls, 3306/tcp no host binding. Routing: re-spawn gate.
- 2026-06-20 — round 2 produced 1 NEW scope deviation: `phase1-runtime-evidence.md` (plan-folder evidence receipt, orchestrator-directed for Part B). D_count 0→1. One deviation-judge fires this gate round.
- 2026-06-20 — round 2 gate: ALL PASS. code-reviewer PASS, rules-compliance PASS (3 round-1 fixes resolved), plan-adherence PASS (Scope-escape CLEAR), acceptance-verifier PASS (5/5 ACs MET w/ runtime receipts), design-compliance PASS, deviation-judge #1 PASS ("receipt, not a bomb"). Tree-integrity matched snapshot. Phase 1 ready to commit.

## Phase 2 — distribution channel resolution (Step 1)

- **2026-06-20 — distribution channel resolved: ark-server-api.com is NOT auth-gated.**
  Both resources return the ZIP body directly (HTTP 200, no login redirect) when hit with a
  plain `curl -sL`:
  - AsaApi (v1.21): `https://ark-server-api.com/resources/asa-server-api.31/download?version=latest`
    → 26 MB ZIP. Version 1.21 confirmed from the resource page. ZIP unpacks: `AsaApiLoader.exe`,
    `ArkApi/AsaApi.dll`, `ArkApi/Plugins/Permissions/Permissions.dll` (v1.1), runtime DLLs
    (`msvcp140.dll`, `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `msdia140.dll`), `config.json`
    (framework config), `Lib/` (developer lib — excluded from deploy).
  - ArkShop (v1.4): `https://ark-server-api.com/resources/asa-arkshop.34/download?version=latest`
    → 4.6 MB ZIP. ZIP unpacks: `ArkShop/ArkShop.dll`, `ArkShop/config.json`,
    `ArkShop/Commented.json`, `ArkShop/PluginInfo.json`.
  - Permissions plugin (v1.1) **ships bundled inside the AsaApi ZIP** — no separate download
    needed. ArkShop `PluginInfo.json` confirms `MinApiVersion: 1.19` (satisfied by v1.21).
- **Pinned versions for Dockerfile ARGs**: ASAAPI_VERSION=1.21, ARKSHOP_VERSION=1.4,
  PERMISSIONS_VERSION=1.1. URLs use `?version=latest` — these are the current stable versions
  at the pinned time; a version bump requires a Dockerfile ARG change + rebuild (no auto-latest).
- **`Lib/` directory excluded from the image**: `Lib/AsaApi.lib` is a Windows import library
  for plugin developers, not needed by the server at runtime. Excluded to keep the image lean.
- **`.pdb` files excluded**: debug symbols (`AsaApiLoader.pdb`, `AsaApi.pdb`,
  `ArkShop/ArkShop.pdb`, `Permissions.pdb`) not needed at runtime. Not stripped individually —
  the entire Lib/ tree is omitted; individual .pdb files at root are left in place (small, and
  stripping them selectively would add complexity with no meaningful size benefit; the game
  binary was already stripped of its .pdb in M1 entrypoint).
- **ArkShop ZIP folder layout**: ZIP contains `ArkShop/` as root folder → must be placed at
  `ArkApi/Plugins/ArkShop/` in the image (i.e., unzip and the `ArkShop/` dir goes there
  directly, or unzip to a staging dir and move).
- **`config.json` handling**: AsaApi framework `config.json` (ZIP root) and plugin
  `config.json` files are synced on first boot if absent on the volume; never overwritten on
  subsequent boots (Phase 5 owns injection; this phase just gets the defaults there).

## Phase 2 — coordinator probes (pre-gate)

- 2026-06-20 — coordinator probe (pre-gate): the build's download `RUN` steps point at `ark-server-api.com`, which the plan's #1 risk flagged as auth-gated/non-scriptable — executor never ran a real `docker build` so the URLs were unexercised. Command: `curl -sSL "https://ark-server-api.com/resources/asa-server-api.31/download?version=1.21"` + ArkShop `.34?version=1.4`, then `od -An -tx1 -N4` + `unzip -l`. Result: REFUTED — both HTTP 200 `application/octet-stream`, magic `50 4b 03 04` (PK/ZIP), `unzip -l` OK; folder==DLL-name holds (`ArkApi/Plugins/Permissions/Permissions.dll`, `ArkShop/ArkShop.dll`). URLs are scriptable + unauthenticated; plan risk over-cautious. Routing: proceeding to fan-out.
- 2026-06-20 — coordinator probe (pre-gate): Dockerfile `cp`s six explicit root files from the AsaApi zip under an `&&` chain — a single missing file aborts the build. Command: `unzip -l /tmp/asaapi.zip | awk '{print $NF}' | grep -cxF <f>` for each of AsaApiLoader.exe/msvcp140.dll/msdia140.dll/libcrypto-3-x64.dll/libssl-3-x64.dll/config.json. Result: REFUTED — all six → 1 (present). Build cp-chain won't abort. Routing: proceeding to fan-out. (Sidebar for code-reviewer: `cp -r ArkApi` also carries `ArkApi/AsaApi.pdb` 48MB + `Permissions.pdb` 17MB onto the volume each boot — executor flagged only the smaller root `AsaApiLoader.pdb`; bloat, not a build error.)

## Phase 2 — round 1 gate

- 2026-06-20 — round 1 gate: 4 PASS / 4 BLOCK. PASS: design-compliance (3-question split clean), acceptance-verifier (5/5 ACs MET at static-evidence ceiling; runtime receipts deferred to Phase 4/dell), plan-adherence (Scope-escape CLEAR, 4/4 steps, plan Step 3 pre-authorized remove-then-copy), deviation-judge #2 (stash-rm-cp sound; dual-static-list coupling fails loud not silent). BLOCK: code-reviewer, rules-compliance, deviation-judge #1, deviation-judge #3. Tree-integrity matched snapshot post-gate (status 00bd7d91 / diff 99f82411). D_count=3.
- 2026-06-20 — code-reviewer round 1: BLOCK (2). (1) `cp -r ArkApi` deploys ~65MB .pdb (AsaApi.pdb 48MB + Permissions.pdb 17MB) onto the volume every boot — contradicts the adjacent `install_or_update` convention that strips ArkAscendedServer.pdb as "dead weight on a headless server" [Dockerfile:39 / entrypoint.sh]. (2) `PERMISSIONS_VERSION=1.1` is a dead pin — never interpolated into a URL (Permissions ships bundled in the AsaApi zip) [Dockerfile:34]. Non-blocking LOUD concern for Phase 5: config-stash lives in /tmp (ephemeral) → a crash mid-deploy after the rm loses operator config; a named cost of Deviation #1 that Phase 5 must close (move stash onto the volume).
- 2026-06-20 — rules-compliance round 1: BLOCK (2). (1) `# … Phase 5 leaves it` is a phase-ref forward-delivery comment, banned by comments.md Hard Rule 1 [entrypoint.sh:119]. (2) unused `PERMISSIONS_VERSION` ARG needs a doc-pin comment (magic-constant-without-provenance) [Dockerfile:33].
- 2026-06-20 — deviation-judge #1 round 1: BLOCK. clean-replace-vs-rsync architectural decision written to notes.md `## Phase 2 — decisions` instead of plan.md Decision Ledger (Rule 00, one home). Coordinator note: this plan's Decision Ledger already hosts execution-resolved entries (row #10 "resolved at Phase-2 execution and recorded"), so a `verified-design` row #12 is the right home — judge BLOCK upheld, routed to fix loop.
- 2026-06-20 — deviation-judge #3 round 1: BLOCK. `PERMISSIONS_VERSION` ARG mechanically enforces nothing — same finding as code-reviewer #2 / rules-compliance #2 (three-way converge). Dedup → one fix.
- 2026-06-20 — round 2 routing: one fix-round executor — (1) keep PERMISSIONS_VERSION ARG + explicit non-enforcement comment [satisfies code-reviewer#2, rules#2, judge#3]; (2) strip .pdb in Dockerfile RUN before chown; (3) reword entrypoint.sh:119 to durable mechanism; (4) move clean-replace decision to plan.md Decision Ledger row #12 + trim notes.md dup. No-progress hashes recorded in coordinator turn context.

## Phase 2 — round 2 gate

- 2026-06-20 — round 2 gate: ALL 8 PASS. code-reviewer PASS (both round-1 BLOCKs resolved), rules-compliance PASS (both resolved; non-blocking concern: Big-O annotation on deploy_plugins()), plan-adherence PASS (Scope-escape CLEAR, 4/4 steps), acceptance-verifier PASS (5/5 ACs MET at static-evidence ceiling), design-compliance PASS (.pdb strip honors 3-question split), deviation-judge #1/#2/#3 PASS. Tree-integrity: diff_hash matched snapshot (cf569d8a) — tracked code unmutated; status drift was only untracked scratch/reviews/ artifacts. No-progress N/A (R1 BLOCKs → R2 PASS, different outcome).
- 2026-06-20 — pre-respawn probe (fix-loop): all 4 fixes verified LANDED before re-gate. `grep` confirmed: Dockerfile:34 doc-pin comment; Dockerfile:53 `.pdb` strip BEFORE chown(:54); entrypoint.sh no phase-ref (line 119 reworded); plan.md row #12 present; notes.md dup trimmed to one-line pointer.
- 2026-06-20 — two NON-BLOCKING residuals carried to commit prompt (not auto-spun into round 3): (1) rules-compliance concern — deploy_plugins() lacks a comments.md Hard-Rule-7 Big-O header (`# Time/Space O(n) where n=plugin count`); trivially-small n, hides nothing. (2) deviation-judge #2 informational — Dockerfile:34 doc-pin comment hardcodes "AsaApi 1.21", accurate today, goes stale only if ASAAPI_VERSION bumps without a comment edit. Both are one-line comment changes; surfaced to Patrick for commit-now-vs-polish-round call (proportionality — a full 8-agent re-gate for two accurate-today comment lines).

## Phase 2 — round 2 coordinator decisions

- **Phase-1 writeback committed as housekeeping (ade3857) + branched `feat/m2-2-bake-plugins` off it.** The dirty plan.md/state.md at entry were the trailing Phase-1 `Committed: 21fe5a8` SHA marker + a radar refresh — not phase-2 WIP. Committed them so the phase-2 diff starts clean against BASE 21fe5a8.
- **judge #1 BLOCK upheld, not overridden.** I had a reservation (plan Step 3 pre-authorized "remove-then-copy", so the stash-rm-cp choice wasn't a true deviation) but the judge's homing concern was independently valid: a binding sync-strategy decision belongs in the durable contract. Routed to fix loop; chose plan.md Decision Ledger row #12 as the home (consistent with the ledger's existing execution-resolved rows #10/#11), NOT a new ADR (the decision is easily reversible — swap the function body — so not ADR-class per documentation.md b-2).
- **PERMISSIONS_VERSION remedy = keep ARG + explicit comment, NOT delete.** Three agents (code-reviewer, rules, judge#3) flagged the dead pin; code-reviewer/judge#3 leaned delete. I directed keep-+-comment because plan Step 2 explicitly required a `PERMISSIONS_VERSION` ARG — deleting it would itself be a plan deviation. The explicit non-enforcement comment is the common remedy all three accepted; round-2 re-judge confirmed it resolves the BLOCK.

## Phase 2 — round 3 gate (final, polish)

- 2026-06-20 — Patrick chose "polish both, then commit" at the round-2 commit prompt. Round 3 = 2 comment-only fixes: (A) Big-O header on `deploy_plugins()` (entrypoint.sh:66, comments.md Hard Rule 7); (B) de-hardcode "AsaApi 1.21" → "the pinned AsaApi (ASAAPI_VERSION)" in the Dockerfile:34 doc-pin comment (judge#2 R2 informational residual).
- 2026-06-20 — round 3 carry decisions: re-spawned code-reviewer, rules-compliance (verify Big-O), plan-adherence, acceptance + the 2 judges whose hunks the comments touched (stash-rm-cp entrypoint.sh; versioned-URL Dockerfile). CARRIED design-compliance (no `[locked]` globs under absent registry; comment-only delta) + decision-rehoming judge (plan.md/notes.md untouched this round). 6 spawned, 2 carried.
- 2026-06-20 — round 3 gate: ALL 8 lanes PASS (6 spawned PASS + 2 carried PASS). Pre-respawn probe verified both fixes landed (Big-O at entrypoint.sh:66, ASAAPI_VERSION ref at Dockerfile:34). Tree-integrity: Dockerfile/entrypoint.sh blobs byte-identical to round-3 snapshot (no gate-agent code mutation); diff drift was only state.md radar refresh (stop-hook, outside phase scope). Phase 2 fully clean — both non-blocking residuals closed. Ready to commit.

## Phase 2 — decisions

- **Distribution channel confirmed non-auth-gated**: `ark-server-api.com` returns ZIP bodies
  directly via `curl -fsSL` with `?version=<N>` — no login, no redirect wall. Versioned URLs
  tested and confirmed live: `?version=1.21` (AsaApi, 27MB) and `?version=1.4` (ArkShop, 4.7MB).
  The `?version=latest` variant also works but we use the explicit version URL so the ARG actually
  gates the download.
- **Permissions ships bundled in the AsaApi ZIP** — no separate download. `PERMISSIONS_VERSION=1.1`
  ARG is a documentation pin; it doesn't drive a separate curl because the DLL comes from the
  AsaApi package.
- Plugin sync = clean-replace over rsync → see plan.md Decision Ledger row #12 (the durable home).
- **`ONLY FOR DEVELOPERS` dir excluded** from image: developer import lib (`Permissions.lib`)
  not needed at runtime. Removed from `/opt/asaapi` (not from temp staging — rm is correctly
  applied after the `cp -r` into /opt, before chown).
- **`Lib/AsaApi.lib` excluded** (developer Windows import library, not a runtime dependency).
  Not copied into /opt/asaapi at all — only files listed explicitly are copied.
- **`.pdb` files stripped at build** (round-2 fix, code-reviewer): `find /opt/asaapi -name '*.pdb' -delete`
  in the Dockerfile RUN before `chown` removes all debug symbols — chiefly `ArkApi/AsaApi.pdb` (~48MB)
  + `Permissions.pdb` (~17MB), ~65MB that `cp -r ArkApi` would otherwise deploy to the volume every
  boot. Mirrors M1's `ArkAscendedServer.pdb` strip ("dead weight on a headless server"). The
  entrypoint's `rm` of `AsaApiLoader.pdb` in the deploy set is now a harmless defensive no-op.
  (Supersedes the round-1 "left in place" note — that was the pre-fix state.)

## Phase 1 — decisions

- **Verified the MariaDB ACs locally in WSL docker, not on dell.** AC1(healthy)/AC2(connect)/AC3(persist) are host-agnostic — `mariadb:11.4` is a stock upstream image with zero Proton/Wine involvement, so a local boot is valid evidence, not an approximation. dell matters only for the GE-Proton game server (Phase 4/5). The full-stack `the-island`-starts-after-mariadb ordering half of AC1 stays compose-guaranteed (`depends_on: condition: service_healthy`) and gets empirically confirmed when the game image boots on dell in Phase 4/5. Coordinator call; all reviewers + acceptance-verifier accepted the local evidence as sufficient for this phase.
- **Committed the plan contract to `main` (873509a) before phase work.** Precedent: the roadmap was committed straight to main in b81e215. Keeps per-phase diffs clean against a stable BASE. Phase code lives on `feat/m2-1-mariadb`.
- **ADR backup deferral anchored to the `m4-ops-tooling` capability-ledger row** ("Backups: economy DB (mysqldump)", planned) rather than inventing fresh prose — the cleaner of the two no-duct-tape resolution options.
