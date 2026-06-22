// Loot design — the tweakable spec, encoded from
// docs/internal/design/supply-crate-loot-design.md (APPROVED 2026-06-21).
// The engine (gen-loot.ts) turns this + Beacon's class-string data into Game.ini.
// Edit weights/quantities/quality here, then re-run `bun run gen-loot.ts`.

export const tiers = ['white', 'green', 'blue', 'purple', 'yellow', 'red'] as const;
export type Tier = (typeof tiers)[number];

const tierIndex = (t: Tier): number => tiers.indexOf(t);

// --- Quality bands per tier (MinQuality/MaxQuality; ARK item-rating floats) ---
// Tunable; confirmed at boot-test. Power gear uses the band as-is (menu-growth gates
// it); cheap gear may roll higher (see qualityFor()).
export const tierQuality: Record<Tier, { min: number; max: number }> = {
  white: { min: 0, max: 1.5 },
  green: { min: 1, max: 2.5 },
  blue: { min: 2, max: 4 },
  purple: { min: 4, max: 7 },
  yellow: { min: 6, max: 11 },
  red: { min: 9, max: 15 },
};

// Cheap items (stone tools, basic weapons, hide) may roll above the tier band — a great
// cheap item is still cheap. Power items track the band (their gating is menu presence).
export const qualityFor = (tier: Tier, power: GearPower): { min: number; max: number } => {
  const band = tierQuality[tier];
  if (power === 'cheap') return { min: band.min, max: Math.min(15, band.max * 1.6) };
  return band;
};

// --- Per-tier pull counts (MinNumItems/MaxNumItems per group); ring adds +1 ---
export type Pull = { min: number; max: number };
export const gearPull: Record<Tier, Pull> = {
  white: { min: 1, max: 2 }, green: { min: 1, max: 2 }, blue: { min: 1, max: 2 },
  purple: { min: 1, max: 2 }, yellow: { min: 1, max: 2 }, red: { min: 1, max: 1 },
};
// Ring gear pulls are non-uniform per Patrick's edit (white +2 … red +1).
export const gearPullRing: Record<Tier, Pull> = {
  white: { min: 3, max: 4 }, green: { min: 3, max: 4 }, blue: { min: 3, max: 4 },
  purple: { min: 3, max: 4 }, yellow: { min: 3, max: 3 }, red: { min: 2, max: 2 },
};
export const saddlePull: Pull = { min: 0, max: 1 };   // bonus; ring +1
export const turretPull: Pull = { min: 0, max: 1 };   // bonus; ring +1
export const resourcePull: Pull = { min: 2, max: 3 }; // guaranteed >=2; ring +1
export const structurePull: Pull = { min: 0, max: 3 };// base-kit; ring +1

export const ringQualityMult = 1.2;
export const gearBlueprintChance = 0.33; // BP appears ~half as often as the item (1:2)

// --- GROUP 1: GEAR (weights per tier; 0 = not in that tier's menu) ---
export type GearPower = 'cheap' | 'power';
export type GearKind = 'tool' | 'weapon' | 'armor';
export type GearItem = {
  label: string;        // Beacon engram label (resolved to class string), or armorSet key
  kind: GearKind;
  power: GearPower;
  weights: Record<Tier, number>;
  armorSet: string | null; // non-null => resolve a set of piece labels instead of `label`
};
const w = (white: number, green: number, blue: number, purple: number, yellow: number, red: number): Record<Tier, number> =>
  ({ white, green, blue, purple, yellow, red });

