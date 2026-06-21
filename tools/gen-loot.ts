// gen-loot.ts — generate ConfigOverrideSupplyCrateItems for config/Game.ini from the
// approved loot design (loot-design.ts) + Beacon's class-string data (../docs/internal/
// reference/beacon-asa/*.tsv). Run: `bun run gen-loot.ts`.
//
// Pipeline: resolve item names -> class strings (FAIL LOUD on misses) ->
// map each crate container -> {tier, ring} by its label -> emit one
// ConfigOverrideSupplyCrateItems line per crate. Writes the block + a review report.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as D from './loot-design.ts';

const here = dirname(fileURLToPath(import.meta.url));
const refDir = join(here, '..', 'docs', 'internal', 'reference', 'beacon-asa');
const outDir = join(here, 'out');

type Row = Record<string, string>;
const parseTsv = (path: string): Row[] => {
  const lines = readFileSync(path, 'utf8').split('\n').filter((l) => l.length > 0);
  const header = (lines[0] ?? '').split('\t');
  return lines.slice(1).map((line) => {
    const cells = line.split('\t');
    const row: Row = {};
    header.forEach((h, i) => { row[h] = cells[i] ?? ''; });
    return row;
  });
};

// --- item label -> class string (exact label; first occurrence wins) ---
const engrams = parseTsv(join(refDir, 'engrams.tsv'));
const itemByLabel = new Map<string, string>();
for (const e of engrams) {
  if (!itemByLabel.has(e.label)) itemByLabel.set(e.label, e.class_string);
}
const misses = new Set<string>();
const resolve = (label: string): string => {
  const cls = itemByLabel.get(label);
  if (cls === undefined) { misses.add(label); return `UNRESOLVED:${label}`; }
  return cls;
};
const resolveMany = (labels: string[]): string[] => labels.map(resolve);

// --- crate -> tier mapping ---
const RELEASED_MASK = 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128; // LostColony (256) excluded
const colorWords: { needle: string; tier: D.Tier }[] = [
  { needle: 'white', tier: 'white' }, { needle: 'green', tier: 'green' },
  { needle: 'blue', tier: 'blue' }, { needle: 'purple', tier: 'purple' },
  { needle: 'yellow', tier: 'yellow' }, { needle: 'red', tier: 'red' },
  { needle: 'lime', tier: 'red' },
];
const osdWords: { needle: string; tier: D.Tier }[] = [
  { needle: 'easy', tier: 'blue' }, { needle: 'medium', tier: 'purple' },
  { needle: 'hard', tier: 'yellow' }, { needle: 'legendary', tier: 'red' },
];
// not loot — event/resource-node "crates"
const excludeNeedles = ['candy corn', 'raptor claws', 'gift', 'beaver', ' den', 'volcan', 'dragon hoard', 'admin', 'hat', 'doggo'];

type Mapped = { tier: D.Tier; ring: boolean };
const mapCrate = (label: string, cls: string): Mapped | null => {
  const l = label.toLowerCase();
  const ring = l.includes('bonus') || cls.includes('_Double_');
  if (l.includes('orbital')) {
    for (const o of osdWords) if (l.includes(o.needle)) return { tier: o.tier, ring };
  }
  for (const c of colorWords) if (l.includes(c.needle)) return { tier: c.tier, ring };
  if (l.includes('deep sea') || l.includes('ocean') || l.includes('treasure')) return { tier: 'red', ring };
  return null;
};

// --- ARK config emit helpers ---
const num = (n: number): string => (Number.isInteger(n) ? String(n) : n.toFixed(2));
type Entry = { name: string; classes: string[]; weight: number; qMin: number; qMax: number; qlMin: number; qlMax: number; bp: number };
const entryStr = (e: Entry): string => {
  const cls = e.classes.map((c) => `"${c}"`).join(',');
  return `(ItemEntryName="${e.name}",EntryWeight=${num(e.weight)},ItemClassStrings=(${cls}),ItemsWeights=(),`
    + `MinQuantity=${num(e.qMin)},MaxQuantity=${num(e.qMax)},MinQuality=${num(e.qlMin)},MaxQuality=${num(e.qlMax)},`
    + `bForceBlueprint=false,ChanceToBeBlueprintOverride=${num(e.bp)})`;
};
type Set = { name: string; min: number; max: number; entries: Entry[] };
const setStr = (s: Set): string =>
  `(SetName="${s.name}",MinNumItems=${num(s.min)},MaxNumItems=${num(s.max)},NumItemsPower=1.0,SetWeight=1.0,`
  + `bItemsRandomWithoutReplacement=true,ItemEntries=(${s.entries.map(entryStr).join(',')}))`;
