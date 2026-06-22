# Supply Crate Loot Redesign — Design Spec

**Date:** 2026-06-21
**Status:** APPROVED 2026-06-21 — ready for implementation plan
**Owner:** Patrick
**Target file:** `config/Game.ini` (shared host-volume config; applies to every map in the cluster)

---

## Goal

Replace ARK's vanilla supply-crate loot with hand-authored, themed tables — **more rewarding
than vanilla but not instant-endgame**. Quality climbs by color tier (white → red); the "ring"
(Double) variant of each color is slightly better/more than its non-ring twin; the rare jackpot
grades (ascendant power gear, crown/tek saddles, element) sit at low weight / low pull.

---

## Locked rules

1. **All maps, one file.** Crate classes absent on the loaded map are **silently ignored** by
   ASA, so one `Game.ini` carries every map's classes; each map uses only its own. The same
   per-tier design is stamped onto every map's matching class string.
2. **Full override** (not append). Each authored crate fully replaces vanilla contents.
3. **`SupplyCrateLootQualityMultiplier` → `1.0`** (was 2.5), commented. Quality is authored
   per-item below. `FishingLootQualityMultiplier` untouched.
4. **Quality model — tier band is the default, with deliberate per-item exceptions:**
   - **Cheap gear** (stone tools, spear/bow/slingshot/pistol/pike, hide/cloth armor) — quality
     ceiling **raised**: a great cheap item is still cheap, so allow high quality *early*.
   - **Power gear** (metal tools, longneck/sword/crossbow, assault rifle/shotgun/fab pistol/fab
     sniper/compound bow/rocket launcher, flak/riot armor) — quality ceiling **gated**: capped
     well below the tier when first introduced, reaching ascendant only at red.
   - **Ascendant is the rare tail**, never the default — even at red the roll skews high-but-not-
     guaranteed-ascendant, and crown/tek items carry the lowest weights.
5. **Stone vs metal tools (worked example of rule 4):**

   | Tool | ⚪ | 🟢 | 🔵 | 🟣 | 🟡 | 🔴 |
   |------|----|----|----|----|----|----|
   | Stone Pick / Hatchet | ≤Mastercraft | ≤Mastercraft | ≤Ascendant | (phased out) | — | — |
   | Metal Pick / Hatchet / Sickle | — | — | App–Journey | Journey–MC | MC–low Asc | Ascendant |

   (No "stone sickle" exists — sickle is metal-track, blue+.)
6. **BP-at-half** (gear + saddles only). Item at weight `W`, its **blueprint at `W/2`, same
   quality**. Turrets, resources, ammo, kibble, structures, element = item-only.
7. **Random, count-limited.** Each group lists its menu; `MinNumItems`/`MaxNumItems` +
   `bItemsRandomWithoutReplacement=true` pull a few at random.
8. **Gear menu GROWS with tier, lower items persist.** Red's menu is *everything* — a red pull
   (just 1) might be an ascendant pistol *or* an ascendant rocket launcher.
9. **Tek:** engrams stay free (`bAutoUnlockAllEngrams=true` unchanged). No tek *gear* BPs.
   Element = small rare boost in red only. Tek *saddles* = red-only crown (rule 11).

---

## The 5 groups (per crate)

| # | Group | Fires | Quality? | BP? | Notes |
|---|-------|-------|:--------:|:---:|-------|
| 1 | **Gear** | Guaranteed | Yes (per rule 4) | Yes | Growing menu; tools weighted > weapons |
| 2 | **Saddles** | Bonus (blue+) | Yes (tier band) | Yes | Power-banded; crown/tek lowest weight |
| 3 | **Turrets** | Bonus | No | No | Auto (blue+), Heavy (purple+) |
| 4 | **Resources** | **Guaranteed ≥2** | No | No | Mats + ammo + kibble; qty scales; black pearls purple+, element red |
| 5 | **Structures** | Bonus (base-kit 0–3) | No | No | Stone (white/green) → metal (blue+); foundations/walls/ceilings/doors/gates |

---

## Pull counts by tier

| Tier | Quality band | Gear (NR/ring) | Saddle | Turret | Resource | Structure | Element |
|------|---|:---:|:---:|:---:|:---:|:---:|:---:|
| ⚪ White  | Prim→Ram   | 1–2 / 3–4 | — | — | 2–3 / 3–4 | 0–3 | — |
| 🟢 Green  | Ram→App    | 1–2 / 3–4 | — | — | 2–3 / 3–4 | 0–3 | — |
| 🔵 Blue   | App→Jour   | 1–2 / 3–4 | 0–1 | 0–1 | 2–3 / 3–4 | 0–3 | — |
| 🟣 Purple | Jour→MC    | 1–2 / 3–4 | 0–1 | 0–1 | 2–3 / 3–4 | 0–3 | — |
| 🟡 Yellow | MC→low Asc | 1–2 / 3   | 0–1 | 0–1 | 2–3 / 3–4 | 0–3 | — |
| 🔴 Red    | Ascendant  | 1 / 2     | 0–1 | 0–1 | 2–3 / 3–4 | 0–3 | ~150 / ~200 |