export const gear: GearItem[] = [
  { label: 'Stone Pick', kind: 'tool', power: 'cheap', weights: w(22, 14, 6, 0, 0, 0), armorSet: null },
  { label: 'Stone Hatchet', kind: 'tool', power: 'cheap', weights: w(22, 14, 6, 0, 0, 0), armorSet: null },
  { label: 'Metal Pick', kind: 'tool', power: 'power', weights: w(0, 0, 12, 9, 7, 6), armorSet: null },
  { label: 'Metal Hatchet', kind: 'tool', power: 'power', weights: w(0, 0, 12, 9, 7, 6), armorSet: null },
  { label: 'Metal Sickle', kind: 'tool', power: 'power', weights: w(0, 0, 8, 6, 5, 4), armorSet: null },
  { label: 'Spear', kind: 'weapon', power: 'cheap', weights: w(16, 10, 6, 4, 3, 2), armorSet: null },
  { label: 'Bow', kind: 'weapon', power: 'cheap', weights: w(14, 10, 6, 4, 3, 2), armorSet: null },
  { label: 'Simple Pistol', kind: 'weapon', power: 'cheap', weights: w(16, 10, 7, 5, 4, 3), armorSet: null },
  { label: 'Slingshot', kind: 'weapon', power: 'cheap', weights: w(10, 4, 2, 1, 1, 1), armorSet: null },
  { label: 'Pike', kind: 'weapon', power: 'cheap', weights: w(0, 8, 6, 5, 4, 3), armorSet: null },
  { label: 'Crossbow', kind: 'weapon', power: 'power', weights: w(0, 10, 8, 6, 5, 4), armorSet: null },
  { label: 'Longneck Rifle', kind: 'weapon', power: 'power', weights: w(0, 0, 10, 8, 6, 5), armorSet: null },
  { label: 'Metal Sword', kind: 'weapon', power: 'power', weights: w(0, 0, 6, 5, 4, 3), armorSet: null },
  { label: 'Assault Rifle', kind: 'weapon', power: 'power', weights: w(0, 0, 0, 8, 7, 6), armorSet: null },
  { label: 'Pump-Action Shotgun', kind: 'weapon', power: 'power', weights: w(0, 0, 0, 7, 6, 5), armorSet: null },
  { label: 'Fabricated Pistol', kind: 'weapon', power: 'power', weights: w(0, 0, 0, 6, 5, 4), armorSet: null },
  { label: 'Fabricated Sniper Rifle', kind: 'weapon', power: 'power', weights: w(0, 0, 0, 0, 7, 6), armorSet: null },
  { label: 'Compound Bow', kind: 'weapon', power: 'power', weights: w(0, 0, 0, 0, 5, 4), armorSet: null },
  { label: 'Rocket Launcher', kind: 'weapon', power: 'power', weights: w(0, 0, 0, 0, 0, 4), armorSet: null },
  { label: 'Hide Armor', kind: 'armor', power: 'cheap', weights: w(0, 10, 6, 4, 3, 2), armorSet: 'hide' },
  { label: 'Flak Armor', kind: 'armor', power: 'power', weights: w(0, 0, 8, 6, 5, 4), armorSet: 'flak' },
  { label: 'Riot Armor', kind: 'armor', power: 'power', weights: w(0, 0, 0, 0, 6, 4), armorSet: 'riot' },
];

// Armor sets -> piece labels (loot entry picks one piece at random).
export const armorSets: Record<string, string[]> = {
  hide: ['Hide Hat', 'Hide Shirt', 'Hide Pants', 'Hide Gloves', 'Hide Boots'],
  flak: ['Flak Helmet', 'Flak Chestpiece', 'Flak Leggings', 'Flak Gauntlets', 'Flak Boots'],
  riot: ['Riot Helmet', 'Riot Chestpiece', 'Riot Leggings', 'Riot Gauntlets', 'Riot Boots'],
};

// --- GROUP 2: SADDLES (power bands; same set every tier blue+, quality = tier band) ---
// Regular bands: members are creature names; engine resolves "<name> Saddle".
// Tek band: members are EXACT Beacon labels (Tek naming is inconsistent), resolved directly.
// Bareback creatures (no saddle item) removed — confirmed via Beacon resolution loud-fail.
export type SaddleBand = { weight: number; tekOnly: boolean; members: string[] };
export const saddleBands: SaddleBand[] = [
  { weight: 10, tekOnly: false, members: ['Parasaur', 'Raptor', 'Trike', 'Carno', 'Stego', 'Sarco', 'Pteranodon', 'Pachy', 'Phiomia', 'Morellatops', 'Iguanodon', 'Gallimimus', 'Pulmonoscorpius', 'Pelagornis', 'Ichthyosaurus', 'Megaloceros', 'Procoptodon', 'Equus', 'Manta', 'Terror Bird'] },
  { weight: 5, tekOnly: false, members: ['Ankylosaurus', 'Doedicurus', 'Sabertooth', 'Argentavis', 'Baryonyx', 'Carbonemys', 'Dunkleosteus', 'Velonasaur', 'Thorny Dragon', 'Kaprosuchus', 'Direbear', 'Mammoth', 'Woolly Rhino', 'Castoroides', 'Chalicotherium', 'Daeodon', 'Megatherium', 'Beelzebufo', 'Arthropluera', 'Araneo', 'Deinonychus', 'Pachyrhinosaurus', 'Snow Owl', 'Tapejara', 'Tropeognathus', 'Ravager', 'Thylacoleo', 'Mantis', 'Lymantria', 'Desmodus', 'Andrewsarchus', 'Maewing', 'Megalania', 'Megalosaurus'] },
  { weight: 3, tekOnly: false, members: ['Rex', 'Spino', 'Therizinosaurus', 'Megalodon', 'Mosasaur', 'Plesiosaur', 'Tusoteuthis', 'Basilosaurus', 'Allosaurus', 'Yutyrannus', 'Carcharo', 'Amargasaurus', 'Basilisk', 'Magmasaur', 'Quetz', 'Bronto', 'Paracer', 'Diplodocus'] },
  { weight: 1, tekOnly: false, members: ['Giganotosaurus', 'Rock Drake'] },
  { weight: 1, tekOnly: true, members: ['Tek Rex Saddle', 'Tek Megalodon Saddle', 'Tek Tapejara Saddle', 'Mosasaur Tek Saddle', 'Rock Drake Tek Saddle'] },
];

// --- GROUP 3: TURRETS (item-only; weight per tier; qty 1-2) ---
export const turrets: { label: string; weights: Record<Tier, number> }[] = [
  { label: 'Auto Turret', weights: w(0, 0, 70, 40, 30, 25) },
  { label: 'Heavy Turret', weights: w(0, 0, 0, 60, 70, 75) },
];
export const turretQty: Pull = { min: 1, max: 2 };

