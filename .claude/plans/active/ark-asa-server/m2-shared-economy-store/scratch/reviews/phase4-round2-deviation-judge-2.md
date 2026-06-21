# Deviation Judge — Phase 4 Round 2 Deviation #2 (Xvfb)

## Verdict: BLOCK

## Deviation summary
Xvfb virtual framebuffer started in the ENABLE_ASAAPI=1 branch; R2 adds a post-loop socket-existence guard (`[[ ! -S /tmp/.X11-unix/X0 ]] → exit 1`) to catch the R1 failure mode (loop-exhaustion with no socket → silent launch into nodrv_CreateWindow).

---

## Adversarial input(s) constructed

1. **Stale socket — Xvfb crashes after bind() but before listen()/accept()**: Xvfb starts, the kernel `bind()` call creates `/tmp/.X11-unix/X0` (the socket file exists), then Xvfb dies (OOM during 1024×768×24 framebuffer allocation, unexpected signal, DRI `ioctl` failure mid-init). The socket file persists on disk. The poll loop sees it at iteration N (`[[ -S /tmp/.X11-unix/X0 ]]` → PASS), breaks early. The R2 guard `if [[ ! -S /tmp/.X11-unix/X0 ]]` also passes (socket file is present). `export DISPLAY=:0` is already set. `proton run "$LOADER_EXE"` launches. Wine calls `connect()` on `/tmp/.X11-unix/X0`, receives `ECONNREFUSED` (nobody listening). Wine logs `nodrv_CreateWindow ("explorer process failed to start")`, loader aborts — same failure the Xvfb was introduced to prevent.

2. **Xvfb alive but not yet listening — race before listen() completes**: Xvfb creates the socket file via `bind()`, the poll loop happens to fire in the narrow window before `listen()` is called. `[[ -S /tmp/.X11-unix/X0 ]]` passes. R2 guard passes. Wine's `connect()` arrives before Xvfb calls `listen()` → `ECONNREFUSED`. This window is very short in practice (microseconds to milliseconds) and is far less likely than scenario 1, but is structurally the same class of defect: `-S` confirms socket-file existence, not connection-readiness.

---

## Trace

**Active input**: Adversarial input #1 (stale socket after Xvfb crash-after-bind).

**entrypoint.sh:297** — `Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &`
- Xvfb starts in background. `stderr` suppressed. Xvfb calls `bind()` → kernel creates `/tmp/.X11-unix/X0` socket file. Then Xvfb dies (OOM / DRI failure) before calling `listen()`. Process exits non-zero, but since this is a background job and stderr is suppressed, the entrypoint observes nothing.

**entrypoint.sh:298** — `xvfb_pid=$!` — captures the now-dead process's PID.

**entrypoint.sh:299** — `export DISPLAY=:0` — sets DISPLAY regardless of Xvfb health.

**entrypoint.sh:302** — `for _ in $(seq 1 50); do [[ -S /tmp/.X11-unix/X0 ]] && break; sleep 0.1; done`
- First iteration: `/tmp/.X11-unix/X0` IS a socket file (created by bind() before crash). `[[ -S /tmp/.X11-unix/X0 ]]` → true. Loop breaks. No `sleep` fires. Loop exits in <1ms.

**entrypoint.sh:306** — `if [[ ! -S /tmp/.X11-unix/X0 ]]; then ... exit 1; fi`
- `/tmp/.X11-unix/X0` is still a socket-type file on disk (verified empirically: bash `-S` tests `stat(2)` type = S_IFSOCK; a bound-then-abandoned Unix socket retains its inode type). Condition is FALSE. No FATAL. No exit. **R2 guard passes silently.**

**entrypoint.sh:311** — `echo "[entrypoint] Launching ..."` — success log emitted. False positive.

**entrypoint.sh:317** — `proton run "${LOADER_EXE}" "${query}" ${flags} 2>&1 &`
- Proton launches with `DISPLAY=:0`. Wine's X11 client calls `connect(AF_UNIX, "/tmp/.X11-unix/X0")`. Xvfb is dead; nobody is listening. Kernel returns `ECONNREFUSED`. Wine logs `nodrv_CreateWindow`. AsaApiLoader aborts. Same failure as pre-Xvfb.

**Empirical confirmation of `-S` on stale socket:**
```
python3: bind() /tmp/test-stale-X0, close(), [[ -S /tmp/test-stale-X0 ]] → PASS
python3: connect() /tmp/test-stale-X0 → ConnectionRefusedError: [Errno 111]
```
Both confirmed on the host (linux 6.18.33.1).

