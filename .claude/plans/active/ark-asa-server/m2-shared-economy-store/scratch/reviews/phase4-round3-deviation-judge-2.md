# Deviation Judge — Phase 4 Round 3 Deviation #2 (Xvfb)

## Plan
`ark-asa-server/m2-shared-economy-store`

## Deviation summary
Xvfb started as a background process for AsaApiLoader's X11 requirement; readiness loop waits
on socket file; combined socket+liveness guard (R3 fix) now requires BOTH
`[[ -S /tmp/.X11-unix/X0 ]]` AND `kill -0 "${xvfb_pid}"` before proceeding — replaces the
R2 socket-only guard that the stale-socket BLOCK identified as insufficient.

---

## Verdict: PASS

---

## Adversarial inputs constructed

### Input 1 — TOCTOU: Xvfb alive at `kill -0` time, crashes 50ms later before Wine connects
Scenario: Xvfb starts normally, binds socket, passes both the `-S` check and `kill -0`, guard
passes, `proton run "${launch_exe}" ...` fires — then Xvfb crashes before Wine's `XOpenDisplay`
call completes. Wine gets ECONNREFUSED or NULL from XOpenDisplay.

### Input 2 — PID reuse: Xvfb dies immediately post-bind, OS recycles its PID
Scenario: Xvfb exits right after binding the socket (e.g. post-bind init crash). OS reuses the
PID for a different short-lived process before the `kill -0` check. `kill -0 $xvfb_pid` returns
0 (the new process is alive), `xvfb_dead=0`, socket is still present (not cleaned up) → guard
passes → proton fires → ECONNREFUSED.

### Input 3 — Xvfb binary not installed in image
Scenario: `Xvfb` not in PATH. `Xvfb :0 ... >/dev/null 2>&1 &` backgrounds a shell that
immediately exits 127. Readiness loop exhausts (socket never appears). `kill -0 $xvfb_pid`
fails (shell exited). Guard fires FATAL.

### Input 4 — `/tmp/.X11-unix/X0` already present from prior container incarnation
Scenario: stale socket at `/tmp/.X11-unix/X0` from a previous container run. Xvfb tries to
bind `:0`, gets EADDRINUSE, exits immediately. Readiness loop sees the stale socket immediately
(`break` at iteration 1). `kill -0 $xvfb_pid` → dead → `xvfb_dead=1`. Guard fires FATAL.

### Input 5 — `kill -0` permission check (different user)
Scenario: Xvfb spawned by a different user than the entrypoint runs as. `kill -0 $xvfb_pid`
returns EPERM (not ESRCH), which also causes `|| xvfb_dead=1` to fire, triggering FATAL.

### Input 6 — Unix socket bind-but-before-listen race (slow Xvfb init)
Scenario: Socket file appears (bind complete) but Xvfb hasn't called listen() yet. Wine's
connect() on the Unix socket. Would this yield ECONNREFUSED?

---

## Trace

### Input 1 — TOCTOU trace (the strongest adversarial input)

```
entrypoint.sh:304  Xvfb :0 -screen 0 1024x768x24 -nolisten tcp >/dev/null 2>&1 &
entrypoint.sh:305  xvfb_pid=$!                           # e.g. PID 42
entrypoint.sh:309  readiness loop: socket appears → break at iteration N
entrypoint.sh:319  kill -0 42 2>/dev/null → exits 0     # Xvfb alive HERE
entrypoint.sh:320  [[ ! -S /tmp/.X11-unix/X0 ]] → false
                   [[ "${xvfb_dead}" -eq 1 ]] → false
                   → guard does NOT fire, falls through
entrypoint.sh:332  proton run "${launch_exe}" ... &      # Xvfb crashes ~here
                   Wine XOpenDisplay(":0") → NULL (ECONNREFUSED or connection reset)
                   loader aborts with nodrv_CreateWindow error (stderr visible to proton)
                   proton exits non-zero
entrypoint.sh:348  wait "$server_pid" → returns non-zero
                   (SAVE_ON_STOP fires if set but RCON is not up → rcon fails silently)
                   container exits non-zero
```

Result: LOUD failure. `docker compose up` shows proton/Wine error output, container stops,
orchestrator sees non-zero exit. Single-tenant game server — no silent data loss, no stale
in-flight state. Fully acceptable.

### Input 2 — PID reuse trace

Time window: Xvfb binds socket (socket appears → readiness loop breaks), then Xvfb dies,
then OS reuses PID, then `kill -0` runs. The readiness loop takes up to 5s, so PID reuse
must happen within that same 5s window AND before `kill -0` runs. In a container with
minimal process churn, PID namespace reuse in <5s is effectively impossible — the PID
counter increments monotonically and wraps only at 32768 (or configured max). Would require
thousands of processes to launch-and-die in that window. Structurally impossible in practice.
Verdict for this input: not a real break.

### Input 3 — Xvfb not installed trace

```
entrypoint.sh:304  Xvfb not in PATH → subshell exits 127 (backgrounded: set -e does not abort parent)
entrypoint.sh:305  xvfb_pid=$! → PID of the dead subshell (e.g. 43)
entrypoint.sh:309  readiness loop: /tmp/.X11-unix/X0 never appears → exhausts all 50 iterations (5s)
entrypoint.sh:319  kill -0 43 2>/dev/null → exits 1 (ESRCH, process gone) → xvfb_dead=1
entrypoint.sh:320  [[ ! -S /tmp/.X11-unix/X0 ]] → true → guard fires
entrypoint.sh:321-324  FATAL message + exit 1 (correct)
```

Result: correctly caught. PASS.

