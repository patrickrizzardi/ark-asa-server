# Todos: ark-asa

Global cross-workstream items only. Granular per-chat work lives in:
- `.claude/plans/active/{slug}/plan.md` for planned work
- `.claude/notes/{slug}/todos.md` for unplanned chat-scoped work

---

## Now (active cross-workstream items)

- [ ] **Deploy + verify the supply-crate loot redesign** (built/integrated 2026-06-21, commit eb26ba9; design `docs/internal/design/supply-crate-loot-design.md`, generator `tools/gen-loot.ts`). Pending Patrick home: (1) push → pull on dell → restart; (2) boot/syntax check (watch logs, settles Game.ini comment-survival); (3) in-game: pop crates per tier, confirm loot matches the design (only proof class strings resolve live). Then tune weights in `tools/loot-design.ts` → `bun run gen-loot.ts --write` → redeploy.

## Soon (committed, not started)

- [ ] {item}

## Later (idea bin — not committed)

- [ ] {item}

## Done (recent)

- [x] {item} (2026-06-20)
