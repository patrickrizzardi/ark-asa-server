# Supply Crate Loot Redesign — Design Spec

**Date:** 2026-06-21
**Status:** DRAFT — for Patrick's review/tweak
**Owner:** Patrick
**Target file:** `config/Game.ini` (shared host-volume config; applies to every map in the cluster)

---

## Goal

Replace ARK's vanilla supply-crate loot with hand-authored, themed tables that are **more
rewarding than vanilla but not instant-endgame**. Loot quality climbs by color tier
(white → red), the "ring" (Double) variant of each color is slightly better/more than its
non-ring twin, and the rare jackpot grades (ascendant gear, crown saddles, element) sit at
low weight / low pull so they stay rare.

## Assumed leans (veto if wrong)
- **Kibble** → folded into the Resources group (green+).
- **Metal structures** → dropped (a stack of mats beats a stack of walls).

---

## Locked rules

1. **All maps, one file.** Crate classes absent on the loaded map are **silently ignored** by
   ASA, so this one `Game.ini` carries every map's classes; each map uses only its own. The
   *same per-tier design* is stamped onto every map's matching class string.
2. **Full override** (not append). Each authored crate fully replaces vanilla contents.
3. **`SupplyCrateLootQualityMultiplier` → `1.0`** (was 2.5), commented. Quality is authored
   per-crate below, so the global knob stays neutral. `FishingLootQualityMultiplier` untouched.
4. **Quality is a TIER property, not per-item.** Every gear item + saddle in a tier rolls that
   tier's quality band (set via `MinQuality`/`MaxQuality`). A "pick" is journeyman in blue,
   mastercraft in purple, ascendant in red — same item, quality climbs with color. No per-item
   quality labels.
5. **Ascendant is the rare tail.** Red's quality roll is skewed so most red gear lands high
   (mastercraft-ish) and ascendant is the lucky top edge — *not* the default. Crown items
   (giga saddle, etc.) also carry the lowest weights.
6. **BP-at-half** (gear + saddles only). Each such item appears twice: the item at weight `W`,
   its **blueprint at `W/2`**, **same quality band**. Turrets, resources, ammo, kibble, element
   = item-only (no BP).
7. **Random, count-limited.** Each group lists its full menu; `MinNumItems`/`MaxNumItems` +
   `bItemsRandomWithoutReplacement=true` pull only a few at random.
8. **Gear menu GROWS with tier, lower items persist.** White is a tiny menu; each tier adds
   items; red's menu is *everything* — so a red pull (just 1 item) might be an ascendant pistol
   *or* an ascendant rocket launcher. Luck of the draw on which.
9. **Tek:** engrams stay free (`bAutoUnlockAllEngrams=true` unchanged). No tek BPs. Element is a
   small rare boost in red only.

---

## The 4 groups (per crate)

| # | Group | Fires | Quality? | BP? | Notes |
|---|-------|-------|:--------:|:---:|-------|
| 1 | **Gear** | Guaranteed | Yes (tier band) | Yes | Growing menu; tools weighted > weapons |
| 2 | **Saddles** | Bonus (blue+) | Yes (tier band) | Yes | One master set; crown saddles low weight |
| 3 | **Turrets** | Bonus | No | No | Auto (blue+), Heavy (purple+) |
| 4 | **Resources** | **Guaranteed ≥2** | No | No | Mats + ammo + kibble; qty scales with tier |

---

## Pull counts by tier (items drawn per group)