### Input 4 — Stale socket from prior container trace

```
/tmp/.X11-unix/X0 exists (stale) before entrypoint runs
entrypoint.sh:304  Xvfb :0 ... & → Xvfb sees EADDRINUSE, exits immediately
entrypoint.sh:305  xvfb_pid=$! → PID of dead Xvfb (e.g. 44)
entrypoint.sh:309  readiness loop: [[ -S /tmp/.X11-unix/X0 ]] → TRUE immediately → break
entrypoint.sh:319  kill -0 44 → exits 1 (ESRCH) → xvfb_dead=1
entrypoint.sh:320  [[ ! -S ... ]] → false  BUT  [[ "${xvfb_dead}" -eq 1 ]] → true → guard fires
entrypoint.sh:321-324  FATAL + exit 1 (correct)
```

Result: correctly caught. PASS. This is actually an improvement over R2 — R2 would have
silently passed this scenario (stale socket from prior run, Xvfb immediately exits).

### Input 6 — Unix socket listen() race trace

`AF_UNIX` semantics: bind() creates the filesystem entry (socket file). listen() and accept()
are called synchronously by Xvfb immediately after bind() in the same process initialization
sequence. The socket file is visible to the filesystem after bind(). A client calling
connect() on an AF_UNIX socket where the server has completed bind() but NOT yet called
listen() gets ECONNREFUSED. However, Xvfb's listen() call follows bind() within the same
synchronous C init sequence — there is no sleep or async handoff between them. By the time
the socket file propagates through the kernel VFS cache and becomes visible to an external
`stat()` call (which the bash `[[ -S ... ]]` check uses), the kernel's processing time for
Xvfb's subsequent listen() call is 0-1 microseconds. The `[[ -S ... ]]` check in the bash
readiness loop has its own syscall overhead (stat + process wakeup) that's orders of
magnitude larger than the bind→listen gap. In practice: if the socket is visible, Xvfb
has already called listen(). Not a realistic break.

---

## Where the fix overshoots (PASS — N/A)

N/A — the fix does not overshoot. It adds the minimum additional check (`kill -0`) needed to
distinguish "alive Xvfb with socket" from "dead Xvfb with stale socket." The check is
correctly scoped inside the `if [[ "${ENABLE_ASAAPI}" == "1" ]]` block.

---

## Strategies attempted

### Mixed inputs
Tried Input 1 (TOCTOU: both conditions met at guard time, Xvfb crashes after). This is the
classic "check passes, then state changes" window. The failure IS real in theory but produces
a LOUD container exit (proton dies, wait returns non-zero). Not a silent failure — does not
require a fix for a single-tenant game server.

Tried Input 4 (stale socket from prior run mixed with immediately-dying new Xvfb). The
liveness check correctly catches the dead process even when socket is present.

### Boundary inputs
- Xvfb not installed (Input 3): caught correctly — xvfb_dead fires, FATAL.
- Display already in use (Input 4): caught correctly — dead Xvfb, xvfb_dead=1, FATAL.
- Empty `xvfb_pid`: not reachable — `$!` always captures a PID when a background job is
  started; even if Xvfb binary is missing, the subshell gets a PID.

### Existing-primitive check
`kill -0 $pid` is the canonical POSIX "process liveness check without sending a signal."
No narrower primitive exists. The SIGUSR1 readiness protocol (used by xvfb-run) is an
alternative but requires modifying the Xvfb startup or wrapping with xvfb-run — significantly
wider than the problem. The `kill -0` idiom is the correct narrow fix.

### Second-caller check
Xvfb is launched exactly once per entrypoint invocation. No second caller exists. N/A.

### Trace-through (TOCTOU)
Traced Input 1 step-by-step above. The TOCTOU window exists but failure is loud:
proton exits non-zero → `wait $server_pid` returns → container stops. Not a silent failure.

### Round-trip / serialization
N/A — no data serialized through the Xvfb path.

### PID reuse
Traced Input 2 — theoretically possible but requires thousands of PIDs to recycle in <5s
inside a container with minimal process churn. Structurally impossible in the deployment
context (single container, light process load).

---

## Round-2 BLOCK resolution confirmation

R2 BLOCK: `[[ -S /tmp/.X11-unix/X0 ]]` passes for a stale socket from Xvfb crash-after-bind;
Wine hits ECONNREFUSED; failure is silent in the entrypoint (exits 0 after proton dies?).

Actually, re-examining: proton run dies → `wait $server_pid` returns non-zero → but
`set -euo pipefail` is still active... wait, `wait` is inside the `main()` function after the
trap is set. The proton process exiting non-zero causes `wait $server_pid` to return non-zero.
With `set -e`, does this abort the script? Yes — unless `wait` is in a conditional. It's
bare: `wait "$server_pid"` at entrypoint.sh:348. Under `set -e`, this would cause an exit.

So even R2's failure mode was NOT silent — it caused a container exit. The distinction R3
adds is catching the failure BEFORE `proton run` fires, with a better error message and
correct Xvfb cleanup. This is a quality improvement over "crash loud with no explanation"
to "FATAL with diagnosis." The R2 BLOCK was correctly raised; the R3 fix is the right
response. The fix is confirmed resolved.

---

## Bottom Line

The R2 stale-socket BLOCK is dead — `kill -0` catches a dead-but-socket-present Xvfb at the
gate, before proton fires. The only residual is a narrow TOCTOU window where Xvfb dies
AFTER the guard but BEFORE Wine connects; that window produces a loud container crash with
visible proton error output, not a silent failure. For a single-tenant game server, that's
acceptable — the operator sees the crash and restarts. PASS.
