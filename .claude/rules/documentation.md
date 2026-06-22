# Documentation Standards — ark-asa

Extends: `~/.claude/rules/documentation.md` (global). Project-specific additions only.

This project is split into two kinds of docs:

- **Infrastructure docs** — ADRs (`docs/internal/decisions/`), the build-vs-runtime rule, runbooks.
  Governed by the global rule as-is.
- **Gameplay-tuning design docs** — the rules that shape the economy and player progression. These
  get the project-specific layout below.

---

## Gameplay-tuning design docs live in `docs/internal/design/economy/`

The server's gameplay/economy/progression tuning is authored as **design docs**, one per gameplay
system, under `docs/internal/design/economy/`. Each doc is the **single authoritative home** for
that system's design + target values. The implementation — generated `config/Game.ini` blocks and
ArkShop `config.json` — is **downstream** of these docs.

Current docs (index: `docs/internal/design/economy/README.md`):

| Doc | System | Implementation |
|---|---|---|
| `loot-crates.md` | Supply-crate loot (all maps) | `Game.ini` `ConfigOverrideSupplyCrateItems` (via `tools/loot-design.ts` + `gen-loot.ts`) |
| `shop.md` | ArkShop catalog + points economy | ArkShop `config.json` (via `tools/shop-design.ts`, planned) |
| `breeding.md` | Breeding / imprint / maturation rates | `Game.ini` breeding multipliers |

### Rules

1. **One doc per gameplay system.** A new tunable system (taming rates, harvest multipliers,
   stat-per-level, etc.) → a **new doc** in `economy/` + a row in `economy/README.md`. Never bolt a
   second system onto an existing doc.
2. **Each doc is the single home for that system** (global Rule 00). A system's values live in
   exactly one doc. Cross-link with a one-line pointer; never duplicate values across docs. (Example:
   breeding affects shop *and* loot balance — both link to `breeding.md`; the values live only there.)
3. **Design + target values in the doc; implementation downstream.** The doc is the source of truth.
   A generator (`tools/*.ts`) turns it into config. **Edit the doc → regenerate → don't hand-edit
   generated config.** A generated block that drifts from its doc is a bug.
4. **Naming**: kebab-case, named for the gameplay system (`loot-crates.md`, `shop.md`, `breeding.md`).
5. **Class strings** (crate/item/creature/resource) resolve from the local Beacon snapshot
   `docs/internal/reference/beacon-asa/` — never guessed (a wrong class string is a silent no-op).

### When a design doc earns a `[locked]` registry entry

Once a gameplay design doc is approved and its generator built, register it `[locked]` in
`.claude/design-sources.md` so a diff that contradicts it is a gate BLOCK (per the global rule §f).
Draft docs (still being edited) are not registered.
