// Shop design — the tweakable spec, encoded from
// docs/internal/design/economy/shop.md (APPROVED 2026-06-22).
// The engine (gen-shop.ts) turns this + Beacon's class-string data into ArkShop config.json.
// Edit prices/amounts/rosters here, then re-run `bun run gen-shop.ts`.
//
// Labels MUST match Beacon's exact label (creatures.tsv for dinos, engrams.tsv for items/saddles).
// gen-shop.ts FAILS LOUD on any unresolved label — fix the name here and re-run.

// --- Income (TimedPointsReward) ---
// Interval is in MINUTES (ArkShop default 5). 250 / 6 min = 2,500/hr → apex Giga (15k) = 6h.
export const income = { intervalMinutes: 6, amountPerInterval: 250 } as const;

// --- Level caps by role ---
// Principle (shop.md §3): cap where level confers an advantage; 300 only where level is cosmetic.
export type Role =
  | 'combat' | 'gatherer' | 'transport' | 'scout' | 'healer' | 'util' // all 225
  | 'utilpet'; // 300 — pure QoL, stats don't scale meaningfully
export const capForRole = (role: Role): number => (role === 'utilpet' ? 300 : 225);

// --- Dino catalog (uncapped shop items; price = rarity/desirability, cap = role) ---
export type Dino = { id: string; label: string; price: number; role: Role };
export const dinos: Dino[] = [
  // util-pet (300)
  { id: 'featherlight', label: 'Featherlight', price: 1000, role: 'utilpet' },
  { id: 'bulbdog', label: 'Bulbdog', price: 1000, role: 'utilpet' },
  { id: 'glowtail', label: 'Glowtail', price: 1000, role: 'utilpet' },
  { id: 'shinehorn', label: 'Shinehorn', price: 1000, role: 'utilpet' },
  { id: 'sinomacrops', label: 'Sinomacrops', price: 1500, role: 'utilpet' },
  { id: 'otter', label: 'Otter', price: 1500, role: 'utilpet' },
  // green (225)
  { id: 'parasaur', label: 'Parasaurolophus', price: 1000, role: 'scout' },
  { id: 'raptor', label: 'Raptor', price: 1500, role: 'combat' },
  { id: 'trike', label: 'Triceratops', price: 1500, role: 'combat' },
  { id: 'ptera', label: 'Pteranodon', price: 2000, role: 'transport' },
  { id: 'diplo', label: 'Diplocaulus', price: 2000, role: 'util' }, // underwater air; scales w/ lvl → 225
  { id: 'saber', label: 'Sabertooth', price: 2500, role: 'combat' },
  { id: 'anky', label: 'Ankylosaurus', price: 2500, role: 'gatherer' },
  { id: 'doed', label: 'Doedicurus', price: 2500, role: 'gatherer' },
  // blue (225)
  { id: 'carno', label: 'Carnotaurus', price: 3000, role: 'combat' },
  { id: 'megalodon', label: 'Megalodon', price: 3000, role: 'combat' },
  { id: 'bary', label: 'Baryonyx', price: 3500, role: 'combat' },
  { id: 'direbear', label: 'Direbear', price: 3500, role: 'combat' },
  { id: 'dunkle', label: 'Dunkleosteus', price: 3500, role: 'gatherer' },
  { id: 'argy', label: 'Argentavis', price: 4000, role: 'transport' },
  // purple (225)
  { id: 'mammoth', label: 'Mammoth', price: 4500, role: 'gatherer' },
  { id: 'megatherium', label: 'Megatherium', price: 5000, role: 'gatherer' },
  { id: 'daeodon', label: 'Daeodon', price: 5000, role: 'healer' },
  { id: 'spino', label: 'Spinosaurus', price: 5500, role: 'combat' },
  { id: 'snowowl', label: 'Snow Owl', price: 6000, role: 'transport' },
  { id: 'theri', label: 'Therizinosaurus', price: 6000, role: 'combat' },
  { id: 'yuty', label: 'Yutyrannus', price: 6500, role: 'combat' },
  { id: 'rhynio', label: 'Rhyniognatha', price: 6500, role: 'combat' },
  { id: 'quetz', label: 'Quetzalcoatlus', price: 7500, role: 'transport' },
  // yellow (225)
  { id: 'allo', label: 'Allosaurus', price: 8000, role: 'combat' },
  { id: 'basilo', label: 'Basilosaurus', price: 8000, role: 'util' },
  { id: 'rex', label: 'Rex', price: 10000, role: 'combat' },
  { id: 'carcharo', label: 'Carcharodontosaurus', price: 10000, role: 'combat' },
  // red (225)
  { id: 'mosa', label: 'Mosasaurus', price: 12000, role: 'combat' },
  { id: 'wyvern', label: 'Fire Wyvern', price: 13000, role: 'combat' }, // ASA wyverns are elemental; Fire is the sellable canonical
  { id: 'tuso', label: 'Tusoteuthis', price: 13000, role: 'combat' },
  { id: 'rockdrake', label: 'Rock Drake', price: 13000, role: 'combat' },
  { id: 'giga', label: 'Giganotosaurus', price: 15000, role: 'combat' }, // apex = the 15k ceiling (6h)
];

