# Deviation Judge — Phase 4 Deviation #2
# Plan: m2-shared-economy-store

**Verdict: BLOCK**

---

## Deviation Summary

Added an Xvfb virtual framebuffer in the ASAAPI branch of `main()`: starts Xvfb `:0`, exports `DISPLAY=:0`, waits up to 5 seconds for the X socket to appear, then launches via `proton run`. Kills Xvfb after `server_pid` exits. Vanilla branch is unchanged.

---

## Cold Read (before rationale)

Mechanically the diff does:
1. `Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &` — stderr discarded, backgrounded
2. `xvfb_pid=$!` — capture PID
3. `export DISPLAY=:0`
4. `for _ in $(seq 1 50); do [[ -S /tmp/.X11-unix/X0 ]] && break; sleep 0.1; done` — poll for socket up to 50×100ms=5s
5. No check after the loop that the socket actually exists
6. Proceed to `proton run` regardless of loop outcome
7. `[[ -n "$xvfb_pid" ]] && kill "$xvfb_pid" 2>/dev/null || true` — cleanup after server exits

The rationale named case I did NOT test: AsaApiLoader with no X display → `nodrv_CreateWindow` → abort.

---

## Adversarial Input Constructed

**Input**: Xvfb fails to start (e.g., the `xvfb-run` binary throws an unexpected error on first invocation, or the user running the container lacks write permission to `/tmp/.X11-unix/`, or a transient `Xvfb` startup error causes immediate exit before binding its socket). Concretely: `Xvfb :0` backgrounds but exits with code 1 before creating `/tmp/.X11-unix/X0`.

This is **in scope** of the fix: the fix's only stated job is "give Wine an X display so AsaApiLoader doesn't abort." The fix is **wider** than that: it also handles the "Xvfb started but not yet ready" timing case — but it handles "Xvfb failed to start entirely" identically (loop runs all 50 iterations, socket never appears, no break fires, execution falls through).

---

## Trace

1. `entrypoint.sh:244`: `Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &`
   - Xvfb exits immediately with code 1 (error). Process is gone.
   - stderr is discarded (`>/dev/null 2>&1`). No log entry anywhere.
   - `xvfb_pid` holds the now-dead process's PID.

2. `entrypoint.sh:249`: `for _ in $(seq 1 50); do [[ -S /tmp/.X11-unix/X0 ]] && break; sleep 0.1; done`
   - `/tmp/.X11-unix/X0` never appears (Xvfb died before binding).
   - Loop iterates all 50 cycles (~5 seconds).
   - **No `break` fires. Loop exits normally — no error, no check.**

3. `entrypoint.sh:250`: `echo "[entrypoint] Launching ... [AsaApiLoader — modded, Xvfb :0]"`
   - Log says "Xvfb :0" — no indication anything went wrong.

4. `entrypoint.sh:256`: `proton run "${LOADER_EXE}" "${query}" ${flags} 2>&1 &`
   - `DISPLAY=:0` is set; there is no server at `:0`.
   - Wine attempts `XOpenDisplay(":0")` → ECONREFUSED (no socket).
   - Wine logs `nodrv_CreateWindow` → `explorer process failed to start` → loader aborts.
   - `server_pid` is assigned the backgrounded proton process, which exits quickly.

5. `entrypoint.sh:272`: `wait "$server_pid"` — returns immediately (proton already exited).
6. `entrypoint.sh:273`: `kill "$tail_pid"` — log tail killed.
7. `entrypoint.sh:274`: `kill "$xvfb_pid"` — kill a dead PID (no-op, `2>/dev/null` swallows ESRCH).

**Net result**: silent 5-second stall, then proton exits immediately with the exact same `nodrv_CreateWindow` failure the fix was supposed to prevent. The log says "Launching... [AsaApiLoader — modded, Xvfb :0]" with zero indication of the actual failure mode. Operator sees a fast-exit server with no diagnostic.

---

## Where the Fix Overshoots