| Tier | Quality band | Gear (NR/ring) | Saddle (NR/ring) | Turret (NR/ring) | Resource (NR/ring) | Element |
|------|---|:---:|:---:|:---:|:---:|:---:|
| ⚪ White  | Prim→Ram   | 1–2 / 3–4 | — | — | 2–3 / 3–4 | — |
| 🟢 Green  | Ram→App    | 1–2 / 3–4 | — | — | 2–3 / 3–4 | — |
| 🔵 Blue   | App→Jour   | 1–2 / 3–4 | 0–1 / 0–1 | 0–1 / 0–1 | 2–3 / 3–4 | — |
| 🟣 Purple | Jour→MC    | 1–2 / 3–4 | 0–1 / 0–1 | 0–1 / 0–1 | 2–3 / 3–4 | — |
| 🟡 Yellow | MC→low Asc | 1–2 / 3   | 0–1 / 0–1 | 0–1 / 0–1 | 2–3 / 3–4 | — |
| 🔴 Red    | Ascendant  | 1 / 2     | 0–1 / 0–1 | 0–1 / 0–1 | 2–3 / 3–4 | ~150 / ~200 |

> **Ring delta:** gear pulls per the table above (you set these — note ring is non-uniform:
> +2 items at white, +1 at red). Saddle/turret/resource pulls +1 on ring. **Quality +~20% on
> ring** for gear + saddles.

---

## How to read the matrices (tweak guide)

- **Weight** = the relative `EntryWeight` that goes in the config — *this is the knob you tweak.*
  Columns are normalized to ~100, so a weight reads like a "% share of that group at that tier."
- A **blank cell** = item isn't in that tier's menu yet (menu grows left→right).
- **~Chance to appear** ≈ `avg(Pull) × weight ÷ 100` (capped ~95%). Derived from weight + pull.
- **+BP** = a blueprint entry exists at half the listed weight, same quality.

---

## Group 1 — GEAR (weight by rarity; tools > weapons; all +BP)

| Item | Type | ⚪ | 🟢 | 🔵 | 🟣 | 🟡 | 🔴 |
|------|------|---:|---:|---:|---:|---:|---:|
| Pick           | tool   | 24 | 16 | 12 |  9 |  7 |  6 |
| Hatchet        | tool   | 24 | 16 | 12 |  9 |  7 |  6 |
| Sickle         | tool   |  — | 10 |  8 |  6 |  5 |  4 |
| Spear          | weapon | 18 | 10 |  7 |  5 |  4 |  3 |
| Bow            | weapon | 16 | 10 |  7 |  5 |  4 |  3 |
| Simple Pistol  | weapon | 18 | 10 |  8 |  6 |  5 |  4 |
| Pike           | weapon |  — |  8 |  6 |  5 |  4 |  3 |
| Crossbow       | weapon |  — | 10 |  8 |  6 |  5 |  4 |
| Longneck Rifle | weapon |  — |  — | 10 |  8 |  6 |  5 |
| Sword          | weapon |  — |  — |  6 |  5 |  4 |  3 |
| Assault Rifle  | weapon |  — |  — |  — |  8 |  7 |  6 |
| Pump Shotgun   | weapon |  — |  — |  — |  7 |  6 |  5 |
| Fabricated Pistol | weapon | — | — | — |  6 |  5 |  4 |
| Fabricated Sniper | weapon | — | — | — |  — |  7 |  6 |
| Compound Bow   | weapon |  — |  — |  — |  — |  5 |  4 |
| Rocket Launcher| weapon |  — |  — |  — |  — |  — |  4 |
| Hide Armor (set) | armor | — | 10 |  6 |  4 |  3 |  2 |
| Flak Armor (set) | armor | — |  — |  8 |  6 |  5 |  4 |
| Riot Armor (set) | armor | — |  — |  — |  — |  6 |  4 |

*Menu growth: White = pick/hatchet/spear/bow/pistol · Green +sickle/pike/crossbow/hide ·
Blue +longneck/sword/flak · Purple +assault rifle/shotgun/fab pistol · Yellow +fab sniper/
compound bow/riot · Red +rocket launcher (full menu).*

---

## Group 2 — SADDLES (one master set, blue→red; quality = tier; all +BP)

Same set + same weights at every tier blue→red; **only the quality differs** (journeyman in
blue … ascendant in red). Crown saddles kept rare by low weight.