> **Ring delta:** gear pulls per table (non-uniform: +2 at white, +1 at red). Saddle/turret/
> resource/structure pulls +1 on ring. **Quality +~20% on ring** for gear + saddles.

---

## How to read the matrices (tweak guide)

- **Weight** = relative `EntryWeight` (the knob). Columns ~normalized to 100 (= "% share").
- **Blank cell** = item not in that tier's menu yet (menu grows left→right).
- **Class** (gear only): **C**heap = high quality early; **P**ower = quality gated (rule 4).
- **+BP** = blueprint entry at half the weight, same quality.

---

## Group 1 — GEAR (weight by rarity; tools > weapons; all +BP)

| Item | Type | Class | ⚪ | 🟢 | 🔵 | 🟣 | 🟡 | 🔴 |
|------|------|:--:|---:|---:|---:|---:|---:|---:|
| Stone Pick     | tool | C | 22 | 14 |  6 |  — |  — |  — |
| Stone Hatchet  | tool | C | 22 | 14 |  6 |  — |  — |  — |
| Metal Pick     | tool | P |  — |  — | 12 |  9 |  7 |  6 |
| Metal Hatchet  | tool | P |  — |  — | 12 |  9 |  7 |  6 |
| Sickle         | tool | P |  — |  — |  8 |  6 |  5 |  4 |
| Spear          | weapon | C | 16 | 10 |  6 |  4 |  3 |  2 |
| Bow            | weapon | C | 14 | 10 |  6 |  4 |  3 |  2 |
| Simple Pistol  | weapon | C | 16 | 10 |  7 |  5 |  4 |  3 |
| Slingshot      | weapon | C | 10 |  4 |  2 |  1 |  1 |  1 |
| Pike           | weapon | C |  — |  8 |  6 |  5 |  4 |  3 |
| Crossbow       | weapon | P |  — | 10 |  8 |  6 |  5 |  4 |
| Longneck Rifle | weapon | P |  — |  — | 10 |  8 |  6 |  5 |
| Sword          | weapon | P |  — |  — |  6 |  5 |  4 |  3 |
| Assault Rifle  | weapon | P |  — |  — |  — |  8 |  7 |  6 |
| Pump Shotgun   | weapon | P |  — |  — |  — |  7 |  6 |  5 |
| Fabricated Pistol | weapon | P | — | — |  — |  6 |  5 |  4 |
| Fabricated Sniper | weapon | P | — | — |  — |  — |  7 |  6 |
| Compound Bow   | weapon | P |  — |  — |  — |  — |  5 |  4 |
| Rocket Launcher| weapon | P |  — |  — |  — |  — |  — |  4 |
| Hide Armor (set) | armor | C | — | 10 |  6 |  4 |  3 |  2 |
| Flak Armor (set) | armor | P | — |  — |  8 |  6 |  5 |  4 |
| Riot Armor (set) | armor | P | — |  — |  — |  — |  6 |  4 |

*Cheap items (C) may roll above the tier band (a mastercraft bow in green is fine); Power items
(P) are capped low when introduced and only reach ascendant at red — exact per-item
MinQuality/MaxQuality mapped at implementation.*

---

## Group 2 — SADDLES (power-banded, blue→red; quality = tier band; all +BP)

Same bands + weights every tier blue→red; **only quality differs** (journeyman in blue …
ascendant in red). Crown/Tek kept rare by weight. **The full saddle-item roster is auto-pulled
from Beacon at implementation and each creature assigned to a band** — bareback/no-saddle
creatures (wyvern, managarmr, griffin, shadowmane, gigantopithecus, direwolf, etc.) filtered out.

**Full enumeration** of every rideable creature from the ARK roster, banded by power. Bareback
creatures (no saddle item) are listed separately and excluded. `(?)` = saddle-vs-bareback call
I'm not 100% on — final saddle-item existence verified against Beacon at build.

**Common (weight 10)** — early / utility
parasaur, raptor, triceratops, carnotaurus, stegosaurus, sarco, pteranodon, pachy, phiomia,
morellatops, iguanodon, gallimimus, pulmonoscorpius, pelagornis, ichthyosaurus, megaloceros,
procoptodon, equus, manta, diplocaulus, moschops, terror bird, aurochs, kairuku(?), dimorphodon(?)

**Mid (weight 5)** — combat / utility
ankylosaurus, doedicurus, sabertooth, argentavis, baryonyx, carbonemys, **Dunkleosteus**,
**Velonasaur**, thorny dragon, kaprosuchus, dire bear, mammoth, woolly rhino, castoroides,
chalicotherium, daeodon, megatherium, beelzebufo, arthropluera, araneo, deinonychus,
pachyrhinosaurus, snow owl, tapejara, tropeognathus, ravager, thylacoleo, mantis, lymantria,
desmodus, andrewsarchus, maewing, megalania, megalosaurus, sarco, anglerfish