const crateStr = (cls: string, sets: Set[]): string =>
  `ConfigOverrideSupplyCrateItems=(SupplyCrateClassString="${cls}",MinItemSets=${sets.length},MaxItemSets=${sets.length},`
  + `bSetsRandomWithoutReplacement=false,bAppendItemSets=false,ItemSets=(${sets.map(setStr).join(',')}))`;

// --- build the 5 group sets for a (tier, ring) ---
const buildSets = (tier: D.Tier, ring: boolean): Set[] => {
  const qMult = ring ? D.ringQualityMult : 1;
  const ql = (power: D.GearPower): { min: number; max: number } => {
    const q = D.qualityFor(tier, power);
    return { min: q.min * qMult, max: q.max * qMult };
  };
  const sets: Set[] = [];

  // GROUP 1 — Gear (always)
  const gearEntries: Entry[] = [];
  for (const g of D.gear) {
    const wt = g.weights[tier];
    if (wt <= 0) continue;
    const classes = g.armorSet ? resolveMany(D.armorSets[g.armorSet] ?? []) : [resolve(g.label)];
    const q = ql(g.power);
    gearEntries.push({ name: g.label, classes, weight: wt, qMin: 1, qMax: 1, qlMin: q.min, qlMax: q.max, bp: D.gearBlueprintChance });
  }
  const gp = ring ? D.gearPullRing[tier] : D.gearPull[tier];
  sets.push({ name: 'Gear', min: gp.min, max: gp.max, entries: gearEntries });

  // GROUP 2 — Saddles (blue+; bonus)
  if (D.tierIndex(tier) >= D.tierIndex('blue')) {
    const sadEntries: Entry[] = [];
    for (const band of D.saddleBands) {
      if (band.tekOnly && tier !== 'red') continue;
      const classes = band.members.map((m) => resolve(band.tekOnly ? m : `${m} Saddle`));
      const q = ql('power'); // saddles track the tier band
      sadEntries.push({ name: band.tekOnly ? 'TekSaddle' : `Saddle_w${band.weight}`, classes, weight: band.weight, qMin: 1, qMax: 1, qlMin: q.min, qlMax: q.max, bp: D.gearBlueprintChance });
    }
    sets.push({ name: 'Saddles', min: D.saddlePull.min, max: D.saddlePull.max + (ring ? 1 : 0), entries: sadEntries });
  }

  // GROUP 3 — Turrets (blue+; bonus; item-only)
  if (D.tierIndex(tier) >= D.tierIndex('blue')) {
    const turEntries: Entry[] = [];
    for (const t of D.turrets) {
      const wt = t.weights[tier];
      if (wt <= 0) continue;
      turEntries.push({ name: t.label, classes: [resolve(t.label)], weight: wt, qMin: D.turretQty.min, qMax: D.turretQty.max, qlMin: 0, qlMax: 0, bp: 0 });
    }
    if (turEntries.length > 0) sets.push({ name: 'Turrets', min: D.turretPull.min, max: D.turretPull.max + (ring ? 1 : 0), entries: turEntries });
  }

  // GROUP 4 — Resources (always; guaranteed >=2; item-only)
  const resEntries: Entry[] = [];
  for (const r of D.resources) {
    const wt = r.weights[tier];
    if (wt <= 0) continue;
    const qty = D.scaleQty(r.maxQty, tier, D.resourceScale);
    resEntries.push({ name: r.label, classes: [resolve(r.label)], weight: wt, qMin: Math.max(1, Math.round(qty * 0.6)), qMax: qty, qlMin: 0, qlMax: 0, bp: 0 });
  }
  const ammo = D.ammoByTier[tier];
  const aQty = D.scaleQty(ammo.maxQty, tier, D.resourceScale);
  resEntries.push({ name: 'Ammo', classes: [resolve(ammo.label)], weight: ammo.weight, qMin: Math.max(1, Math.round(aQty * 0.6)), qMax: aQty, qlMin: 0, qlMax: 0, bp: 0 });
  sets.push({ name: 'Resources', min: D.resourcePull.min + (ring ? 1 : 0), max: D.resourcePull.max + (ring ? 1 : 0), entries: resEntries });

  // GROUP 5 — Structures (always; base-kit; item-only; stone white/green -> metal blue+)
  const stEntries: Entry[] = [];
  const stone = D.isStoneTier(tier);
  for (const s of D.structures) {
    if (s.metalOnly && stone) continue;
    const label = stone ? s.stone : s.metal;
    const qty = D.scaleQty(s.maxQty, tier, D.resourceScale);
    stEntries.push({ name: s.name, classes: [resolve(label)], weight: 10, qMin: Math.max(1, Math.round(qty * 0.6)), qMax: qty, qlMin: 0, qlMax: 0, bp: 0 });
  }
  sets.push({ name: 'Structures', min: D.structurePull.min, max: D.structurePull.max + (ring ? 1 : 0), entries: stEntries });

  return sets;
};

