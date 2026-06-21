# Code Review: m2-shared-economy-store Phase 4 (round 1)

### Verdict: BLOCK

### Diff Scope
- Files changed: 5 (`entrypoint.sh`, `docker-compose.yml`, `Dockerfile`, `.env.test.example`, `.env.prod.example`)
- Lines added/removed: +43 / -5 (per `git diff 29735d2 --stat` of cited files)
- Phase commits reviewed: staged/uncommitted on `feat/m2-4-asaapi-loader` (base `29735d2`)

### What's Solid
- The launch-routing refactor is clean: one `launch_exe` var, both branches reuse the identical `${query}`/`${flags}`, so there's no arg drift between vanilla and modded (Quality gate "same query/flags reused" — genuinely met). Good.
- The `xvfb_pid` cleanup at entrypoint.sh:274 mirrors the existing `tail_pid` kill pattern and is correctly guarded with `[[ -n ... ]]` so the vanilla branch (empty pid) doesn't `kill ""`.
- `unzip` placement in the Dockerfile is correct per `build-time-vs-runtime.md` (immutable build dep → image layer) and the apt layer is tidy (`--no-install-recommends` + `rm -rf /var/lib/apt/lists/*`). Deviation #1 validated.
- Xvfb gated strictly to the loader branch keeps `ENABLE_ASAAPI=0` byte-for-byte M1 (AC3) — and runtime evidence confirms the vanilla path still advertises for join. Deviation #2 validated (see adversarial section).
- Comments carry durable WHY (the `nodrv_CreateWindow` reason, the pdb offset-cache reason). No changelog phrasing, no Big-O regressions on the touched funcs.

### Required Fixes (BLOCK)

1. **[entrypoint.sh:33-52]** WHAT: The pdb-shed decision is gated on first-install state (`INSTALL_MARKER`), not on the `ENABLE_ASAAPI` toggle that actually governs it. Adversarial trace: boot **vanilla first** (`ENABLE_ASAAPI=0` → pdb deleted at line 51, `.installed` marker written at line 53) → operator flips to `ENABLE_ASAAPI=1` and restarts → the first-install block is skipped (marker exists), so the pdb is never re-fetched → AsaApi hits `[critical] Failed to read pdb` and loads **zero plugins** while the server still reports "successfully started." This is the exact failure the deviation was meant to prevent, just shifted onto the toggle-flip ordering — and the plan's own AC3 (rollback via toggle, no rebuild) makes flip-both-directions a first-class supported path. WHY: silent-wrong-output (Operating Principle #9) — the modded server boots "green" but with no mods, no loud error; the runtime-evidence doc even records needing a manual `steamcmd validate` (~2GB) to recover the pdb on dell, confirming the gap is real, not theoretical. Also a `no-duct-tape.md` #6 violation ("this case can't happen yet" — it can, on the documented rollback path). FIX: decouple pdb presence from first-install. Either (a) before the modded launch, if `ENABLE_ASAAPI=1` and `ArkAscendedServer.pdb` is absent, run a `steamcmd +app_update ... validate` (or targeted re-fetch) to restore it and verify it landed — same "verify the artifact" discipline as the `SERVER_EXE` check at line 40; or (b) never shed the pdb at all (simplest: drop the conditional `rm` entirely and accept the ~6GB on vanilla too, since the toggle can flip either way on the same volume). Whichever — the invariant must be "pdb present whenever a modded boot could occur on this volume," not "pdb present iff the very first boot was modded."

### Concerns (non-blocking, but will bite later)

1. **[entrypoint.sh:244-249]** Xvfb startup failure is swallowed. If `Xvfb :0` fails to launch (binary missing, `:0` already bound by a leftover process inside a long-lived container), `xvfb_pid` points at a dead PID, the socket never appears, the readiness loop spins the full ~5s, and `proton run` then launches into a broken display → loader aborts → crash loop with no entrypoint-level diagnostic. It degrades to the *pre-fix* failure mode (loud Wine `nodrv_CreateWindow`), so it's not silent — hence Concern not BLOCK — but a `kill -0 "$xvfb_pid" 2>/dev/null` check (or a "socket never came up" warning when the loop exhausts all 50 iterations) would turn a confusing crash-loop into a one-line root cause. Cheap robustness win on a runtime path.