---

## Where the fix overshoots

- **Stated problem (R1 BLOCK)**: the readiness poll loop exhausts with no socket (Xvfb never started), falls through silently, proton launches with no display → nodrv_CreateWindow. R1 fix: exit 1 if socket absent after loop.
- **Wider effect of R2 guard**: the guard correctly catches "socket never appeared" but also passes "socket appeared then died" — the same downstream failure (nodrv_CreateWindow) with a success log emitted first, making it harder to diagnose.
- **Narrower fix that would work**: two options, either sufficient:

  **Option A — Process liveness check (minimal, one line after the existing guard):**
  ```bash
  if [[ ! -S /tmp/.X11-unix/X0 ]]; then
    echo "[entrypoint] FATAL: Xvfb failed to start — /tmp/.X11-unix/X0 socket absent after 5s." >&2
    exit 1
  fi
  if ! kill -0 "$xvfb_pid" 2>/dev/null; then
    echo "[entrypoint] FATAL: Xvfb created socket then exited — display not available." >&2
    exit 1
  fi
  ```
  A dead process cannot accept connections. Socket + live pid = necessary condition for Wine to connect. Not a perfect readiness proof (Xvfb could still be in the bind→listen gap), but closes the stale-socket class entirely.

  **Option B — xvfb-run (existing primitive, already in base image):**
  `xvfb-run` is confirmed present in the `steamcmd:proton` base (`/home/patrick/docs/development/ark-asa/.claude/plans/active/ark-asa-server/m2-shared-economy-store/phase4-runtime-evidence.md:44` and `scratch/reviews/phase4-round1-plan-adherence.md:58`). It uses the X11 SIGUSR1 readiness protocol: Xvfb sends `SIGUSR1` to its parent when it is fully ready to accept connections — after `listen()`, not after `bind()`. This is the narrower, correct readiness check and eliminates both adversarial inputs (stale socket AND bind→listen race). Replaces the Xvfb start + poll loop + guard block with:
  ```bash
  xvfb-run --server-num=0 --server-args="-screen 0 1024x768x24 -nolisten tcp" \
    proton run "${LOADER_EXE}" "${query}" ${flags} 2>&1 &
  ```
  Note: this changes the process topology (Xvfb is a child of xvfb-run, not a sibling), which simplifies cleanup (no separate xvfb_pid to kill). The existing `[[ -n "$xvfb_pid" ]] && kill "$xvfb_pid"` cleanup at line 335 would need to be removed or made conditional.

---

## Strategies attempted

**1. Mixed inputs (primary — produced BLOCK):** Mixed "Xvfb binds socket" with "Xvfb then crashes before listen". The fix's `-S` check guards socket-file existence; it does not distinguish a live socket from a dead one. The `ECONNREFUSED` path survives R2. BLOCK on this input.

**2. Boundary inputs:** Checked the `seq 1 50` loop boundary (50 iterations × 0.1s = 5s cap). At the boundary where Xvfb is slow-starting (e.g., filesystem contention), the loop could exhaust before socket appears — this is R1's scenario, already fixed. At the boundary where Xvfb starts exactly on iteration 50 (socket appears at last check), the fix passes correctly — Xvfb is live and accepting. No break found here.

**3. Existing-primitive check:** `xvfb-run` is present in the base image (confirmed at `phase4-runtime-evidence.md:44`). It uses the SIGUSR1 X11 readiness protocol — the standard, narrower primitive that proves connection-readiness (not just socket-file existence). The entrypoint uses raw `Xvfb` + socket-existence poll instead. This is the "30-lines-away narrower helper" pattern from the mandate: the existing primitive does the right thing and the deviation uses a weaker homegrown check.

**4. Round-trip / serialization:** Not applicable — no data serialization in this path.

**5. Second-caller check:** Not applicable — the Xvfb start is a single call site. No second caller.

---

## Bottom Line

The R1 BLOCK (silent loop exhaustion) is fixed; the R2 guard correctly exits on "socket never appeared." But `-S` on a Unix socket is an existence check, not a liveness check — a stale socket from Xvfb-crash-after-bind is indistinguishable at the filesystem level, passes the guard, and lets proton launch into the same nodrv_CreateWindow abort with a false success log. BLOCK — add `kill -0 "$xvfb_pid"` after the socket check, or replace the whole block with `xvfb-run` which is already in the image and does this right.