**High (weight 3)** — heavy hitters / platforms
rex, spino, therizinosaur, megalodon, mosasaurus, plesiosaur, **Tusoteuthis**, basilosaurus,
allosaurus, yutyrannus, carcharodontosaurus, acrocanthosaurus, amargasaurus, basilisk,
astrodelphis, magmasaur, quetzal (platform), brontosaurus (platform), paraceratherium (platform),
diplodocus (platform)

**Crown (weight 1)** — endgame
giganotosaurus, rock drake, megachelon (platform), astrocetus (platform), titanosaur (platform)

**Tek (RED only, weight 1)**
Rex Tek, Mosasaur Tek, Megalodon Tek, Rock Drake Tek, Tapejara Tek

**Bareback — rideable but NO saddle item, EXCLUDED:**
direwolf, wyvern (all variants), griffin, managarmr, shadowmane, ferox, gigantopithecus, gasbags,
reaper, bloodstalker, phoenix, liopleurodon, crystal wyvern, gacha, karkinos, roll rat,
rock elemental, ice golem. *(Mek/Enforcer/Exo-Mek/Tek Stryder = crafted/special, not saddle.)*

---

## Group 3 — TURRETS (bonus, item-only)

| Item | 🔵 | 🟣 | 🟡 | 🔴 | Qty |
|------|---:|---:|---:|---:|----:|
| Auto Turret  | 70 | 40 | 30 | 25 | 1–2 |
| Heavy Turret |  — | 60 | 70 | 75 | 1–2 |

---

## Group 4 — RESOURCES (guaranteed ≥2; item-only; quantity scales with tier)

Weights pick *which* mats; quantity grows up the ladder. Black pearls gated purple+, element red.

| Resource | Weight | Qty ⚪→🔴 | Tiers |
|----------|---:|---|---|
| Metal Ingot     | 15 | 10 → 100 | all |
| Silica Pearls   | 12 | 10 → 50 | all |
| Oil             | 10 | 10 → 50 | all |
| Polymer         | 10 | 10 → 150 | all |
| Electronics     | 10 | 10 → 150 | all |
| Crystal         | 10 | 10 → 100 | all |
| Cementing Paste | 10 | 10 → 50 | all |
| Ammo bundle*    | 13 | scales | all |
| Kibble (variety)|  8 | 3 → 15  | green+ |
| Black Pearls    |  6 | 5 → 20  | **purple+** |
| Element         |  8 | ~75 (red) / ~150 (ring) | **red** |

*Ammo bundle scales: Stone Arrows / Simple ammo (white–green) → Advanced Rifle Bullets
(blue–yellow) → ARB + Rockets (red). Not coupled to the dropped weapon (ARK entries roll
independently).*

---

## Group 5 — STRUCTURES (bonus, base-kit pull 0–3; item-only; stone→metal by tier)

When it fires, pulls up to 3 types so a hit = a buildable kit (foundations + walls + ceilings).
Stone at white/green, metal at blue+ (behemoth gates are metal-only → blue+).

| Structure | ⚪/🟢 (stone) | 🔵→🔴 (metal) | Qty ⚪→🔴 |
|-----------|:---:|:---:|---|
| Foundation | ✔ | ✔ | 4 → 9 |
| Wall       | ✔ | ✔ | 8 → 12 |
| Ceiling    | ✔ | ✔ | 4 → 9 |
| Doorframe + Door | ✔ | ✔ | 1 → 2 |
| Dinosaur Gateway + Gate | ✔ | ✔ | 1 → 4 |
| Behemoth Gateway + Gate | — | ✔ (blue+) | 1 → 2 |

---

## The `SupplyCrateLootQualityMultiplier` change

```ini
; Quality is authored per-item in the ConfigOverrideSupplyCrateItems tables below, so the
; global crate-quality knob stays neutral (1.0) — the table numbers are the real numbers.
SupplyCrateLootQualityMultiplier=1.0
; FishingLootQualityMultiplier is a separate system (fishing-rod loot) — left at 2.50.
```

---

## To verify at implementation (plan stage — not guessed here)

1. **Exact crate class strings per map** (`SupplyCrate_Level##_<Map>_C` + ring/Double variants),
   every map in the cluster. A wrong string = silent no-op.
2. **Item class strings** for every gear/resource/turret/structure listed.
3. **Full saddle-item roster** pulled from Beacon → each saddleable creature assigned to a band;
   bareback/no-saddle creatures dropped. Confirm tek-saddle item classes (Rex/Mosa/Megalodon/
   Rock Drake/Tapejara Tek).
4. **Quality → numeric `MinQuality`/`MaxQuality`** per item per tier, implementing rule 4
   (cheap raised, power gated) + the ascendant-rare curve. Verified in-game.
5. **Element sanity** — ~150 vs the 3× boss element already in `Game.ini` (Dragon Alpha 1320,
   King Titan Alpha 1500) = head-start, not a shortcut.
