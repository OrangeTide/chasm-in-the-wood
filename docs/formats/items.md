# items.txt

Every item the game knows: weapons, armour, consumables, loot, and the objective
relic. Read by `ReadItem` in `content.pas`. See [README](README.md) for the shared
line syntax.

## Record

```
item  ID  KIND  DMG  AC  SLOTS  VALUE  FLAGS  [tags]  "Name"
```

Keyword `item`, then seven required fields, optional tags, and the quoted display
name last. A line with fewer than eight fields is skipped.

| Field | Meaning |
| --- | --- |
| `ID` | Unique id, referenced by other tables (`DAGGER`, `POTION`). |
| `KIND` | What the item is, one of the kinds below. |
| `DMG` | Weapon damage die (a `6` is 1d6). `0` for non-weapons. |
| `AC` | Armour class a worn piece sets (armour) or adds (shield). |
| `SLOTS` | Pack bulk, in slots. |
| `VALUE` | Price in coin. Loot weighting and sale value both use it. |
| `FLAGS` | Bitfield, see below. |
| `"Name"` | Display name, quoted. |

## KIND

`weapon armor shield potion light key treasure misc relic scroll`

- `weapon`, `armor`, `shield` can be worn and set the combat stats.
- `potion` is drunk (see the `eff:`/`pow:` tags), `scroll` is read.
- `light` is a torch or lantern, burned underground.
- `key` opens a locked chest.
- `treasure` is sale-only reward.
- `relic` is the objective; it never spawns as loot and is never sold.
- `misc` is anything else (rations, tools, trophies).

## FLAGS

A sum of bits:

- `1` two-handed (bars a shield)
- `2` ranged
- `4` silvered or blessed (strikes as holy)
- `8` revive (raises a gravely wounded ally)

## Tags

Optional `key:value` tags sit after `FLAGS` and before the name. Unknown tags are
ignored.

- `eff:<effect>` the use effect of a consumable: `heal` or `light`.
- `pow:<n>` the effect's magnitude. For `heal`, hit points restored, with `0`
  meaning a full restore. For `light`, seconds added to the carried torch.

## Example

```
item SWORD    weapon   6  0 1  10 0 "Short Sword"
item GREATAXE weapon  10  0 2  15 1 "Great Axe"
item MARMOR   armor    0 14 2  75 0 "Chain Mail"
item POTION   potion   0  0 1  25 0 eff:heal pow:10 "Healing Potion"
item SCRLIGHT scroll   0  0 1  15 0 eff:light pow:150 "Scroll of Daylight"
item KEY      key      0  0 1   5 0 "Iron Key"
```
