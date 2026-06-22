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

// --- Free starter kit (claim once; all dinos lvl 150; the ONLY capped thing) ---
export const STARTER_LEVEL = 150;
export const MASTERCRAFT_QUALITY = 4; // ArkShop quality index: 0 prim,1 ram,2 app,3 journ,4 master,5 asc
// "Metal armor" in ARK = Flak (the metal-tier armor set). 3 full sets = qty 3 per piece.
export const flakSet = ['Flak Helmet', 'Flak Chestpiece', 'Flak Leggings', 'Flak Gauntlets', 'Flak Boots'];
export const starterKit = {
  id: 'starter',
  defaultAmount: 3, // 3 claims = 3 SURVIVAL CHANCES: re-claim after each death, then you're on your own.
  price: 0,
  onlyFromSpawn: false,
  description: 'Free survival kit — one loadout per claim, 3 claims total (re-claim after a death).',
  armorQty: 1, // one flak set per claim (not all 3 at once → a single death doesn't wipe everything)
  // dino label → primitive saddle label (so they're rideable); ONE of each per claim.
  dinos: [
    { label: 'Pteranodon', saddle: 'Pteranodon Saddle', count: 1 },
    { label: 'Doedicurus', saddle: 'Doedicurus Saddle', count: 1 },
    { label: 'Ankylosaurus', saddle: 'Ankylosaurus Saddle', count: 1 },
    { label: 'Castoroides', saddle: 'Castoroides Saddle', count: 1 },
  ],
} as const;

// --- Boss tribute sets (uncapped shop items; base 120k; CONTENTS TBD per boss) ---
// Placeholder until Patrick picks bosses/difficulties (shop.md §8). Drafted from Beacon at build.
export const BOSS_BASE_PRICE = 120000;
export type BossSet = { id: string; description: string; price: number; items: { label: string; amount: number }[] };
export const bossKits: BossSet[] = [
  // e.g. { id: 'broodmother_g', description: 'Broodmother (Gamma) tribute', price: 120000, items: [...] }
];