// --- main ---
const crates = parseTsv(join(refDir, 'loot_containers.tsv'));
const emitted: string[] = [];
const report: string[] = [];
const excluded: string[] = [];
const unmapped: string[] = [];
let nonCrate = 0;

for (const c of crates) {
  const cls = c.class_string;
  const label = c.label;
  if (!cls.includes('SupplyCrate')) { nonCrate++; continue; } // creature inventories / fishing — out of scope
  const availInt = Number(c.availability);
  if ((availInt & RELEASED_MASK) === 0) continue; // not on a released map (e.g. LostColony only)
  const l = label.toLowerCase();
  if (excludeNeedles.some((n) => l.includes(n))) { excluded.push(`${label}  [${cls}]`); continue; }
  const m = mapCrate(label, cls);
  if (m === null) { unmapped.push(`${label}  [${cls}]`); continue; }
  emitted.push(crateStr(cls, buildSets(m.tier, m.ring)));
  report.push(`${m.tier.padEnd(6)} ${m.ring ? 'RING' : '    '}  ${label}`);
}

// --- write outputs ---
import { mkdirSync } from 'node:fs';
mkdirSync(outDir, { recursive: true });
const header = '; === Supply crate loot — GENERATED by tools/gen-loot.ts. Do not hand-edit. ===\n'
  + '; Tweak tools/loot-design.ts and re-run. Source class strings: Beacon ASA DB.\n'
  + 'SupplyCrateLootQualityMultiplier=1.0\n';
writeFileSync(join(outDir, 'game-ini-loot.txt'), header + emitted.join('\n') + '\n');
writeFileSync(join(outDir, 'crate-map-report.txt'),
  `EMITTED ${emitted.length} crates:\n${report.sort().join('\n')}\n\n`
  + `EXCLUDED (event/resource junk) ${excluded.length}:\n${excluded.sort().join('\n')}\n\n`
  + `UNMAPPED (no tier from label — need a rule) ${unmapped.length}:\n${unmapped.sort().join('\n')}\n`);

console.log(`emitted: ${emitted.length} crates -> out/game-ini-loot.txt`);
console.log(`excluded(junk): ${excluded.length}, unmapped: ${unmapped.length}, skipped non-crate: ${nonCrate} (see out/crate-map-report.txt)`);
if (misses.size > 0) {
  console.error(`\n!! ${misses.size} UNRESOLVED item labels (fix names in loot-design.ts):`);
  for (const m of [...misses].sort()) console.error(`   - ${m}`);
  process.exit(1);
}
console.log('all item labels resolved OK.');

// --- optional: write the block into config/Game.ini between markers (idempotent) ---
const MARK_START = '; >>> GENERATED SUPPLY-CRATE LOOT (tools/gen-loot.ts) — do not edit between markers >>>';
const MARK_END = '; <<< END GENERATED SUPPLY-CRATE LOOT <<<';
if (process.argv.includes('--write')) {
  const iniPath = join(here, '..', 'config', 'Game.ini');
  let ini = readFileSync(iniPath, 'utf8');
  // flip the existing multiplier in place (do not duplicate); fishing multiplier untouched
  ini = ini.replace(/^SupplyCrateLootQualityMultiplier=.*$/m, 'SupplyCrateLootQualityMultiplier=1.0');
  // Idempotency keys on the config LINES, not the marker comments — ARK rewrites
  // GameUserSettings.ini (stripping comments); Game.ini appears read-only, but if that
  // ever changes our markers could vanish. We own every supply-crate override (full
  // custom design), so stripping all `ConfigOverrideSupplyCrateItems=` lines + the old
  // markers and re-appending the fresh block is idempotent regardless of comment fate.
  const kept = ini.split('\n').filter((l) =>
    !l.startsWith('ConfigOverrideSupplyCrateItems=') && l !== MARK_START && l !== MARK_END);
  const body = kept.join('\n').replace(/\n{3,}/g, '\n\n').replace(/\s*$/, '');
  ini = `${body}\n\n${MARK_START}\n${emitted.join('\n')}\n${MARK_END}\n`;
  writeFileSync(iniPath, ini);
  console.log(`patched config/Game.ini (stripped old overrides, re-added ${emitted.length}; SupplyCrateLootQualityMultiplier=1.0).`);
} else {
  console.log('(run with --write to patch config/Game.ini in place)');
}
