# Todos: ark-asa

Global cross-workstream items only. Granular per-chat work lives in:
- `.claude/plans/active/{slug}/plan.md` for planned work
- `.claude/notes/{slug}/todos.md` for unplanned chat-scoped work

---

## Now (active cross-workstream items)

- [ ] {item}

## Soon (committed, not started)

- [ ] {item}

## Later (idea bin — not committed)

- [ ] {item}

## Done (recent)

- [x] **Supply-crate loot redesign — SHIPPED** (2026-06-22): all-8-maps custom loot via `tools/gen-loot.ts` (reads Beacon class-string snapshots in `docs/internal/reference/beacon-asa/`), 111 crate overrides in `config/Game.ini`, deployed + boot-verified clean on dell, playtested + amounts tuned down. Tweak loop: edit `tools/loot-design.ts` → `cd tools && bun run gen-loot.ts --write` → push → dell pull + restart. Design: `docs/internal/design/supply-crate-loot-design.md`. (Optional ongoing: in-game weight tuning to taste.)
- [x] {item} (2026-06-20)
