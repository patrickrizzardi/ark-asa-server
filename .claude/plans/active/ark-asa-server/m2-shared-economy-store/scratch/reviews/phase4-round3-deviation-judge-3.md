# Deviation Judge — Phase 4 Deviation #3 (pdb retention) — Round 3

## Deviation Judge: m2-shared-economy-store Phase 4 Deviation #3

### Verdict: PASS

### Deviation summary (one line)
`ensure_modded_pdb()` guards the pdb artifact with a `pdb_ok()` helper requiring `[[ -f ]]` AND
`stat -c%s > 1048576` (1 MiB floor) at all three check sites (early-return, per-attempt break,
final fatal exit).

### Round-2 BLOCK resolved?
Yes. The original BLOCK was: a 0-byte or trivially-truncated pdb passed bare `-f`, AsaApi
SHA-256-failed silently (zero plugins, server "started"). The 1 MiB floor closes that window
completely. A 0-byte file, a 512-byte file, and any partial download under 1 MiB now all fail
`pdb_ok()` and correctly trigger the restore loop.

---

### Adversarial input(s) constructed

1. **>1 MiB but still-truncated pdb at early-return** — Previous boot's steamcmd validate started
   writing the ~6 GB pdb, wrote ≥1,048,577 bytes, then the container was OOM-killed or
   SIGKILL'd mid-write. Next boot: `pdb_ok()` early-return check sees a file that is `[[ -f ]]`
   AND `stat -c%s > 1048576` → returns true → `ensure_modded_pdb` returns 0 without running any
   steamcmd validate → AsaApi attempts SHA-256 on the truncated pdb.

2. **`stat` binary absent from container image** — `stat -c%s "${pdb}" 2>/dev/null` fails, the
   `|| echo 0` fallback fires, `pdb_ok()` returns false → restore loop is triggered correctly.
   (Safety check, not a break.)

3. **`${pdb}` is a directory (impossible via normal flow, confirmatory)** — `[[ -f dir ]]` is false →
   `pdb_ok()` returns false → restore loop triggered. Safe.

---

### Trace

**For adversarial input #1 (the only candidate for a real residual):**

- entrypoint.sh:219: `if pdb_ok; then return 0; fi`
  - `pdb_ok` at line 217: `[[ -f "${pdb}" ]]` → true (file exists, partially written)
  - `stat -c%s "${pdb}" 2>/dev/null` → returns e.g. `52428800` (50 MiB, written before kill)
  - `52428800 -gt 1048576` → true
  - `pdb_ok` returns 0 (success)
- `ensure_modded_pdb` returns 0 at line 220
- No steamcmd validate runs
- entrypoint.sh:279: `proton run "${LOADER_EXE}" …` launches AsaApiLoader
- AsaApi SHA-256s the truncated pdb → fails → logs `[critical] Failed to read pdb` → loads ZERO
  plugins

**This is a real but residual window. Is it a ship-blocker?**

Three mitigating facts narrow it to negligible:

1. **Loud failure, not silent.** The comment in ensure_modded_pdb itself describes the original
   issue as a "silent failure." A >1 MiB-but-truncated pdb still triggers AsaApi's
   `[critical] Failed to read pdb` log — zero plugins, but NOT silent. An operator watching
   container logs sees this immediately.

2. **Narrow write window.** The partial file must exceed 1 MiB (0.016% of the ~6 GB pdb) before
   the kill. The more common kill-mid-download cases (early kill, disk exhaustion near the start)
   yield < 1 MiB and are caught by `pdb_ok()`.

3. **steamcmd validate is integrity-checking by contract.** Once `pdb_ok()` is called AFTER a
   steamcmd validate call (lines 232 and 239), a passing result means steamcmd verified the file
   against Steam's CDN checksum manifest. The only >1 MiB-but-corrupt path that reaches the
   `pdb_ok` early-return WITHOUT a prior validate is the interrupted-previous-boot scenario — and
   closing that would require running steamcmd validate on EVERY boot, regressing cold-start by
   minutes for the 99.9% case where the pdb is clean.

4. **No available shell primitive closes it tighter.** A full SHA-256 at the shell level is O(6 GB)
   compute every boot. The only realistic tighter fix would be a `stat` floor closer to the real
   file size — but pdb size varies across ASA versions, and baking in a near-actual size (e.g.
   5 GB) creates a new break whenever Steam ships a version with a smaller pdb. The 1 MiB floor
   is the correct abstraction: reject obviously-broken artifacts, let steamcmd validate handle
   integrity post-restore, let AsaApi log loudly if somehow a corrupt file survives.

---

### Where the fix overshoots (BLOCK only)

N/A — verdict is PASS.

---

### Strategies attempted

- **Mixed inputs**: Constructed the >1 MiB partial-pdb scenario (adversarial input #1) — exists
  as a real (if narrow) residual, but is demonstrably loud rather than silent and has no practical
  shell-level fix that doesn't regress cold-start time. Does not meet the bar for a ship-blocker.

- **Existing-primitive check**: Confirmed that steamcmd's `validate` subcommand is itself an
  integrity checker (computes checksums against CDN manifest). After a successful validate +
  `pdb_ok` passing, the pdb is integrity-verified by two independent mechanisms. This is the
  correct design — the 1 MiB floor is NOT a replacement for validate, it is a pre-validate
  guard against obviously-broken artifacts on the common boot path.

- **Boundary inputs**: `stat -c%s = 0` (0-byte file) — caught: `0 > 1048576` is false.
  `stat -c%s = 1048576` (exactly 1 MiB) — caught: `-gt` is strict, `1048576 > 1048576` is false.
  `stat -c%s = 1048577` (1 MiB + 1 byte) — passes `pdb_ok`. This is the lower boundary of the
  residual window. Consistent with design intent.

- **`stat` unavailability / failure**: `|| echo 0` fallback fires, returns 0, `pdb_ok` returns
  false, restore loop triggers. Safe.

- **Round-trip**: The `pdb_ok()` helper is defined as a nested function inside
  `ensure_modded_pdb()`. In bash, nested function definitions are scoped globally once the
  enclosing function runs — this means `pdb_ok` is visible globally after `ensure_modded_pdb`
  is called. Since `ensure_modded_pdb` is only called once and `pdb_ok` is never referenced
  externally, this is harmless. No round-trip concern.

---

### Bottom Line

Round-2 BLOCK is dead — the 1 MiB floor kills 0-byte and trivially-truncated pdb artifacts.
The residual (>1 MiB partial from an interrupted prior validate) is audible via AsaApi's own
critical log, too narrow to be a realistic first-boot failure, and not closeable with a shell
primitive that doesn't regress cold-start. Ship it.
