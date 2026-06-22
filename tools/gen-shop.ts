// gen-shop.ts — generate ArkShop config.json (ShopItems + Kits + TimedPointsReward) from the
// approved shop design (shop-design.ts) + Beacon's class-string data (../docs/internal/
// reference/beacon-asa/*.tsv). Run: `bun run gen-shop.ts`.
//
// Pipeline: resolve dino/item labels -> Blueprint'<path>' (FAIL LOUD on misses) -> build the
// ShopItems map (dinos + resources), the Kits map (free starter), and General.TimedPointsReward
// -> merge into the ArkShop config skeleton -> write tools/out/arkshop-config.json + a report.
//
// Does NOT emit the Mysql block — the entrypoint injects it from .env at boot (jq). Generating it
// here would risk committing/overwriting DB creds.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as D from './shop-design.ts';

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

// --- label -> blueprint path (exact label; first occurrence wins, so base variant beats Aberrant) ---
const buildIndex = (rows: Row[]): Map<string, string> => {
  const m = new Map<string, string>();
  for (const r of rows) if (r.label && r.path && !m.has(r.label)) m.set(r.label, r.path);
  return m;
};
const dinoPath = buildIndex(parseTsv(join(refDir, 'creatures.tsv')));
const itemPath = buildIndex(parseTsv(join(refDir, 'engrams.tsv')));

const misses = new Set<string>();
// ArkShop wants the full UE reference form: Blueprint'/Game/....X.X'
const bp = (index: Map<string, string>, label: string, kind: string): string => {
  const path = index.get(label);
  if (path === undefined) { misses.add(`${kind}: ${label}`); return `UNRESOLVED:${label}`; }
  return `Blueprint'${path}'`;
};
const dinoBp = (label: string): string => bp(dinoPath, label, 'dino');
const itemBp = (label: string): string => bp(itemPath, label, 'item');

// --- ArkShop config object shapes ---
type ItemEntry = { Quality: number; ForceBlueprint: boolean; Amount: number; Blueprint: string };
type ShopItem =
  | { Type: 'item'; Description: string; Price: number; Items: ItemEntry[] }
  | { Type: 'dino'; Description: string; Level: number; Price: number; Neutered: boolean; Blueprint: string };
type KitDino = { Level: number; Blueprint: string; SaddleBlueprint?: string };
type Kit = { DefaultAmount: number; Price: number; Description: string; OnlyFromSpawn: boolean; Items: ItemEntry[]; Dinos: KitDino[] };

// --- build ShopItems: dinos (price-only gate; MinLevel/MaxLevel omitted = default 1/999) ---
const shopItems: Record<string, ShopItem> = {};
for (const d of D.dinos) {
  shopItems[d.id] = {
    Type: 'dino',
    Description: `${d.label} (lvl ${D.capForRole(d.role)})`,
    Level: D.capForRole(d.role),
    Price: d.price,
    Neutered: false,
    Blueprint: dinoBp(d.label),
  };
}
// --- resources as item entries ---
for (const r of D.resources) {
  shopItems[r.id] = {
    Type: 'item',
    Description: `${r.label} (${r.amount}x)`,
    Price: r.price,
    Items: [{ Quality: 0, ForceBlueprint: false, Amount: r.amount, Blueprint: itemBp(r.label) }],
  };
}
// --- boss tribute sets (contents TBD; only emitted once Patrick fills shop-design.bossKits) ---
for (const b of D.bossKits) {
  shopItems[b.id] = {
    Type: 'item',
    Description: b.description,
    Price: b.price,
    Items: b.items.map((it) => ({ Quality: 0, ForceBlueprint: false, Amount: it.amount, Blueprint: itemBp(it.label) })),
  };
}

