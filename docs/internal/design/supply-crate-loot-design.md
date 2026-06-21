# Supply Crate Loot Redesign — Design Spec

**Date:** 2026-06-21
**Status:** DRAFT — for Patrick's review/tweak
**Owner:** Patrick
**Target file:** `config/Game.ini` (shared host-volume config; applies to every map in the cluster)

---

## Goal

Replace ARK's vanilla supply-crate loot with hand-authored, themed loot tables that are
**more rewarding than vanilla but not instant-endgame**. Loot climbs by color tier
(white → red), the "ring" (Double) variant of each color is slightly better and slightly
more than its non-ring twin, and the rare jackpot items (top dino saddles, ascendant gear,
element) sit at low weight so they stay exciting.

## Non-negotiables (locked during brainstorm)

1. **All maps, one file.** `ConfigOverrideSupplyCrateItems` lines for crate classes that
   don't exist on the currently-loaded map are **silently ignored** by ASA — so this one
   `Game.ini` carries every map's crate classes, and each map picks up only its own. The
   *same per-tier design* is stamped onto every map's matching class string ("same loot per
   map").
2. **Full override**, not append. Each authored crate fully replaces its vanilla contents.
3. **`SupplyCrateLootQualityMultiplier` → `1.0`** (currently 2.5), with a comment. Quality is
   authored per-crate in the tables below, so the global knob stays neutral and our numbers
   are the real numbers. `FishingLootQualityMultiplier` is a separate system — **untouched**.
4. **BP-at-half rule.** Every *gear* item (tools, weapons, armor, saddles **only**) appears
   twice in a set: the item at weight `W`, and its **blueprint at weight `W/2`** (so the BP
   shows up ~half as often as the item). **The BP rolls the same quality band as the item**
   (mastercraft sword → mastercraft sword BP). Structures, turrets, kibble, resources, ammo,
   and element are **item-only** (no BP — no quality tier / no blueprint exists).
5. **Random, count-limited pools.** Each set lists the *full* menu of tier-appropriate items;
   `MinNumItems`/`MaxNumItems` + `bItemsRandomWithoutReplacement=true` pull only a few at
   random. Nobody can predict a specific drop, and rolling the whole menu at once is
   near-impossible.
6. **Ring (Double) variant** of each color = same table, **+1 item pulled** and **quality
   nudged ~+20%**. Deliberately less than vanilla's flat 2×.
7. **Tek:** engrams stay free (`bAutoUnlockAllEngrams=true` unchanged). **No tek blueprints**
   in drops (pointless — engrams already unlocked; the real tek gate is *element*). Red drops
   a *small* element boost only.

---

## How to read the tables (tweak guide)

- **Weight** = the relative pick-weight that goes in the config (`EntryWeight`). Within a set
  I've normalized weights to sum to ~100, so a weight reads like a "% share of that set."
  **This is the number you tweak.**
- **Pull** = how many items the set draws (`MinNumItems`–`MaxNumItems`), random without
  replacement.
- **~Appears** = rough chance the item shows in a given crate ≈ `avg(Pull) × weight ÷ 100`
  (capped at ~95%). **Approximate** — it's derived from Weight + Pull; tweak the Weight, this
  follows.
- **+BP** in the Item column = a second entry exists for its blueprint at **half** the listed
  weight, same quality band. (Not shown as its own row to keep the table readable.)
- **Set type:** *Guaranteed* sets always fire (`MinNumItems ≥ 1`); *Bonus* sets use
  `MinNumItems=0`, so they're a chance, not a promise.

> Quality bands are named here. Their exact `MinQuality`/`MaxQuality` numbers get mapped and
> **verified at implementation** (the named-tier → numeric mapping is engine-specific). Same
> for every crate/item **class string** — verified per map before it touches `Game.ini`, since
> a typo is a silent no-op.

---

## Tier summary

| Tier | Min lvl | Quality band | Gear pulled (non-ring / ring) | Element |
|------|--------:|--------------|:-----------------------------:|--------:|
| ⚪ White  |  3 | Primitive → Ramshackle      | 1–2 / 2–3 | — |
| 🟢 Green  | 15 | Ramshackle → Apprentice     | 2–3 / 3–4 | — |
| 🔵 Blue   | 25 | Apprentice → Journeyman     | 2–3 / 3–4 | — |
| 🟣 Purple | 35 | Journeyman → Mastercraft    | 3–4 / 4–5 | — |
| 🟡 Yellow | 45 | Mastercraft → low Ascendant | 3–4 / 4–5 | — |
| 🔴 Red    | 60 | Ascendant                   | 4–5 / 5–6 | ~150 / ~200 (ring) |

