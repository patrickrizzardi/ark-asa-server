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
import { beacon } from './beacon.ts';
import * as D from './shop-design.ts';

const here = dirname(fileURLToPath(import.meta.url));
const refDir = beacon.refDir(here);
const outDir = join(here, 'out');

// --- label -> Blueprint'<path>' (ArkShop wants the full UE reference form; first occurrence wins) ---
const misses = new Set<string>();
const wrapBp = (path: string): string => `Blueprint'${path}'`;
const dinoIndex = beacon.buildIndex(beacon.parseTsv(join(refDir, 'creatures.tsv')), (r) => r.path);
const itemIndex = beacon.buildIndex(beacon.parseTsv(join(refDir, 'engrams.tsv')), (r) => r.path);
const resolveDino = beacon.makeResolver(dinoIndex, misses, wrapBp);
const resolveItem = beacon.makeResolver(itemIndex, misses, wrapBp);
const dinoBp = (label: string): string => resolveDino(label, 'dino');
const itemBp = (label: string): string => resolveItem(label, 'item');

// --- ArkShop config object shapes ---
type ItemEntry = { Quality: number; ForceBlueprint: boolean; Amount: number; Blueprint: string };
type ShopItem =
  | { Type: 'item'; Description: string; Price: number; Items: ItemEntry[] }
  | { Type: 'dino'; Description: string; Level: number; Price: number; Neutered: boolean; Blueprint: string };
type KitDino = { Level: number; Blueprint: string; SaddleBlueprint?: string; Neutered?: boolean };
type Kit = { DefaultAmount: number; Price: number; Description: string; OnlyFromSpawn: boolean; Items: ItemEntry[]; Dinos: KitDino[] };

// --- build ShopItems: dinos (price-only gate; MinLevel/MaxLevel omitted = default 1/999) ---
const shopItems: Record<string, ShopItem> = {};
for (const d of D.dinos) {
  shopItems[d.id] = {
    Type: 'dino',
    Description: `${d.label} (lvl ${D.capForRole(d.role)})`,
    Level: D.capForRole(d.role),
    Price: d.price,
    Neutered: D.NEUTER_STORE_DINOS,
    Blueprint: dinoBp(d.label),
  };
}
// --- resources + kibble + consumables as item entries (all uncapped shop items) ---
for (const r of [...D.resources, ...D.kibble, ...D.consumables]) {
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

// --- build Kits (general): free survival + free weapons + paid taming + paid defense ---
const kits: Record<string, Kit> = {};
for (const k of D.kits) {
  const dinos: KitDino[] = [];
  for (const d of k.dinos) {
    for (let i = 0; i < d.count; i++) {
      const entry: KitDino = { Level: d.level, Blueprint: dinoBp(d.label), Neutered: D.NEUTER_STORE_DINOS };
      if (d.saddle) entry.SaddleBlueprint = itemBp(d.saddle);
      dinos.push(entry);
    }
  }
  const items: ItemEntry[] = k.items.map((it) => ({
    Quality: it.quality, ForceBlueprint: false, Amount: it.amount, Blueprint: itemBp(it.label),
  }));
  kits[k.id] = {
    DefaultAmount: k.defaultAmount,
    Price: k.price,
    Description: k.description,
    OnlyFromSpawn: k.onlyFromSpawn,
    Items: items,
    Dinos: dinos,
  };
}

// --- assemble config: OVERLAY onto the real ArkShop default (arkshop-config.base.json) ---
// The base carries every key ArkShop reads — incl. Messages + SellItems (omitting them caused a
// `json.exception.type_error.306 cannot use value() with null` load failure). We replace ONLY the
// three blocks we own: General.TimedPointsReward (income), ShopItems, Kits. Mysql stays the base's
// placeholder (UseMysql:false, empty creds) — the entrypoint injects real creds at boot.
// The base file is ours (captured from ArkShop's default); `as` is justified — we know its shape and
// only touch these three blocks. Indexer keeps Messages/SellItems/Mysql intact + untyped passthrough.
type ArkShopConfig = {
  General: { TimedPointsReward: Record<string, unknown> };
  ShopItems: Record<string, ShopItem>;
  Kits: Record<string, Kit>;
  [key: string]: unknown;
};
const config = JSON.parse(readFileSync(join(here, 'arkshop-config.base.json'), 'utf8')) as ArkShopConfig;
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
writeFileSync(join(outDir, 'arkshop-config.json'), JSON.stringify(config, null, 2) + '\n');

const report = [
  `ShopItems: ${Object.keys(shopItems).length} (${D.dinos.length} dinos, ${D.resources.length} resources, ${D.kibble.length} kibble, ${D.consumables.length} consumables, ${D.bossKits.length} boss sets)`,
  `Kits: ${Object.keys(kits).length} — ${D.kits.map((k) => `${k.id}(x${k.defaultAmount}, ${k.price}pt)`).join(', ')}`,
  `Income: ${D.income.amountPerInterval} pts / ${D.income.intervalMinutes} min (~${Math.round(D.income.amountPerInterval * (60 / D.income.intervalMinutes))}/hr)`,
  '',
  'Dinos:',
  ...D.dinos.map((d) => `  ${String(d.price).padStart(6)}  L${D.capForRole(d.role)}  ${d.label} (${d.role})`),
  '',
  'Resources + Kibble + Consumables:',
  ...[...D.resources, ...D.kibble, ...D.consumables].map((r) => `  ${String(r.price).padStart(6)}  ${r.amount}x ${r.label}`),
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
