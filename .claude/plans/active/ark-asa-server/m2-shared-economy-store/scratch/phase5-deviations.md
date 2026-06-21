# m2-shared-economy-store Phase 5 Deviations — captured 2026-06-21

D_count: 7

## Scope Deviations (verbatim from executor report)

- **Scope Deviation #1** (file: `Dockerfile`): touched outside declared Phase 5 scope. Rationale: `inject_plugin_db_config()` requires `jq` for safe JSON mutation; `jq` is not in the `parkervcp/steamcmd:proton` base image; without adding it to the Dockerfile apt layer the entrypoint fails at boot with `jq: command not found`. The plan says "Use a placeholder-substitution or `jq` approach" — jq was chosen; the Dockerfile is the only place to bake it. Diff hunks: `Dockerfile:18`.
- **Scope Deviation #2** (file: `.gitignore`): touched outside declared Phase 5 scope. Rationale: `inject_plugin_db_config()` writes the live DB password into `./plugins-config/ArkShop/config.json` on the host bind at runtime; without a gitignore rule an operator could accidentally `git add .` and commit the injected credentials. The quality gate explicitly requires "DB password never committed." Diff hunks: `.gitignore:8-10`.
- **Scope Deviation #3** (file: `plugins-config/.gitkeep`): file created outside declared Phase 5 scope. Rationale: `./plugins-config/` must exist as a directory on the host before `docker compose up` or Docker creates it as root (breaking the non-root `container` user's ability to write into it at runtime). A tracked `.gitkeep` ensures the directory exists in the checkout. Diff hunks: `plugins-config/.gitkeep:1` (empty file).
- **Scope Deviation #4** (file: `.claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md`): plan notes updated with Phase 5 execution decisions. Rationale: standard practice per this plan's established pattern (all prior phases recorded their decisions here); the notes are the churn log for the plan coordinator. Diff hunks: `notes.md:146-174`.

## Approach Deviations (verbatim from executor report)

- **Deviation #1** (Step 1): plan said `reuse ./config or add ./plugins-config`, executor did `chose ./plugins-config/ (separate dir)`. Rationale: `./config` holds engine INI files symlinked to `…/Saved/Config/WindowsServer`; plugin `config.json` files are a distinct concern with a distinct target path (`ArkApi/Plugins/*/`); mixing them would make the `./config` bind purpose ambiguous and require the WindowsServer symlink to coexist with plugin subdirs in the same host dir. Separate dirs = separate concerns = cleaner mental model for operators. Diff hunks: `entrypoint.sh:266-289, docker-compose.yml:83`.
- **Deviation #2** (Step 2): plan said `Use a placeholder-substitution or jq approach`, executor did `used jq with --arg for all creds (no sed/placeholder substitution)`. Rationale: sed-based placeholder substitution on JSON is fragile — special characters in passwords (quotes, backslashes, forward slashes) corrupt the JSON or require extensive escaping; jq's `--arg` passes values as typed strings with no shell or jq-expression interpretation, making it safe for arbitrary password values. The `tonumber` coercion for MysqlPort preserves the integer JSON type ArkShop expects. Diff hunks: `entrypoint.sh:329-368, Dockerfile:18`.
- **Deviation #3** (Step 3): plan said `Look up + add the ASA API Utils CurseForge mod ID to MODS`, executor did `auto-appended 955333 to MODS in the ENABLE_ASAAPI=1 branch with de-duplication rather than baking it into the MODS default`. Rationale: baking it into `MODS=955333` as the default would silently add the mod to vanilla (ENABLE_ASAAPI=0) boots too (the vanilla path also passes `-mods=${MODS}` when MODS is non-empty). Gating the append inside `if ENABLE_ASAAPI==1` ensures the mod is only passed when ArkShop is actually running. The de-duplication check prevents a doubled entry if the operator already lists 955333 in their `.env`. Diff hunks: `entrypoint.sh:400-413`.

## Resolved spawn list (orchestrator's parsed view)

### Deviation #1
- **type**: scope
- **rationale**: jq required for safe JSON mutation; not in base image; added to Dockerfile apt layer (only place to bake it).
- **diff hunks**: Dockerfile:18
- **carry status**: fresh

### Deviation #2
- **type**: scope
- **rationale**: plugins-config/** gitignored (except .gitkeep) so the runtime-injected DB password in ArkShop/config.json can't be accidentally committed.
- **diff hunks**: .gitignore:8-10
- **carry status**: fresh

### Deviation #3
- **type**: scope
- **rationale**: plugins-config/.gitkeep created so the host bind-mount dir exists pre-`up`, preventing root-owned dir creation that would block the non-root container user.
- **diff hunks**: plugins-config/.gitkeep:1
- **carry status**: fresh

### Deviation #4
- **type**: scope
- **rationale**: notes.md updated with Phase 5 execution decisions (established churn-log pattern for this plan).
- **diff hunks**: .claude/plans/active/ark-asa-server/m2-shared-economy-store/notes.md:146-174
- **carry status**: fresh

### Deviation #5
- **type**: approach
- **rationale**: chose separate ./plugins-config/ dir (not reusing ./config) — separate concerns (engine INI vs plugin config.json), distinct target paths, cleaner operator model.
- **diff hunks**: entrypoint.sh:266-289, docker-compose.yml:83
- **carry status**: fresh

### Deviation #6
- **type**: approach
- **rationale**: jq --arg for all creds (no sed/placeholder) — safe for special chars in passwords; tonumber coercion keeps MysqlPort integer-typed.
- **diff hunks**: entrypoint.sh:329-368, Dockerfile:18
- **carry status**: fresh

### Deviation #7
- **type**: approach
- **rationale**: auto-append 955333 to MODS inside ENABLE_ASAAPI=1 branch with de-dup — avoids adding the mod to vanilla boots; prevents doubled entry if operator already lists it.
- **diff hunks**: entrypoint.sh:400-413
- **carry status**: fresh
