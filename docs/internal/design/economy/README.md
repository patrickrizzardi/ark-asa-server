# Economy & Progression Design

Design docs for the server's **gameplay-tuning systems** — the rules that shape the economy and
player progression. One doc per system; each is the **single authoritative home** for that system's
design + target values. The implementation (generated `config/Game.ini` / ArkShop `config.json`) is
downstream of these docs.

Convention is enforced by [`.claude/rules/documentation.md`](../../../../.claude/rules/documentation.md).

## Docs

| Doc | System | Implementation | Generator |
|---|---|---|---|
| [loot-crates.md](loot-crates.md) | Supply-crate loot (all maps) | `config/Game.ini` (`ConfigOverrideSupplyCrateItems`) | `tools/loot-design.ts` + `gen-loot.ts` |
| [shop.md](shop.md) | ArkShop catalog + points economy | ArkShop `config.json` (tracked seed `config/arkshop.config.json`, deployed each boot) | `tools/shop-design.ts` + `gen-shop.ts` |
| [breeding.md](breeding.md) | Breeding / imprint / maturation rates | `config/Game.ini` (breeding multipliers) | — (hand-edited) |

## Boundaries (what goes where)

- **One doc per gameplay system.** A new tunable system (e.g. taming rates, harvest multipliers,
  stat-per-level) → a new doc here + a row in this index. Don't bolt it onto an existing doc.
- **Cross-link, don't duplicate.** Breeding affects shop *and* loot balance — it's referenced from
  both, but its values live only in `breeding.md` (one home per concern).
- **Design + target values here; implementation is downstream.** These docs are the source of truth;
  the generators turn them into config. Edit the doc, regenerate, don't hand-edit generated config.
