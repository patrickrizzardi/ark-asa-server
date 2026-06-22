// beacon.ts — shared helpers for the config generators (gen-loot.ts, gen-shop.ts): load Beacon's
// committed TSV snapshots, build label→value indexes, and resolve labels FAIL-LOUD. The two engines
// differ only in which column they index (loot → class_string, shop → blueprint path) and how they
// format the hit (loot → bare class string, shop → Blueprint'…'), so those stay as thin per-engine
// adapters over `makeResolver`.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export type Row = Record<string, string>;

export const beacon = {
  // path to the committed Beacon ASA snapshot dir, relative to a generator's own dir
  refDir: (here: string): string => join(here, '..', 'docs', 'internal', 'reference', 'beacon-asa'),

  // Parse a tab-separated snapshot into row objects keyed by header.
  // Time: O(n) where n = lines  Space: O(n)
  parseTsv: (path: string): Row[] => {
    const lines = readFileSync(path, 'utf8').split('\n').filter((l) => l.length > 0);
    const header = (lines[0] ?? '').split('\t');
    return lines.slice(1).map((line) => {
      const cells = line.split('\t');
      const row: Row = {};
      header.forEach((h, i) => { row[h] = cells[i] ?? ''; });
      return row;
    });
  },

  // Build a label → pick(row) index, first-occurrence-wins (so a base variant beats an
  // Aberrant/Tek/Corrupt one, which sort later by label).
  // Time: O(n) where n = rows  Space: O(n)
  buildIndex: (rows: Row[], pick: (r: Row) => string): Map<string, string> => {
    const m = new Map<string, string>();
    for (const r of rows) { if (r.label && !m.has(r.label)) m.set(r.label, pick(r)); }
    return m;
  },

  // A resolver bound to a shared `misses` Set. `format` wraps a hit (identity for loot's bare class
  // string, Blueprint'…' for ArkShop). On a miss it records `kind: label` and returns an
  // UNRESOLVED:<label> sentinel so the caller's exit(1) gate fails loud instead of emitting garbage.
  makeResolver: (
    index: Map<string, string>,
    misses: Set<string>,
    format: (value: string) => string = (v) => v,
  ) => (label: string, kind = 'item'): string => {
    const v = index.get(label);
    if (v === undefined) { misses.add(`${kind}: ${label}`); return `UNRESOLVED:${label}`; }
    return format(v);
  },
} as const;
