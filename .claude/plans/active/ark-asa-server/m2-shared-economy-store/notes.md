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

## Phase 1 — decisions

- **Verified the MariaDB ACs locally in WSL docker, not on dell.** AC1(healthy)/AC2(connect)/AC3(persist) are host-agnostic — `mariadb:11.4` is a stock upstream image with zero Proton/Wine involvement, so a local boot is valid evidence, not an approximation. dell matters only for the GE-Proton game server (Phase 4/5). The full-stack `the-island`-starts-after-mariadb ordering half of AC1 stays compose-guaranteed (`depends_on: condition: service_healthy`) and gets empirically confirmed when the game image boots on dell in Phase 4/5. Coordinator call; all reviewers + acceptance-verifier accepted the local evidence as sufficient for this phase.
- **Committed the plan contract to `main` (873509a) before phase work.** Precedent: the roadmap was committed straight to main in b81e215. Keeps per-phase diffs clean against a stable BASE. Phase code lives on `feat/m2-1-mariadb`.
- **ADR backup deferral anchored to the `m4-ops-tooling` capability-ledger row** ("Backups: economy DB (mysqldump)", planned) rather than inventing fresh prose — the cleaner of the two no-duct-tape resolution options.
