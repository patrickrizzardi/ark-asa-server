## Code Review: m2-shared-economy-store Phase 2 (round 2)

### Verdict: PASS

### Diff Scope
- Files changed: 2 in-scope code files (`Dockerfile`, `entrypoint.sh`) + plan.md (ledger row #12) + notes.md (churn)
- Lines added/removed (code files): Dockerfile +29 / -0; entrypoint.sh +74 / -0 (cumulative vs Phase 1 SHA 21fe5a8)
- Round-2 delta vs round 1: Dockerfile:34 (doc-pin comment), Dockerfile:53 (`.pdb` strip), entrypoint.sh:119 (comment reword)
- Phase commits reviewed: staged/uncommitted working tree vs 21fe5a8

### What's Solid
- The `.pdb` strip fix is the *right* fix, in the *right* place. `find /opt/asaapi -name '*.pdb' -delete` is a recursive walk — it catches all four debug-symbol files the coordinator's own pre-gate probe enumerated (`ArkApi/AsaApi.pdb` 48MB, `ArkApi/Plugins/Permissions/Permissions.pdb` 17MB, `ArkShop/ArkShop.pdb`, root `AsaApiLoader.pdb`), not just the root one the executor originally flagged. Stripping at build (Dockerfile:53) instead of at deploy (entrypoint) keeps BOTH the image lean AND every per-boot volume copy lean — the `cp -r "${src}/ArkApi"` at entrypoint.sh:94 now physically cannot carry a `.pdb` because none exist in `/opt/asaapi`. Strictly better than an entrypoint-side delete.
- Ordering is correct: line 53 runs after all `cp` steps (39-51) and before `chown` (54), inside the same `RUN` layer, so nothing ships the symbols.
- AsaApi needs no `.pdb` at runtime — debug symbols are loaded only by a debugger/crash-dump tooling, never by the loader at boot. Nothing runtime-needed is deleted. Confirmed against the M1 precedent at install_or_update (entrypoint.sh:43) which strips `ArkAscendedServer.pdb` as "dead weight on a headless server" — this fix makes the plugin tree consistent with that convention.
- The doc-pin comment at Dockerfile:34 makes non-enforcement unambiguous: "doc-pin only … no separate download, no URL interpolation. Records which Permissions version AsaApi 1.21 carries." States that the ARG enforces nothing, why (bundled in the AsaApi zip), and its real purpose (provenance). Magic-constant-without-provenance closed.
- The stash/restore glob guards (`[[ -f ]] || continue`) correctly survive the no-match case under `set -euo pipefail` — verified by a standalone repro: a `Plugins/` dir with zero `config.json` files does not crash the deploy, and an empty stash dir does not crash the restore. Defensive shell done right.

### Required Fixes (BLOCK only — empty if PASS)
None — phase ready to commit.

### Concerns (non-blocking, but will bite later)
- entrypoint.sh:87 `rm -rf "${win64}/AsaApiLoader.pdb"` is now dead defensive cleanup — with the build-time strip in place, `/opt/asaapi` ships no `.pdb`, so the entrypoint never deploys one to remove. It is HARMLESS (removes a path that won't exist) and serves a real hygiene purpose: scrubbing a stale `.pdb` left on the volume by a pre-fix image boot. Keep it — not a finding, noted so a future reader doesn't "clean it up" and lose the stale-volume guard.
- Round-1 non-blocking concerns (config-stash in /tmp crash-window at entrypoint.sh:68; dual-static-list maintenance coupling at entrypoint.sh:85-91 / 97-102) are UNCHANGED by this delta — the round-2 edits touched only comments + the Dockerfile strip, none of which touch those lines. Correctly deferred to Phase 5 per round-1 routing; not worsened, not re-raised.
- Theoretical stash-key collision: stash filename is `${plugin_name}_config.json`; a plugin literally named `ArkShop_config` would collide with `ArkShop`'s stash. Plugin names are AsaApi folder names (ArkShop, Permissions), not operator-controlled with `_config` suffixes, so unreachable in practice. Subsumed by the existing dual-static-list/maintenance concern already flagged for Phase 5. No new action.
- Cross-flags to siblings (NOT my BLOCK): entrypoint.sh:119 comment reword + Dockerfile:34 doc-pin are rules-compliance-reviewer's lane (phase-ref comment ban / magic-constant provenance). Both read clean from a code-quality angle too. Ledger row #12 placement is deviation-judge's lane.

### Laziness Pattern Audit
- Placeholder / mock pollution: PASS — no dummy values; ARGs carry real pinned versions corroborated in notes.md.
- Half-finished implementations: PASS — deploy_plugins handles empty-Plugins, no-config, empty-stash, and seed-if-absent branches; no happy-path-only gaps in the delta.
- Type escape hatches (code-quality angle): N-A — shell, no type assertions in the delta.
- Smuggled TODOs (code-quality angle): PASS — entrypoint.sh:119 phase-ref ("Phase 5 leaves it") was removed and replaced with a durable invariant comment; no incomplete-work markers remain in the delta.
- Magic constants without provenance: PASS — `PERMISSIONS_VERSION=1.1` now carries an explicit provenance/non-enforcement comment; the other two ARGs interpolate into real download URLs.
- Documented deviations — adversarial inputs constructed: PASS — Deviation: ".pdb stripped at build, not deployed." Adversarial inputs attempted across strategies: (1) NESTED-vs-ROOT — does `find … -name '*.pdb' -delete` catch the deep `ArkApi/Plugins/Permissions/Permissions.pdb`, not just root `AsaApiLoader.pdb`? YES, recursive walk; the wider find is correct, not an overshoot. (2) RUNTIME-NEED — does deleting any `.pdb` break the loader at boot? NO; symbols are debugger-only, and the M1 precedent strips the game `.pdb` already. (3) STALE-VOLUME second-caller — does a volume that already has a `.pdb` from a pre-fix boot get cleaned? YES via entrypoint.sh:87 `rm`. (4) NO-MATCH GLOB — does the stash/restore survive zero config.json under `set -euo pipefail`? YES, verified by repro. None broke the fix. Deviation validated.

### Test Coverage Audit
N/A — not a bug-fix or Tier A plan. This is infra packaging (Dockerfile + entrypoint shell); the plan's `## Planned RED Repros` and `## Behavioral Contract` sections are explicitly empty (no gate-shaped work). Phase ACs are runtime-verified on dell at Phase 4 per the plan; no unit-test surface in this phase. No existing test was weakened (no test files in scope).

### Bottom Line
Both round-1 BLOCKs are dead, chief — the `.pdb` strip is recursive, correctly ordered, and strictly better than an entrypoint delete, and the doc-pin comment makes the dead ARG honest. Clean PASS; the leftover concerns are Phase 5's problem, exactly where round 1 parked them.