// --- GROUP 4: RESOURCES (item-only; guaranteed >=2; qty scales by tier) ---
// maxQty is the red quantity; engine scales down by tier via resourceScale.
export const resourceScale: Record<Tier, number> = {
  white: 0.1, green: 0.2, blue: 0.35, purple: 0.5, yellow: 0.75, red: 1.0,
};
// qtyLo = amount at the item's first available tier; qtyHi = amount at red. Interpolated
// per item (see interpQty) — each item has its own curve. Lowered 2026-06-22 (Patrick:
// too much per drop).
export const resources: { label: string; weights: Record<Tier, number>; qtyLo: number; qtyHi: number }[] = [
  { label: 'Metal Ingot', weights: w(15, 15, 15, 15, 15, 15), qtyLo: 10, qtyHi: 100 },
  { label: 'Silica Pearls', weights: w(12, 12, 12, 12, 12, 12), qtyLo: 10, qtyHi: 50 },
  { label: 'Oil', weights: w(10, 10, 10, 10, 10, 10), qtyLo: 10, qtyHi: 50 },
  { label: 'Polymer', weights: w(10, 10, 10, 10, 10, 10), qtyLo: 10, qtyHi: 150 },
  { label: 'Electronics', weights: w(10, 10, 10, 10, 10, 10), qtyLo: 10, qtyHi: 150 },
  { label: 'Crystal', weights: w(10, 10, 10, 10, 10, 10), qtyLo: 10, qtyHi: 100 },
  { label: 'Cementing Paste', weights: w(10, 10, 10, 10, 10, 10), qtyLo: 10, qtyHi: 50 },
  { label: 'Black Pearl', weights: w(0, 0, 0, 6, 6, 6), qtyLo: 5, qtyHi: 20 },   // purple+
  { label: 'Element', weights: w(0, 0, 0, 0, 0, 8), qtyLo: 75, qtyHi: 75 },      // red only
];
// Ammo bundle: label varies by tier (arrows -> ARB -> rockets).
export const ammoByTier: Record<Tier, { label: string; maxQty: number; weight: number }> = {
  white: { label: 'Stone Arrow', maxQty: 40, weight: 13 },
  green: { label: 'Stone Arrow', maxQty: 60, weight: 13 },
  blue: { label: 'Advanced Rifle Bullet', maxQty: 80, weight: 13 },
  purple: { label: 'Advanced Rifle Bullet', maxQty: 120, weight: 13 },
  yellow: { label: 'Advanced Rifle Bullet', maxQty: 160, weight: 13 },
  red: { label: 'Rocket Propelled Grenade', maxQty: 10, weight: 13 },
};

// --- GROUP 5: STRUCTURES (item-only; stone white/green -> metal blue+; qty scales) ---
// qtyLo = first-tier amount, qtyHi = red amount (interpolated). Lowered 2026-06-22
// (Patrick: don't want 50 foundations after a couple drops).
export const structures: { name: string; stone: string; metal: string; qtyLo: number; qtyHi: number; metalOnly: boolean }[] = [
  { name: 'Foundation', stone: 'Stone Foundation', metal: 'Metal Foundation', qtyLo: 4, qtyHi: 9, metalOnly: false },
  { name: 'Wall', stone: 'Stone Wall, Doorways & Windowframe', metal: 'Metal Wall, Doorways & Windowframe', qtyLo: 8, qtyHi: 12, metalOnly: false },
  { name: 'Ceiling', stone: 'Stone Ceiling & Hatchframe', metal: 'Metal Ceiling & Hatchframe', qtyLo: 4, qtyHi: 9, metalOnly: false },
  { name: 'Dino Gate', stone: 'Stone Gateway', metal: 'Metal Gateway', qtyLo: 1, qtyHi: 4, metalOnly: false },
  { name: 'Behemoth Gate', stone: 'Stone Behemoth Gateway', metal: 'Metal Behemoth Gateway', qtyLo: 1, qtyHi: 2, metalOnly: true },
];

export const isStoneTier = (t: Tier): boolean => t === 'white' || t === 'green';
// Per-tier amount interpolated from qtyLo (at firstTier) to qtyHi (at red).
export const interpQty = (qtyLo: number, qtyHi: number, tier: Tier, firstTier: Tier): number => {
  const span = tierIndex('red') - tierIndex(firstTier);
  if (span <= 0) return qtyHi;
  const frac = (tierIndex(tier) - tierIndex(firstTier)) / span;
  return Math.max(1, Math.round(qtyLo + (qtyHi - qtyLo) * frac));
};
export const firstActiveTier = (weights: Record<Tier, number>): Tier => tiers.find((t) => weights[t] > 0) ?? 'red';
// scaleQty still used for the ammo bundle (ammoByTier carries per-tier amounts).
export const scaleQty = (maxQty: number, tier: Tier, table: Record<Tier, number>): number =>
  Math.max(1, Math.round(maxQty * table[tier]));
export { tierIndex };