// --- build Kits: the one free starter kit (claim once) ---
const starterDinos: KitDino[] = [];
for (const e of D.starterKit.dinos) {
  for (let i = 0; i < e.count; i++) {
    starterDinos.push({ Level: D.STARTER_LEVEL, Blueprint: dinoBp(e.label), SaddleBlueprint: itemBp(e.saddle) });
  }
}
const starterItems: ItemEntry[] = D.flakSet.map((piece) => ({
  Quality: D.MASTERCRAFT_QUALITY, ForceBlueprint: false, Amount: D.starterKit.armorQty, Blueprint: itemBp(piece),
}));
const kits: Record<string, Kit> = {
  [D.starterKit.id]: {
    DefaultAmount: D.starterKit.defaultAmount,
    Price: D.starterKit.price,
    Description: D.starterKit.description,
    OnlyFromSpawn: D.starterKit.onlyFromSpawn,
    Items: starterItems,
    Dinos: starterDinos,
  },
};

// --- assemble config: OVERLAY onto the real ArkShop default (arkshop-config.base.json) ---
// The base carries every key ArkShop reads — incl. Messages + SellItems (omitting them caused a
// `json.exception.type_error.306 cannot use value() with null` load failure). We replace ONLY the
// three blocks we own: General.TimedPointsReward (income), ShopItems, Kits. Mysql stays the base's
// placeholder (UseMysql:false, empty creds) — the entrypoint injects real creds at boot.
const config = JSON.parse(readFileSync(join(here, 'arkshop-config.base.json'), 'utf8'));
config.General.TimedPointsReward = {
  ...config.General.TimedPointsReward,
  Enabled: true,
  Interval: D.income.intervalMinutes,
  Groups: { Default: { Amount: D.income.amountPerInterval } },
};
config.ShopItems = shopItems;
config.Kits = kits;

// --- write outputs ---
mkdirSync(outDir, { recursive: true });
const dinoCount = D.dinos.length;
const resCount = D.resources.length;
const bossCount = D.bossKits.length;
writeFileSync(join(outDir, 'arkshop-config.json'), JSON.stringify(config, null, 2) + '\n');

const report = [
  `ShopItems: ${Object.keys(shopItems).length} (${dinoCount} dinos, ${resCount} resources, ${bossCount} boss sets)`,
  `Kits: ${Object.keys(kits).length} (starter: ${starterDinos.length} dinos + ${starterItems.length} armor pieces)`,
  `Income: ${D.income.amountPerInterval} pts / ${D.income.intervalMinutes} min (~${Math.round(D.income.amountPerInterval * (60 / D.income.intervalMinutes))}/hr)`,
  '',
  'Dinos:',
  ...D.dinos.map((d) => `  ${String(d.price).padStart(6)}  L${D.capForRole(d.role)}  ${d.label} (${d.role})`),
  '',
  'Resources:',
  ...D.resources.map((r) => `  ${String(r.price).padStart(6)}  ${r.amount}x ${r.label}`),
].join('\n');
writeFileSync(join(outDir, 'shop-report.txt'), report + '\n');

console.log(`emitted: ${Object.keys(shopItems).length} shop items + ${Object.keys(kits).length} kit(s) -> out/arkshop-config.json`);
if (misses.size > 0) {
  console.error(`\n!! ${misses.size} UNRESOLVED labels (fix names in shop-design.ts):`);
  for (const m of [...misses].sort()) console.error(`   - ${m}`);
  process.exit(1);
}
console.log('all labels resolved OK.');
console.log('(Mysql block intentionally omitted — entrypoint injects it from .env at boot.)');

// --- optional: write the tracked seed config/arkshop.config.json (entrypoint deploys it each boot) ---
// Only reached when all labels resolved (the exit(1) above guards a broken seed). The seed carries
// NO secrets (Mysql injected at boot), so it is safe to commit.
if (process.argv.includes('--write')) {
  const seedPath = join(here, '..', 'config', 'arkshop.config.json');
  writeFileSync(seedPath, JSON.stringify(config, null, 2) + '\n');
  console.log('wrote tracked seed -> config/arkshop.config.json (entrypoint deploys it each boot).');
} else {
  console.log('(run with --write to update the tracked seed config/arkshop.config.json)');
}
