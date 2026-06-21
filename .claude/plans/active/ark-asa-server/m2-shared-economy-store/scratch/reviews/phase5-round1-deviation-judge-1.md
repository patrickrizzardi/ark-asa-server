# Deviation Judge — Full Report
## Plan: m2-shared-economy-store | Phase 5 | Deviation #1

---

## Deviation Judge: m2-shared-economy-store Phase 5 Deviation #1

### Verdict: BLOCK

### Deviation summary (one line)
`jq` appended to the existing `apt-get install -y --no-install-recommends unzip` line in the Dockerfile (line 18), adding a new build-time dependency to avoid `jq: command not found` at runtime in `inject_plugin_db_config()`.

---

### Adversarial input(s) constructed

1. **Existing-primitive check**: `python3 -c 'import json, sys; ...'` — python3 is available in the `parkervcp/steamcmd:proton` base image AND is already used in the same project's `phase5-runtime-evidence.md` (lines 31 and 80) to read and parse the EXACT `config.json` that `inject_plugin_db_config()` mutates. A `python3 -c` JSON-rewrite one-liner (safe with `--arg`-equivalent `os.environ` reads) would have handled the mutation with zero Dockerfile changes required.

2. **Scope-deviation side-effect check (vanilla build)**: An operator using `ENABLE_ASAAPI=0` (vanilla rollback mode, explicitly supported at `entrypoint.sh:432-437`) builds a vanilla image. The `jq` package is unconditionally baked in (Dockerfile line 18), but `inject_plugin_db_config()` is guarded at `entrypoint.sh:401` — `jq` is never called at runtime. The cost is: (a) image bloat for vanilla users, and (b) if `jq` is ever unavailable in the apt repo at build time (package rename or repo outage), the vanilla build fails for a dependency it doesn't need at runtime.

---

### Trace

#### Adversarial input 1 — Existing primitive (python3)

`phase5-runtime-evidence.md:31` shows the operator running:
```
cat ./plugins-config/ArkShop/config.json | python3 -c "import sys,json; d=json.load(sys.stdin); m=d['Mysql']; ..."
```
on the running container — proving python3 is present at runtime in the base image.

`phase5-runtime-evidence.md:80` shows a second python3 invocation against the same config path.

`inject_plugin_db_config()` at `entrypoint.sh:332-344` mutates `config.json` via:
```bash
jq --arg host "${ARKSHOP_DB_HOST}" \
   --arg user "${ARKSHOP_DB_USER}" \
   --arg pass "${ARKSHOP_DB_PASS}" \
   --arg db   "${ARKSHOP_DB_NAME}" \
   --arg port "${ARKSHOP_DB_PORT}" \
   '.Mysql.UseMysql = true | ...' \
   "${arkshop_cfg}" > "${tmp}" \
&& mv "${tmp}" "${arkshop_cfg}"
```

An equivalent python3 one-liner would read the file, load JSON, mutate keys, write back — with credentials sourced from `os.environ` (same security profile as jq's `--arg`; env vars never touch the shell-interpolation path). This is not speculative — the operator ALREADY uses python3 this way in the verification flow. Zero Dockerfile changes needed.

#### Adversarial input 2 — Vanilla build fails on jq

`entrypoint.sh:30` sets `ENABLE_ASAAPI:=1` (default modded), and `entrypoint.sh:401` gates `inject_plugin_db_config` behind `if [[ "${ENABLE_ASAAPI}" == "1" ]]`. An operator running vanilla (`ENABLE_ASAAPI=0`) never hits line 332 — jq is never executed.

Yet `Dockerfile:18` installs `jq` unconditionally — it runs in every `docker build` invocation regardless of how the operator intends to run the container. If `jq` is unavailable from apt at build time (repo mirror lag, package rename in a future Debian/Ubuntu base, transient network failure), the build fails — even for a vanilla deployment that will never invoke jq.

The fix is scoped to "jq is needed by inject_plugin_db_config" but the wider effect is "jq is a required build-time dependency for all users of this image." The vanilla operator is collateral damage.

---

### Where the fix overshoots

- **Stated problem**: `inject_plugin_db_config()` calls `jq` and the base image doesn't have it — the entrypoint fails with `jq: command not found` when `ENABLE_ASAAPI=1`.
- **Wider effect**: Installing `jq` in the Dockerfile adds an unconditional build-time dependency for ALL builds (including vanilla `ENABLE_ASAAPI=0` builds that never call jq at runtime) AND makes the build fragile to jq apt availability. More critically: it creates a scope deviation to the Dockerfile that was entirely avoidable.
- **Narrower fix that would work**: Replace the jq calls in `inject_plugin_db_config()` with `python3 -c` JSON mutation. `python3` is already present in `ghcr.io/parkervcp/steamcmd:proton` (confirmed: `phase5-runtime-evidence.md:31,80` shows the operator using python3 against the SAME config.json in the SAME container). No Dockerfile change required. The scope deviation to `Dockerfile` is fully avoidable — the plan says "placeholder-substitution or jq approach"; python3's `json` module IS a safe JSON mutation approach with no Dockerfile dependency.

---

### Strategies attempted

N/A — BLOCK verdict. Both strategies that produced findings are documented above.

For completeness:
- **Mixed inputs**: N/A — scope deviation; angle is "does touching this file introduce side effects the plan didn't authorize?" The vanilla build failure is the side effect.
- **Existing-primitive check**: `python3` found in the operator's own runtime evidence at `phase5-runtime-evidence.md:31,80` — the narrower primitive exists and was already used in this exact flow.
- **Boundary inputs**: Checked vanilla mode (`ENABLE_ASAAPI=0`) as the smallest non-default config — jq never called but always installed.
- **Second-caller check**: Not applicable (single Dockerfile, single entrypoint).
- **Round-trip / serialization**: Not applicable (apt install is a one-way bake).

---

### Bottom Line

The executor reached for jq (reasonable tool), didn't notice python3 was already there in the base image doing JSON reads on the same file in the same test session. The Dockerfile touch was avoidable — swap jq for python3 in `inject_plugin_db_config()` and the scope deviation disappears entirely.