- **Stated problem**: Xvfb is started asynchronously and Wine may connect before the socket is ready → poll up to 5s for the socket.
- **Wider effect**: The poll loop exits after 5s whether or not the socket ever appeared. If Xvfb failed to start (socket never comes), execution proceeds anyway into a Wine launch that is guaranteed to fail with the same `nodrv_CreateWindow` abort — silently, with a misleading success log line.
- **Narrower fix**: After the loop, add a guard:
  ```bash
  if [[ ! -S /tmp/.X11-unix/X0 ]]; then
    echo "[entrypoint] FATAL: Xvfb :0 failed to start (socket /tmp/.X11-unix/X0 not found after 5s). Cannot launch AsaApiLoader." >&2
    [[ -n "$xvfb_pid" ]] && kill "$xvfb_pid" 2>/dev/null || true
    exit 1
  fi
  ```
  This is the narrowest possible addition: one conditional, after the loop already present at line 249, before line 250. The rest of the fix is correct. No existing primitive needed — the guard is trivially constructed from the existing socket path the loop already uses (`/tmp/.X11-unix/X0`).

---

## Strategies Attempted

### Mixed inputs
Tried: Xvfb starts successfully AND the socket exists (the stated case) mixed with Xvfb starts but exits before creating the socket. The loop-fall-through behavior fires for "Xvfb never ready" the same way it fires for "Xvfb not yet ready." The fix doesn't distinguish these — it is wider than the stated timing problem.

### Boundary inputs
- Loop boundary: `seq 1 50` with `sleep 0.1` = exactly 5s maximum. If the socket appears at iteration 51 (> 5s), execution proceeds without it — same failure. This is a pre-existing design tradeoff (Xvfb is documented as "comes up in well under 1s"), not a new issue introduced by this deviation.
- Loop boundary: socket appears at iteration 1 (immediate) — the `break` fires correctly. Not a problem.
- Loop boundary: socket never appears — **this is the adversarial input above, and it breaks the fix.**

### Existing-primitive check
Searched `entrypoint.sh` for a socket-readiness check pattern that also validates the listener is alive (not just that the socket file exists). None found. The loop at line 249 is the only check, and it is a pure `[[ -S path ]]` test. A post-loop guard using the same test with an explicit `exit 1` is the narrower fix.

### DISPLAY leak into vanilla path
`export DISPLAY=:0` at line 246 is inside `if [[ "${ENABLE_ASAAPI}" == "1" ]]`. The vanilla `else` branch at line 251 doesn't set `DISPLAY`. However, `export` in bash persists through the function's process environment for anything spawned after it. Since the two branches are mutually exclusive (`if/else`), there is no scenario where both run in the same process. `SDL_VIDEODRIVER=dummy` is set globally in `ENV` in the Dockerfile (line 82) and is never unset in the ASAAPI branch — this is a pre-existing separate concern (does AsaApiLoader's Wine use SDL_VIDEODRIVER? Probably not for the Win32 window creation path) and is NOT introduced by this deviation. PASS on DISPLAY-leak and SDL_VIDEODRIVER-interference.

### Hardcoded :0 collision
`/tmp/.X11-unix/` is a per-container tmpfs in Docker (not shared with host unless explicitly bind-mounted, which this compose setup does not do). A stale `:0` socket from a prior crashed Xvfb is not possible across container restarts. If two ASAAPI containers ran on the same host, they each have separate container namespaces and separate `/tmp`. The `:0` collision concern is bounded by the container isolation. PASS on `:0` collision.

### Signal/cleanup ordering
On `SIGTERM`: `stop()` fires (lines 263-269), kills `server_pid`, but does NOT kill `xvfb_pid`. `stop()` then returns. Bash's trap returns, execution resumes at line 272 `wait "$server_pid"` — which may return quickly if the signal already killed it. Then line 273 kills `tail_pid`, line 274 kills `xvfb_pid`. Xvfb stays alive from `SIGTERM` receipt until line 274 executes — but since the game server is dead by then, there's nothing to display for. This is a minor resource leak window (Xvfb keeps running while we wait for `server_pid` to fully exit) but `wait` is fast and Xvfb is tiny. This is NOT a correctness break; it's a cosmetic ordering concern pre-existing in the `stop()` trap design. PASS on signal/cleanup.

### Round-trip / double-boot
`INSTALL_MARKER` at `entrypoint.sh:23` controls first-boot vs warm-boot paths. The Xvfb fix fires on every boot in the ASAAPI branch, not just first-boot. `/tmp/.X11-unix/` is fresh every container start. The fix is idempotent across reboots. PASS.

---

## Bottom Line

The readiness loop's fall-through is the gap: 5 seconds of silence → proceeds into a Wine launch that is guaranteed to fail the same way the fix intended to prevent, with a success log message and zero diagnostic. Add a post-loop guard — one conditional, four lines — and the fix is correct.
