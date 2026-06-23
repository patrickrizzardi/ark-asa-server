# Todos: ark-asa

Global cross-workstream items only. Granular per-chat work lives in:
- `.claude/plans/active/{slug}/plan.md` for planned work
- `.claude/notes/{slug}/todos.md` for unplanned chat-scoped work

---

## Now (active cross-workstream items)

- [ ] **Shop economy — IN-GAME verify** (deployed + server-verified on dell, latest commit 169757b): ArkShop V1.4 loads the full catalog — 37 dinos, 19 resources, 6 kibble, mindwipe, **5 kits** (starter+weapons free 3-claim; taming 3k / defense 5k / underwater-taming 4k, all buy-5×); **all store dinos neutered** (no breeding bought dinos). Code reviewed + `tools/beacon.ts` extracted (DRY); docs in sync. Patrick to confirm IN-GAME: `/shop` lists, buy a dino (neutered, right level), `/buykit starter` 3× then refused, +250pts/6min, kits give correct contents. **Still open**: (a) boss-tribute kits (`bossKits: []`, draft from Beacon); (b) "other food / other kits" ideas Patrick floated; (c) optional ADR for deploy-from-repo model; (d) optional `bun-types` tsconfig tidy. Tweak loop: edit `tools/shop-design.ts` → `cd tools && bun run gen-shop.ts --write` → push → dell pull + restart.

## Soon (committed, not started)

- [ ] {item}

## Later (idea bin — not committed)

- [ ] {item}

## Done (recent)

- [x] **Supply-crate loot redesign — SHIPPED** (2026-06-22): all-8-maps custom loot via `tools/gen-loot.ts` (reads Beacon class-string snapshots in `docs/internal/reference/beacon-asa/`), 111 crate overrides in `config/Game.ini`, deployed + boot-verified clean on dell, playtested + amounts tuned down. Tweak loop: edit `tools/loot-design.ts` → `cd tools && bun run gen-loot.ts --write` → push → dell pull + restart. Design: `docs/internal/design/economy/loot-crates.md`. (Optional ongoing: in-game weight tuning to taste.)
- [x] {item} (2026-06-20)