2. **[entrypoint.sh:194-277 / docker-compose.yml]** No PID-1 init / zombie reaper. The entrypoint is PID 1 and now forks a third long-lived child (Xvfb, alongside the server and `tail`). `proton`/Wine spawn their own subprocess trees; without `init: true` on the service (or tini), re-parented Wine zombies accrue to PID 1 which doesn't reap them. Pre-existing condition (server + tail already had this shape), and Xvfb is explicitly killed at line 274 on the normal path, so this isn't introduced by Phase 4 — but Phase 4 adds a child and an X subsystem that's notorious for orphan helpers. Worth a one-line `init: true` on the `the-island` service. Cross-cutting infra, not a Phase 4 BLOCK.

3. **[entrypoint.sh:246]** `DISPLAY=:0` and Xvfb display number are hardcoded. Fine for a single-tenant box (only one server per container), and runtime evidence proves it works — but if a future phase ever runs two server processes in one container (it won't per the single-map scope), `:0` collides. Noting only because the value has no provenance comment; the surrounding comment explains *why Xvfb*, not *why :0*. Low stakes — leave it unless you want a one-word note.

4. **[entrypoint.sh:51 comment]** The kept-comment at lines 44-48 says "Vanilla (ENABLE_ASAAPI=0) never touches the pdb, so it's shed there to reclaim the space." After Required Fix #1 the comment must be re-stated to match whatever invariant you land on — flagging so the comment doesn't rot into a contradiction of the fixed code.

### Laziness Pattern Audit
- Placeholder / mock pollution: PASS — no dummy values; `.env.*.example` toggles carry real operator-facing comments.
- Half-finished implementations: FAIL — pdb-shed gated on the wrong condition leaves the modded-after-vanilla path half-handled (Required Fix #1); Xvfb startup-failure path unhandled (Concern #1, degrades loudly so not a BLOCK).
- Type escape hatches (code-quality angle): PASS — N/A for shell; no eval/unquoted-expansion bugs introduced. `${flags}` is intentionally unquoted for word-splitting with a load-bearing comment at line 225-226 (correct).
- Smuggled TODOs (code-quality angle): PASS — no TODO/FIXME/phase-ref comments in the diff.
- Magic constants without provenance: PASS (with Concern #3) — `1024x768x24` and `:0` are Xvfb-standard; the 50-iteration/0.1s readiness cap carries a "~5s" rationale comment.
- Documented deviations — adversarial inputs constructed (NOT the case executor named): FAIL — Deviation #3 (pdb) breaks under the adversarial input. Adversarial inputs attempted across strategies:
  - **Second-caller / state-ordering** (Dev #3): boot-vanilla-then-flip-modded → pdb already deleted + marker set → modded boot loads zero plugins silently. **BROKE the fix** → Required Fix #1.
  - **Reverse ordering** (Dev #3): boot-modded-then-flip-vanilla → pdb kept forever (~6GB waste under vanilla); cosmetic, not a break.
  - **Coexistence / config-conflict** (Dev #2): `SDL_VIDEODRIVER=dummy` (Dockerfile:82, global) vs `DISPLAY=:0` set only in loader branch → runtime evidence shows modded server reaches "advertising for join," so they coexist. Deviation #2 **validated**.
  - **Startup-failure injection** (Dev #2): Xvfb fails to bind → readiness loop swallows it, but degrades to the loud pre-fix abort → Concern #1, not a break of the stated fix.
  - **Build-dependency** (Dev #1): no adversarial input breaks it — `unzip` is unconditionally needed by Phase 2's RUN and is immutable. Deviation #1 **validated**.

### Test Coverage Audit
- Bug-fix Phase 1 failing test present: N/A — not a bug-fix plan (Planned RED Repros section empty); this is an infra/entrypoint phase verified by runtime receipts, not unit tests.
- Test weakening detected: N/A — no test files in scope.
- Tier A invariants tested: N/A — not a Tier A correctness-critical code plan; the AC evidence is bare-metal runtime logs (acceptance-verifier's audit, not mine).
- Tier A adversarial cases: N/A.

### Bottom Line
Chief, the launch flip itself is clean and the runtime receipts prove AsaApi actually loads — but the pdb-shed is wired to "was the first boot modded?" instead of "is this boot modded?", so the documented rollback toggle can silently strand the modded server with zero plugins. Fix the gate to track the toggle, not the install marker, and this ships.