// --- Resources (uncapped shop items; all RAW gathers — no crafted items, to force crafting) ---
export type ShopResource = { id: string; label: string; amount: number; price: number };
export const resources: ShopResource[] = [
  // Basic
  { id: 'hide', label: 'Hide', amount: 300, price: 250 },
  { id: 'keratin', label: 'Keratin', amount: 250, price: 300 },
  { id: 'chitin', label: 'Chitin', amount: 250, price: 300 },
  // Mid
  { id: 'metal', label: 'Metal', amount: 500, price: 1000 }, // RAW ore (not ingot) — players must smelt
  { id: 'pearls', label: 'Silica Pearls', amount: 500, price: 1000 },
  { id: 'crystal', label: 'Crystal', amount: 500, price: 800 },
  { id: 'oil', label: 'Oil', amount: 300, price: 800 },
  { id: 'obsidian', label: 'Obsidian', amount: 500, price: 800 },
  { id: 'paste', label: 'Cementing Paste', amount: 300, price: 800 },
  { id: 'sulfur', label: 'Sulfur', amount: 300, price: 700 },
  { id: 'polymer', label: 'Organic Polymer', amount: 300, price: 1000 }, // farmed, not crafted
  { id: 'pelt', label: 'Pelt', amount: 200, price: 300 },
  { id: 'sap', label: 'Sap', amount: 50, price: 400 },
  // Elite
  { id: 'blackpearls', label: 'Black Pearl', amount: 100, price: 2500 },
  { id: 'elementdust', label: 'Element Dust', amount: 50000, price: 3000 }, // 1000 dust = 1 element
  { id: 'redgem', label: 'Red Gem', amount: 100, price: 1200 }, // Aberration gems
  { id: 'bluegem', label: 'Blue Gem', amount: 100, price: 1200 },
  { id: 'greengem', label: 'Green Gem', amount: 100, price: 1200 },
  { id: 'gasball', label: 'Congealed Gas Ball', amount: 50, price: 800 },
];

// --- Kibble (uncapped shop items; priced by tier — higher kibble costs more) ---
// Sold per 10 (a taming-sized chunk). Cheap-ish but not trivial early (income ~2,500/hr).
export const kibble: ShopResource[] = [
  { id: 'kibble_basic', label: 'Basic Kibble', amount: 10, price: 50 },
  { id: 'kibble_simple', label: 'Simple Kibble', amount: 10, price: 100 },
  { id: 'kibble_regular', label: 'Regular Kibble', amount: 10, price: 200 },
  { id: 'kibble_superior', label: 'Superior Kibble', amount: 10, price: 300 },
  { id: 'kibble_exceptional', label: 'Exceptional Kibble', amount: 10, price: 400 },
  { id: 'kibble_extraordinary', label: 'Extraordinary Kibble', amount: 10, price: 500 },
];

// --- Consumables (uncapped shop items) ---
export const consumables: ShopResource[] = [
  { id: 'mindwipe', label: 'Mindwipe Tonic', amount: 1, price: 1000 },
  // NOTE: no vanilla "Dino Mindwipe Tonic" exists in ASA (only mod versions, e.g. "CS Dino Mindwipe",
  // which we don't run) — omitted. Re-add if a dino-respec mod is installed.
];

// --- Kits ---
// Free dinos/limited gear MUST be kits (shop items can't be capped). Kits are also the SANCTIONED
// EXCEPTION to "sell only raw resources / force crafting" — they may contain finished gear BECAUSE
// they're purchase-limited (DefaultAmount). ArkShop quality index: 0 prim,1 ram,2 app,3 journ,4 master,5 asc.
export const STARTER_LEVEL = 150;
export const MASTERCRAFT_QUALITY = 4;
// ALL store-bought dinos (shop items AND kits) are neutered — you can use them but NOT breed them.
// Closes the bypass where a bought flat-225 could be bred into imprinted (strong) offspring; breeding
// stays gated behind dinos you tamed yourself. Gender doesn't matter, neutering does.
export const NEUTER_STORE_DINOS = true;
// "Metal armor" in ARK = Flak (metal-tier set); Riot = higher-armor set (paid defense upgrade).
export const flakSet = ['Flak Helmet', 'Flak Chestpiece', 'Flak Leggings', 'Flak Gauntlets', 'Flak Boots'];
export const riotSet = ['Riot Helmet', 'Riot Chestpiece', 'Riot Leggings', 'Riot Gauntlets', 'Riot Boots'];

