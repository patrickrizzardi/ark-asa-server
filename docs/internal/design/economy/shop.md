# ArkShop Catalog & Points Economy

**Status**: APPROVED + VALUES LOCKED (Patrick, 2026-06-22) — moving to build. Only build-time detail left: boss-tribute *contents* (which bosses/difficulties, §8), drafted from Beacon data at build time.
**System**: the in-game shop + points economy (ArkShop, backed by MariaDB; shipped in M2).
**Related**: breeding tuning → [breeding.md](breeding.md); supply-crate loot → [loot-crates.md](loot-crates.md).
**Generator (built)**: `tools/shop-design.ts` (spec) + `tools/gen-shop.ts` (engine) → ArkShop `config.json`. Mirrors the loot tool. See §11.

> **How to use this doc**: edit any value in the tables below. Prices are in shop points. Anything
> marked _(proposed)_ or with a `?` is a guess — change freely. When you're happy, this becomes the
> spec and the generator gets built.

---

## 0. North star (the lens for every number)

Built for **working adults** — a few hours a day, most playing **2–3×/week**. They should reach
endgame **without 1,000 hours but not in 1 hour**. Easy *start*, earned *endgame*. The shop is a
**leg-up, never a shortcut**: taming and breeding stay the real path to power.

---

## 1. Verified ArkShop capabilities (the rules we design within)

From the ArkShop source (Michidu/Ark-Server-Plugins), confirmed 2026-06-22:

- **Regular shop items have NO purchase limit, NO cooldown, NO global stock.** Unlimited buys.
  ArkShop offers a `MinLevel`/`MaxLevel` player-level wall, but we leave it at 1 (boosted XP makes it
  meaningless — see §4) → **price is the only gate.**
- **Kits** have `DefaultAmount` (a per-player redemption cap) **and** a `Price`. Per-player only —
  true server-wide scarcity is not possible in config.
- **Dinos spawn FLAT**: `SpawnDino(..., level, true, neutered)` → exactly the configured level,
  **zero imprint, zero taming-effectiveness bonus**. A shop 225 ≈ a perfectly-tamed wild 150 and is
  strictly beaten by a bred + imprinted dino. _This is the no-pay-to-win spine — it's structural._
  (See [breeding.md](breeding.md) for why bred beats bought.)
- Dino entry fields available: `Level`, `Neutered`, `Gender`, `Blueprint`, `SaddleBlueprint`,
  `PreventCryo`, `Stryder*`, `GachaResources`.

---

## 2. Economy anchors

| Knob | Value | Notes |
|---|---|---|
| Income | **250 pts / 6 min** (~2,500/hr) | 10 ticks/hr — infrequent enough to not spam chat. `TimedPointsReward`. Tuned so the apex dino = 6 h (below). |
| Top combat dino (Rex, 225) | **10,000** | ~4 h of play |
| Apex dino (Giga, 225) | **15,000** | **6 h — the dino price ceiling ("max dino = 6 h of work")** |
| Boss tribute set | **120,000** | ~48 h — endgame gate (8× the apex dino); harder bosses scale above this |

**Pacing reference** (income 2,500/hr; play pattern 2 h/day × 3 days/week = 6 h/week):

| What | Price | Hours | Weeks @6h/wk |
|---|---|---|---|
| Cheap utility dino | 1,000–1,500 | ~0.5 h | first session |
| Mid combat dino (225) | 3,500 | 1.4 h | first session |
| Top combat dino — Rex (225) | 10,000 | 4 h | ~⅔ week |
| Apex dino — Giga (225) | 15,000 | **6 h** | ~1 week |
| Two Gigas | 30,000 | 12 h | ~2 weeks |
| Boss tribute set | 120,000 | 48 h | ~8 weeks |

---

## 3. Level-cap principle

> **Cap the level wherever level confers an advantage. Allow 300 only where level is cosmetic.**

| Role | Cap | Why |
|---|---|---|
| Free starter | **150** | fast start, not endgame |
| Combat | **225** | level = melee/HP = real edge |
| Gatherer | **225** | level = weight/HP/gather rate = real edge |
| Transport | **225** | level = weight/HP = real edge |
| Pure util-pet | **300** | stats don't scale meaningfully → level is just a feel-good number |