---

## ⚪ White (lvl 3) — "Scraps" · quality Primitive→Ramshackle

**Gear set — Guaranteed, Pull 1–2**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Stone Pick (+BP)     | 20 | ~30% |
| Stone Hatchet (+BP)  | 20 | ~30% |
| Metal Pick (+BP)     | 12 | ~18% |
| Metal Hatchet (+BP)  | 12 | ~18% |
| Spear (+BP)          | 14 | ~21% |
| Bow (+BP)            | 12 | ~18% |
| Simple Pistol (+BP)  |  6 | ~9%  |
| Slingshot (+BP)      |  4 | ~6%  |

**Structures set — Bonus, Pull 0–1** (item-only)

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Metal Foundation ×2 | 40 | ~20% |
| Metal Wall ×3       | 35 | ~17% |
| Metal Ceiling ×2    | 25 | ~12% |

---

## 🟢 Green (lvl 15) — "Early kit" · quality Ramshackle→Apprentice

**Gear set — Guaranteed, Pull 2–3**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Metal Pick (+BP)     | 14 | ~35% |
| Metal Hatchet (+BP)  | 14 | ~35% |
| Sickle (+BP)         |  8 | ~20% |
| Pike (+BP)           | 14 | ~35% |
| Bow (+BP)            | 12 | ~30% |
| Crossbow (+BP)       | 10 | ~25% |
| Simple Pistol (+BP)  | 10 | ~25% |
| Spear (+BP)          |  8 | ~20% |

**Armor set — Bonus, Pull 0–2**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Hide armor pieces (+BP)  | 55 | ~28% |
| Cloth armor pieces (+BP) | 45 | ~22% |

**Kibble set — Bonus, Pull 0–1** (item-only)

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Basic Kibble ×5    | 40 | ~20% |
| Simple Kibble ×3   | 35 | ~17% |
| Regular Kibble ×2  | 25 | ~12% |

**Resources — Bonus, Pull 0–1** (item-only): Stone Arrows ×40 / ARB ×20 (low weight).

---

## 🔵 Blue (lvl 25) — "Utility" · quality Apprentice→Journeyman

**Gear set — Guaranteed, Pull 2–3**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Journeyman tools (pick/hatchet) (+BP) | 22 | ~55% |
| Crossbow (+BP)        | 14 | ~35% |
| Longneck Rifle (+BP)  | 14 | ~35% |
| Simple Pistol (+BP)   | 10 | ~25% |
| Pike (+BP)            | 10 | ~25% |
| Sword (+BP)           | 12 | ~30% |
| Bow (+BP)             |  8 | ~20% |

**Armor set — Bonus, Pull 0–2**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Chitin armor pieces (+BP) | 60 | ~30% |
| Flak armor pieces (+BP)   | 40 | ~20% |

**Saddle set — Bonus, Pull 0–1** (common dinos)

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Parasaur Saddle (+BP) | 28 | ~14% |
| Raptor Saddle (+BP)   | 26 | ~13% |
| Trike Saddle (+BP)    | 24 | ~12% |
| Carno Saddle (+BP)    | 22 | ~11% |

**Misc set — Bonus, Pull 0–1** (item-only): 1× Auto Turret (low weight), ARB ×50.

---

## 🟣 Purple (lvl 35) — "Strong" · quality Journeyman→Mastercraft

**Gear set — Guaranteed, Pull 3–4**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Mastercraft tools (+BP)    | 18 | ~63% |
| Assault Rifle (+BP)        | 16 | ~56% |
| Pump-Action Shotgun (+BP)  | 14 | ~49% |
| Fabricated Pistol (+BP)    | 14 | ~49% |
| Sword (+BP)                | 12 | ~42% |
| Crossbow (+BP)             | 10 | ~35% |
| Longneck Rifle (+BP)       | 16 | ~56% |

**Armor set — Bonus, Pull 0–2**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Flak armor set (+BP) | 100 | ~35% |

**Saddle set — Bonus, Pull 0–1** (mid-tier dinos)

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Ankylo Saddle (+BP)      | 24 | ~12% |
| Doedicurus Saddle (+BP)  | 22 | ~11% |
| Sabertooth Saddle (+BP)  | 20 | ~10% |
| Carbonemys Saddle (+BP)  | 18 | ~9%  |
| Argentavis Saddle (+BP)  | 16 | ~8%  |