export type KitItem = { label: string; quality: number; amount: number };
export type KitDinoSpec = { label: string; saddle: string | null; level: number; count: number };
export type Kit = {
  id: string; defaultAmount: number; price: number; onlyFromSpawn: boolean;
  description: string; dinos: KitDinoSpec[]; items: KitItem[];
};
// expand an armor set (5 pieces) into per-piece kit items
const armor = (set: string[], quality: number, amount: number): KitItem[] =>
  set.map((label) => ({ label, quality, amount }));
// all 6 kibble tiers at `amount` each (for the taming kits)
const allKibble = (amount: number): KitItem[] => kibble.map((k) => ({ label: k.label, quality: 0, amount }));

export const kits: Kit[] = [
  // FREE survival kit — 3 claims (re-claim after a death), one loadout each; dinos lvl 150 w/ saddles.
  {
    id: 'starter', defaultAmount: 3, price: 0, onlyFromSpawn: false,
    description: 'Free survival kit',
    dinos: [
      { label: 'Pteranodon', saddle: 'Pteranodon Saddle', level: STARTER_LEVEL, count: 1 },
      { label: 'Doedicurus', saddle: 'Doedicurus Saddle', level: STARTER_LEVEL, count: 1 },
      { label: 'Ankylosaurus', saddle: 'Ankylosaurus Saddle', level: STARTER_LEVEL, count: 1 },
      { label: 'Castoroides', saddle: 'Castoroides Saddle', level: STARTER_LEVEL, count: 1 },
    ],
    items: armor(flakSet, MASTERCRAFT_QUALITY, 1),
  },
  // FREE weapons kit — 3 claims, all primitive basics.
  {
    id: 'weapons', defaultAmount: 3, price: 0, onlyFromSpawn: false,
    description: 'Free weapons kit — basic primitive gear',
    dinos: [],
    items: [
      { label: 'Crossbow', quality: 0, amount: 1 },
      { label: 'Spear', quality: 0, amount: 2 },
      { label: 'Bola', quality: 0, amount: 10 },
      { label: 'Stone Arrow', quality: 0, amount: 100 },
      { label: 'Tranquilizer Arrow', quality: 0, amount: 50 },
    ],
  },
  // PAID taming kit — buy up to 5; mid-tier longneck (journeyman), 500 darts, narcotics, a kibble stack.
  {
    id: 'taming', defaultAmount: 5, price: 3000, onlyFromSpawn: false,
    description: 'Taming kit (buy up to 5) — journeyman',
    dinos: [],
    items: [
      { label: 'Longneck Rifle', quality: 3, amount: 1 },
      { label: 'Tranquilizer Dart', quality: 0, amount: 500 },
      { label: 'Bola', quality: 0, amount: 50 }, // cheap to craft anyway
      { label: 'Narcotic', quality: 0, amount: 200 },
      ...allKibble(10), // 10 of each of the 6 kibble tiers
    ],
  },
  // PAID defense kit — buy up to 5; heavy turrets (NOT tek), 500 ARB/turret, metal spikes, a Riot set.
  {
    id: 'defense', defaultAmount: 5, price: 5000, onlyFromSpawn: false,
    description: 'Defense kit (buy up to 5) — 5 heavy turrets + ammo, metal spikes, a riot set.',
    dinos: [],
    items: [
      { label: 'Heavy Turret', quality: 0, amount: 5 },
      { label: 'Advanced Rifle Bullet', quality: 0, amount: 2500 }, // 500 per turret × 5
      { label: 'Metal Spike Wall', quality: 0, amount: 10 },
      ...armor(riotSet, MASTERCRAFT_QUALITY, 1),
    ],
  },
  // PAID underwater taming kit — buy up to 5; SCUBA set + harpoon + tranq spear bolts. Pricier than land taming.
  {
    id: 'taming_water', defaultAmount: 5, price: 4000, onlyFromSpawn: false,
    description: 'Underwater taming kit (buy up to 5) — SCUBA gear, harpoon + tranq spear bolts.',
    dinos: [],
    items: [
      { label: 'SCUBA Tank', quality: 2, amount: 1 },
      { label: 'SCUBA Mask', quality: 2, amount: 1 },
      { label: 'SCUBA Flippers', quality: 2, amount: 1 },
      { label: 'SCUBA Leggings', quality: 2, amount: 1 },
      { label: 'Harpoon Gun', quality: 3, amount: 1 },
      { label: 'Tranq Spear Bolt', quality: 0, amount: 200 },
      ...allKibble(10), // 10 of each of the 6 kibble tiers
    ],
  },
];

// --- Boss tribute sets (uncapped shop items; base 120k; CONTENTS TBD per boss) ---
// Placeholder until Patrick picks bosses/difficulties (shop.md §8). Drafted from Beacon at build.
export const BOSS_BASE_PRICE = 120000;
export type BossSet = { id: string; description: string; price: number; items: { label: string; amount: number }[] };
export const bossKits: BossSet[] = [
  // e.g. { id: 'broodmother_g', description: 'Broodmother (Gamma) tribute', price: 120000, items: [...] }
];