---

## 4. The two buckets

The design uses kits for **one thing only**: the free starter kit (it's free, so it must be
claim-once). **Everything else is an uncapped shop item** — gated by **price only**, buyable forever.
No resource caps for now (revisit if a resource turns out to be abused).

1. **Free starter kit** — `DefaultAmount: 1` (claim once). The only capped thing. Section 5.
2. **Uncapped shop items** — **price only** (no player-level wall — boosted XP makes it meaningless,
   players hit ~60 in an hour), unlimited buys. Dinos (§6), resources (§7), boss tribute sets (§8).

---

## 5. Kits

Free dinos/limited gear **must** be kits (shop items can't be capped). Kits are also the **sanctioned
exception** to "sell only raw resources / force crafting" — they may contain finished gear *because*
they're purchase-limited (`DefaultAmount`). ArkShop quality index: 0 prim · 1 ram · 2 app · 3 journ ·
4 master · 5 asc.

| Kit | Price | Claims | Contents (per claim) |
|---|---|---|---|
| **starter** (survival) | free | 3 | 1 Ptera + 1 Doed + 1 Anky + 1 Castoroides (all lvl 150, w/ saddles) + 1 Mastercraft flak set |
| **weapons** | free | 3 | Crossbow ×1, Spear ×2, Bola ×3, Stone Arrow ×100, Tranq Arrow ×50 (all primitive) |
| **taming** | 3,000 | 5 | Journeyman Longneck ×1, Tranq Dart ×500, Bola ×50, Narcotic ×200, 10× each kibble tier |
| **defense** | 5,000 | 5 | Heavy Turret ×5, ARB ×2,500 (500/turret), Metal Spike Wall ×10, Mastercraft Riot set |
| **taming_water** | 4,000 | 5 | SCUBA set (4pc, Q2), Harpoon Gun (Q3), Tranq Spear Bolt ×200, 10× each kibble tier |
| **cryopods** | 1,000 | 5 | 5 reusable Empty Cryopods (25 total/player) — keepable pods, unlike the dino-delivery pod |

**The two free kits use the 3-claim survival model**: claim → die → re-claim, 3× then on your own
(one death shouldn't wipe everything). Riot > Flak (~15% more armor, Beacon-verified) so the paid
defense kit upgrades the free flak. Free dinos are flat lvl-150 — a leg-up, not endgame.

---

## 6. Dino catalog (uncapped shop items; gated by price only)

Two axes: **price tier** (white→red ladder = how valuable/rare/hard-to-get → sets points) and
**role** (sets the level cap). No `MinLevel` wall — boosted XP makes a player-level gate meaningless
(everyone's ~60 within an hour), so price is the only gate.

**All store dinos — shop items AND kits — are neutered** (`NEUTER_STORE_DINOS`): usable but not
breedable. Closes the bypass where a bought flat-225 gets bred into imprinted (strong) offspring —
breeding stays gated behind dinos you tamed yourself.

**All rideable store dinos ship WITH their saddle** (`SaddleBlueprint`), at **primitive quality** —
rideable out of the box, the same convenience the kits give. Buying makes you mobile, not armored:
better-quality saddles still come from crafting/looting, so the crafting loop is preserved. Dinos
with no saddle item (light pets, Otter, Sinomacrops, Diplocaulus) ship bareback. Delivery is by
**cryopod** (`GiveDinosInCryopods: true`, base config) — the saddled dino pods up as one item;
saddle + cryo are independent. The per-dino `saddle` map lives in `tools/shop-design.ts` (labels
Beacon-verified; the generator FAILS LOUD on a typo).

> **The delivery pod is NOT keepable.** ArkShop's `GiveDinosInCryopods` pod is **one-time-use** — it
> poofs when the dino is released (documented ArkShop behavior; no setting makes it permanent).
> `CryoLimitedTime: false` only governs expiry (true = 60-min). Players who want **reusable** pods buy
> the **cryopods kit** (§5) — the vanilla `Empty Cryopod` IS reusable, unlike the delivery pod.

| Dino | Role | Tier | Price | Lvl cap |
|---|---|---|---|---|
| Featherlight | util-pet | util | 1,000 | 300 |
| Bulbdog | util-pet | util | 1,000 | 300 |
| Glowtail | util-pet | util | 1,000 | 300 |
| Shinehorn | util-pet | util | 1,000 | 300 |
| Sinomacrops | util-pet (glide) | util | 1,500 | 300 |
| Otter | util-pet (insul.) | util | 1,500 | 300 |
| Parasaur | scout | green | 1,000 | 225 |
| Raptor | combat | green | 1,500 | 225 |
| Trike | combat | green | 1,500 | 225 |
| Pteranodon | transport (fly) | green | 2,000 | 225 |
| Diplocaulus | util (underwater air, scales w/ lvl) | green | 2,000 | 225 |
| Sabertooth | combat + chitin gather | green | 2,500 | 225 |
| Ankylosaurus | gatherer (metal) | green | 2,500 | 225 |
| Doedicurus | gatherer (stone) | green | 2,500 | 225 |
| Carnotaurus | combat | blue | 3,000 | 225 |
| Megalodon | combat (water) | blue | 3,000 | 225 |
| Baryonyx | combat | blue | 3,500 | 225 |
| Direbear | combat/gather | blue | 3,500 | 225 |
| Thylacoleo | combat (climb/ambush) | blue | 3,500 | 225 |
| Dunkleosteus | gatherer (water: oil/silica/metal) | blue | 3,500 | 225 |
| Argentavis | transport | blue | 4,000 | 225 |
| Mammoth | gatherer (wood) | purple | 4,500 | 225 |
| Megatherium | gatherer/combat | purple | 5,000 | 225 |
| Daeodon | healer | purple | 5,000 | 225 |
| Spinosaurus | combat | purple | 5,500 | 225 |
| Snow Owl | transport/heal | purple | 6,000 | 225 |
| Therizinosaurus | combat/gather | purple | 6,000 | 225 |
| Yutyrannus | combat (buff) | purple | 6,500 | 225 |
| Quetzal | transport (platform) | purple | 7,500 | 225 |
| Allosaurus | combat (pack) | yellow | 8,000 | 225 |
| Basilosaurus | water utility | yellow | 8,000 | 225 |
| Rex | combat | yellow | 10,000 | 225 |
| Carcharodontosaurus | combat | yellow | 10,000 | 225 |
| Mosasaurus | water apex | red | 12,000 | 225 |
| Wyvern | combat (fly) | red | 13,000 | 225 |
| Tusoteuthis (Squid) | water apex | red | 13,000 | 225 |
| Rock Drake | combat (climb) | red | 13,000 | 225 |
| Giganotosaurus | combat apex | red | 15,000 | 225 |

_Add / cut / reprice freely. Candidates not yet included: Bronto, Paracer, Karkinos, Magmasaur,
Managarmr, Plesiosaur, Tropeognathus, Velonasaur, Gigantopithecus._

---

## 7. Resources (all uncapped shop items — buy forever, gated by price + bundle size)

Amounts deliberately modest ("don't overdo abundance"). Tiers below are *difficulty-to-farm* bands
that drive price; none are capped. Pricing principle: **bundle ≈ playtime-to-farm, or a bit more for
elite stuff** — so buying is a convenience tax, never the efficient path.

### Basic — cheap convenience
| Resource | Bundle | Price |
|---|---|---|
| Hide | 300 | 250 |
| Keratin | 250 | 300 |
| Chitin | 250 | 300 |

### Mid — refined
| Resource | Bundle | Price |
|---|---|---|
| Metal (ore) | 500 | 1,000 |
| Silica Pearls | 500 | 1,000 |
| Crystal | 500 | 800 |
| Oil | 300 | 800 |
| Obsidian | 500 | 800 |
| Cementing Paste | 300 | 800 |
| Sulfur | 300 | 700 |
| Polymer (organic) | 300 | 1,000 |
| Pelt | 200 | 300 |
| Sap | 50 | 400 |

> Every resource sold is gathered **raw** — no finished/crafted items (Electronics + Gunpowder both
> cut, to keep crafting mandatory). "Metal (ore)" = raw `Metal` (not Metal Ingot) → players must
> smelt it themselves. The generator resolves the raw-resource class strings, never crafted ones.

### Elite — hard farm (still uncapped, just pricey)
| Resource | Bundle | Price |
|---|---|---|
| Black Pearls | 100 | 2,500 |
| Element Dust | 50,000 | 3,000 |
| Red / Blue / Green Gem | 100 | 1,200 |
| Congealed Gas Ball | 50 | 800 |

> Element is sold as **Element Dust** (not element) — keeps crafting in the loop (players craft dust
> → element / shards themselves, in-inventory). 50,000 dust = 50 element worth.
> Gems + Gas Ball are Aberration-flavored — keep only if Ab is in rotation.

### Kibble — uncapped, priced by tier (sold per 10)
Cheap-ish but not trivial early (~2,500/hr income): Basic 50 · Simple 100 · Regular 200 · Superior
300 · Exceptional 400 · Extraordinary 500.

### Consumables — uncapped
| Item | Qty | Price |
|---|---|---|
| Mindwipe Tonic | 1 | 1,000 |

> No vanilla **Dino** Mindwipe Tonic exists in ASA (only mod versions) — omitted; re-add if a
> dino-respec mod is installed.

---

## 8. Boss tribute sets (uncapped shop items, price-gated)

Sell the **ingredients to summon a boss** (artifacts + trophies) — players still have to win the
fight. Price is the endgame gate. Uncapped for now; revisit if it's abused.
_Per-boss contents + prices TBD — one entry per boss/difficulty._

Base price **120,000** (~48 h of play — your "boss access should take ~48 h"). Harder
bosses/difficulties scale above this base. Per-boss contents still TBD (which bosses/difficulties).

| Set | Price | Contents |
|---|---|---|
| Boss tribute (base) | 120,000 | artifacts + trophies for one summon |

---

## 9. Breeding & imprint

Lives in its own doc — [breeding.md](breeding.md). It's the mechanism that makes a home-bred dino
strictly beat a shop dino (the no-P2W spine), so it's part of the same economy but a distinct system.

---

## 10. Open items / to confirm

- **Boss tribute contents** (§8) — which bosses/difficulties; base price 120k locked, harder ones scale up. Drafted from Beacon data at build time.
- Resource amounts/prices (§7) — LOCKED by Patrick 2026-06-22 (basics trimmed, mid bundles bumped, Electronics cut).
- Source of truth for class strings at build time: `docs/internal/reference/beacon-asa/`
  (`creatures.tsv`, `engrams.tsv`) — same as the loot generator. Resolve every dino/item/resource
  label to its exact class string (a typo = silent no-op).

---

## 11. Build & deploy (the generator)

`tools/shop-design.ts` encodes this doc (income, dino roster, resources, starter kit). `tools/gen-shop.ts`
resolves every label → `Blueprint'<path>'` against the Beacon TSVs (**FAILS LOUD** on any miss), builds
the ArkShop `config.json` (General.TimedPointsReward + ShopItems + Kits), and **omits the Mysql block**
(the entrypoint injects DB creds from `.env` at boot — no secrets in the generated file).

**Tweak loop** (same shape as loot):
```
edit tools/shop-design.ts  →  cd tools && bun run gen-shop.ts --write  →  git push
  →  on dell: git pull  →  docker compose restart the-center
```
- `--write` writes the **tracked** seed `config/arkshop.config.json` (no secrets → safe to commit).
  Without `--write` it only writes `tools/out/arkshop-config.json` (gitignored, for inspection).
- **Deploy model**: the entrypoint copies `config/arkshop.config.json` → the **per-server** ArkShop
  plugin dir (`…/Win64/ArkApi/Plugins/ArkShop/config.json` on each server's own game volume)
  **every boot** (repo = source of truth for the catalog), then injects the Mysql block onto that
  per-server runtime copy. There is **no host bind** — each server owns its copy, so N cluster
  servers never contend on a shared file. Catalog edits happen in the spec, never on a deployed
  copy (overwritten each boot by design). Permissions follows the same model from
  `config/permissions.config.json` (see
  [ADR 0004](../../decisions/0004-shared-config-model.md)).

**Levels are flat** (ArkShop spawns no taming/imprint bonus, §1), so a shop 225 is beaten by anything
bred — the no-P2W spine needs no per-stat tuning. **Not yet boot-verified on dell.**
