# Breeding & Imprint Tuning

**Status**: tuned in `config/Game.ini` (lines 39–48); two proposed nudges below pending Patrick.
**System**: breeding / imprint / maturation rates (`Game.ini`). A distinct gameplay system that
affects **both** shop and loot balance, so it lives in its own doc.
**Related**: shop economy → [shop.md](shop.md); supply-crate loot → [loot-crates.md](loot-crates.md).

> **Why this matters to the economy**: shop dinos spawn FLAT (no imprint, no taming bonus — see
> [shop.md](shop.md) §1). The imprint payoff below is what makes a home-bred, fully-imprinted dino
> strictly out-class anything bought or tamed. That gap **is** the no-pay-to-win spine — breeding
> stays the real path to power.

---

## North star

Built for **working adults** (a few hours a day, most 2–3×/week). Breeding must be **finishable in a
session** — fast maturation + enough cuddles to fully imprint before the baby grows up — or the
imprint reward is unreachable for exactly the players this server is for.

---

## Current values + proposed nudges

| Setting | Current | Proposed | Note |
|---|---|---|---|
| `BabyImprintingStatScaleMultiplier` | 3 | **3 (keep)** | 100% imprint ≈ **+60%** stats — big breeding reward (Patrick's call over ~20%). This is the bred-beats-bought gap. |
| `BabyImprintAmountMultiplier` | 3 | 3 | fewer cuddles to hit 100% — good for casual |
| `BabyMatureSpeedMultiplier` | 300 | 300 | baby→adult in minutes — good for casual |
| `EggHatchSpeedMultiplier` | 30 | 30 | fast hatch |
| `MatingIntervalMultiplier` | 0.001 | 0.001 | near-instant re-mate |
| `MatingSpeedMultiplier` | 5 | 5 | fast mating |
| `BabyCuddleIntervalMultiplier` | 0.01 | 0.01 | cuddles come fast enough to fully imprint in the short maturation window |
| `BabyCuddleGracePeriodMultiplier` | 0.1 | 0.1 | — |
| `BabyCuddleLoseImprintQualitySpeedMultiplier` | 2 | **1** _(proposed)_ | =2 punishes a missed cuddle 2× as fast — harsh for a 2–3×/week audience |
| `LayEggIntervalMultiplier` | 7 | **? review** | =7 makes eggs lay **7× less often** — throttles *kibble-egg farming*, not breeding. Intended? If you want easy kibble taming, lower it. |
| `BabyFoodConsumptionSpeedMultiplier` | 1.0 | 1.0 | — |

---

## Synergy check (verify at boot — not yet tested)

`BabyMatureSpeedMultiplier=300` shrinks the maturation window to minutes. For 100% imprint to be
reachable in that window, the cuddle cadence (`BabyCuddleIntervalMultiplier=0.01`) + per-cuddle
amount (`BabyImprintAmountMultiplier=3`) must fit enough cuddles in. Looks right on paper; confirm
on dell by breeding one dino end-to-end and checking it can hit 100%.

---

## Open items

- `LayEggIntervalMultiplier=7` — confirm intended (kibble-egg throttle, not a breeding knob).
- `BabyCuddleLoseImprintQualitySpeedMultiplier` 2 → 1 — confirm the softer setting.
- Boot-test the full breed→imprint loop reaches 100% inside the maturation window.
