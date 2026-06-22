# Todos: ark-asa

Global cross-workstream items only. Granular per-chat work lives in:
- `.claude/plans/active/{slug}/plan.md` for planned work
- `.claude/notes/{slug}/todos.md` for unplanned chat-scoped work

---

## Now (active cross-workstream items)

- [ ] **Shop economy — IN-GAME verify** (deployed + server-verified on dell 2026-06-22, commit 890f659): ArkShop V1.4 loads the generated catalog, server advertising. Patrick to confirm in-game: `/shop` lists catalog, buy a dino (spawns at level), `/buykit starter` claim-once, +250 pts/6min tick. Then: draft boss-tribute kits (`bossKits: []` in `tools/shop-design.ts`, from Beacon) + optional ADR for the ArkShop deploy-from-repo model change. Design SoT: `docs/internal/design/economy/shop.md`. Tweak loop: edit `tools/shop-design.ts` → `cd tools && bun run gen-shop.ts --write` → push → dell pull + restart.

## Soon (committed, not started)

- [ ] {item}

## Later (idea bin — not committed)

- [ ] {item}

## Done (recent)

- [x] **Supply-crate loot redesign — SHIPPED** (2026-06-22): all-8-maps custom loot via `tools/gen-loot.ts` (reads Beacon class-string snapshots in `docs/internal/reference/beacon-asa/`), 111 crate overrides in `config/Game.ini`, deployed + boot-verified clean on dell, playtested + amounts tuned down. Tweak loop: edit `tools/loot-design.ts` → `cd tools && bun run gen-loot.ts --write` → push → dell pull + restart. Design: `docs/internal/design/economy/loot-crates.md`. (Optional ongoing: in-game weight tuning to taste.)
- [x] {item} (2026-06-20)
