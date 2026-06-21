# Beacon ASA Content Reference

Local snapshot of [Beacon](https://usebeacon.app)'s ARK: Survival Ascended content
database — so ARK-config work (loot, spawns, stats, breeding, engrams, colors) is a
**local lookup**, not web research or guessing. Beacon compiles this from the actual
game files (proper UE5 IoStore extraction), so the class strings are authoritative.

- **Source:** `ArkSA.sqlite` from a Beacon desktop install
  (`%AppData%\The ZAZ\Beacon\Libraries\ArkSA.sqlite`).
- **Snapshot date:** 2026-06-21
- **Format:** TSV (tab-separated), one file per table, blob/icon columns dropped, long
  values truncated at 4000 chars, embedded newlines shown as ` ⏎ `.

## Re-pulling (when ASA adds content)

```python
import sqlite3, os
# copy ArkSA.sqlite + -wal + -shm together first (to apply the WAL), then:
db = sqlite3.connect('ArkSA.sqlite')
# export each table to TSV (see git history of this dir for the exporter)
```

## Map bitmask (the `availability` column in loot/spawn/engram tables)

| bit | map | bit | map |
|----:|-----|----:|-----|
| 1 | The Island | 16 | Extinction |
| 2 | Scorched Earth | 32 | Astraeos |
| 4 | The Center | 64 | Ragnarok |
| 8 | Aberration | 128 | Valguero |
| 256 | Lost Colony (not yet public as of snapshot) | | |

A row's `availability` is the OR of the maps it appears on (e.g. `5` = Island + Center).

## Tables

| File | Rows | What it holds |
|------|-----:|---------------|
| `creatures.tsv` | 845 | Dino class strings, labels, stats, taming, per-map availability |
| `engrams.tsv` | 3897 | **Item class strings** by label + tags + stack size (the item lookup) |
| `loot_containers.tsv` | 393 | **Supply-crate class strings** + availability + min/max item sets |
| `maps.tsv` | 9 | Map labels, `world_name`, difficulty, the bitmask `mask` |
| `ini_options.tsv` | 361 | Every Game.ini / GameUserSettings option + description + type |
| `game_variables.tsv` | 33 | Misc game constants |
| `spawn_points.tsv` | 331 | Dino spawn container class strings + per-map availability |
| `spawn_point_populations.tsv` | 492 | Spawn population entries |
| `colors.tsv` / `color_sets.tsv` | 227 / 177 | Color IDs + named color sets (for `cheat SetTargetDinoColor` etc.) |
| `content_packs.tsv` | 88 | DLC / mod content-pack ids |
| `tags_*.tsv` | — | Tag → object lookups for creatures / engrams / loot containers |

> Derived from Beacon's community-compiled data; for personal server-config use.
> Not canonical game source — but it's what the gold-standard tool uses, and we verify
> against the live server at boot.