| Saddle | Weight | | Saddle | Weight |
|--------|---:|---|--------|---:|
| Parasaur     | 10 | | Argentavis      | 5 |
| Raptor       | 10 | | Direbear        | 4 |
| Trike        |  9 | | Baryonyx        | 4 |
| Carno        |  8 | | Allosaurus      | 4 |
| Pteranodon   |  7 | | Rex             | 4 |
| Stego        |  7 | | Paracer (plat)  | 3 |
| Sarco        |  6 | | Bronto (plat)   | 3 |
| Ankylosaurus |  6 | | Spino           | 3 |
| Doedicurus   |  5 | | Therizinosaurus | 3 |
| Sabertooth   |  5 | | Megalodon       | 3 |
| Carbonemys   |  4 | | Mosasaur (plat) | 2 |
| Quetzal (plat)| 2 | | Plesiosaur      | 2 |
| Basilosaurus |  2 | | Megalania       | 2 |
| Giganotosaurus| 1 | | Rock Drake      | 1 |
| Managarmr    |  1 | | | |

*Saddles for creatures absent on a given map are harmless no-ops (the item still exists).
Final saddleable-creature list verified per map at implementation.*

---

## Group 3 — TURRETS (bonus, item-only; weight by rarity)

| Item | 🔵 | 🟣 | 🟡 | 🔴 | Qty |
|------|---:|---:|---:|---:|----:|
| Auto Turret  | 70 | 40 | 30 | 25 | 1–2 |
| Heavy Turret |  — | 60 | 70 | 75 | 1–2 |

---

## Group 4 — RESOURCES (guaranteed ≥2; item-only; quantity scales with tier)

Weights pick *which* mats; quantity grows up the ladder. Black pearls gated purple+, element red.

| Resource | Weight | Qty ⚪→🔴 (scales) | Tiers |
|----------|---:|---|---|
| Metal Ingot     | 16 | 30 → 300 | all |
| Silica Pearls   | 12 | 20 → 200 | all |
| Oil             | 10 | 20 → 200 | all |
| Polymer         | 10 | 10 → 150 | all |
| Electronics     | 10 | 10 → 150 | all |
| Crystal         | 10 | 20 → 200 | all |
| Cementing Paste | 10 | 20 → 200 | all |
| Ammo bundle*    | 14 | scales (see note) | all |
| Kibble (variety)|  8 | 3 → 15   | green+ |
| Black Pearls    |  6 | 5 → 50   | **purple+** |
| Element         |  8 | ~150 (red) / ~200 (ring) | **red** |

*Ammo bundle scales: Stone Arrows / Simple ammo (white–green) → Advanced Rifle Bullets
(blue–yellow) → ARB + Rockets (red). Not coupled to the dropped weapon — ARK loot entries roll
independently, so ammo is its own roll.*

---

## The `SupplyCrateLootQualityMultiplier` change

```ini
; Quality is authored per-crate in the ConfigOverrideSupplyCrateItems tables below, so the
; global crate-quality knob stays neutral (1.0) — the table numbers are the real numbers.
SupplyCrateLootQualityMultiplier=1.0
; FishingLootQualityMultiplier is a separate system (fishing-rod loot) — left at 2.50.
```

---

## To verify at implementation (plan stage — not guessed here)

1. **Exact crate class strings per map** (`SupplyCrate_Level##_<Map>_C` + ring/Double variants),
   every map in the cluster. A wrong string = silent no-op.
2. **Item class strings** for every item/resource/saddle/turret listed.
3. **Quality band → numeric `MinQuality`/`MaxQuality`** per tier, **plus the curve that makes
   ascendant the rare tail** (rule 5) — likely via the quality roll power, verified in-game.
4. **Saddleable-creature list per map** (drop saddles for absent dinos are harmless).
5. **Element sanity** — ~150 is a head-start vs the 3× boss element already in `Game.ini`
   (Dragon Alpha 1320, King Titan Alpha 1500), not a shortcut.