**Misc set — Bonus, Pull 0–1** (item-only): 1–2× Heavy Turret (low weight), ARB ×100.

---

## 🟡 Yellow (lvl 45) — "High-end" · quality Mastercraft→low Ascendant

**Gear set — Guaranteed, Pull 3–4**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Ascendant Pick / Hatchet (+BP) | 16 | ~56% |
| Assault Rifle (mc→asc) (+BP)   | 16 | ~56% |
| Pump-Action Shotgun (+BP)      | 14 | ~49% |
| Fabricated Sniper (+BP)        | 12 | ~42% |
| Compound Bow (+BP)             | 14 | ~49% |
| Sword (+BP)                    | 12 | ~42% |
| Longneck Rifle (+BP)           | 16 | ~56% |

**Armor set — Bonus, Pull 0–2**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Flak armor set (+BP)   | 60 | ~30% |
| Riot armor pieces (+BP)| 40 | ~20% |

**Saddle set — Bonus, Pull 0–1** (high-tier dinos)

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Rex Saddle (+BP)        | 24 | ~12% |
| Spino Saddle (+BP)      | 22 | ~11% |
| Therizino Saddle (+BP)  | 20 | ~10% |
| Megalodon Saddle (+BP)  | 18 | ~9%  |
| Mosasaur Saddle (+BP)   | 16 | ~8%  |

**Misc set — Bonus, Pull 0–1** (item-only): Heavy Turret ×1–2, ARB ×150, Rocket Propelled Grenade ×3.

---

## 🔴 Red (lvl 60) — "Jackpot" · quality Ascendant

**Gear set — Guaranteed, Pull 4–5**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Ascendant tools (+BP)        | 14 | ~63% |
| Ascendant Assault Rifle (+BP)| 14 | ~63% |
| Ascendant Shotgun (+BP)      | 12 | ~54% |
| Fabricated Sniper (+BP)      | 12 | ~54% |
| Compound Bow (+BP)           | 12 | ~54% |
| Longneck Rifle (+BP)         | 12 | ~54% |
| Sword (+BP)                  | 12 | ~54% |

**Armor set — Bonus, Pull 0–2**

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Ascendant Flak set (+BP) | 60 | ~40% |
| Riot armor set (+BP)     | 40 | ~27% |

**Saddle set — Bonus, Pull 0–1** (top-tier dinos — the rare jackpot)

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Rex Saddle (+BP)          | 18 | ~9%  |
| Giganotosaurus Saddle (+BP)| 10 | ~5% |
| Wyvern Saddle (+BP)       | 12 | ~6%  |
| Mosasaur Saddle (+BP)     | 14 | ~7%  |
| Basilosaurus Saddle (+BP) | 14 | ~7%  |
| Spino Saddle (+BP)        | 16 | ~8%  |
| Therizino Saddle (+BP)    | 16 | ~8%  |

**Misc set — Bonus, Pull 0–1** (item-only)

| Item | Weight | ~Appears |
|------|-------:|---------:|
| Element ×150              |  8 | ~4%  |
| Heavy Turret ×2–3         | 30 | ~15% |
| ARB ×250                  | 32 | ~16% |
| Rocket Propelled Grenade ×5 | 30 | ~15% |

---

## Ring (Double) variant rule

Each color's ring crate is its own class string. It reuses the **same `ItemSets`** as the
non-ring color, with two changes baked in:

1. **+1 to every set's pull** (`MinNumItems`/`MaxNumItems` each +1) → more items per crate.
2. **Quality range ~+20%** on every gear entry → slightly better rolls.

Concrete element exception: red+ring drops **~200** element (vs ~150 non-ring), still low weight.

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

1. **Exact crate class strings per map** (`SupplyCrate_Level##_<Map>_C` + the Double/ring
   variants) for every map in the cluster. Source: Beacon / arkcodes / live game files on dell.
   A wrong string = silent no-op.
2. **Item class strings** for every item listed (e.g. `PrimalItem_WeaponRifle_C`).
3. **Quality band → numeric `MinQuality`/`MaxQuality`** mapping per named tier.
4. **Element craft sanity check** — confirm ~150 element is a "head start," not enough to
   trivialize tek, in the context of the 3× boss element rewards already in `Game.ini`.
5. **Saddle availability per map** — drop saddles for dinos that don't exist on a given map
   are harmless (the saddle item still exists), but worth a sanity pass.
