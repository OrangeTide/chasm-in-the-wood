# monsters.txt

The bestiary. Read by `ReadMonster` in `content.pas`. See [README](README.md) for
the shared line syntax.

## Record

```
mon  ID  HD  AC  ATK  DMG  MORALE  SPEED  XP  FLAGS  MODEL  AREAS  [tags]  "Name"
```

Keyword `mon`, then eleven required fields, optional tags, and the quoted name. A
line with fewer than twelve fields is skipped.

| Field | Meaning |
| --- | --- |
| `ID` | Unique id (`RAT`, `DEMON`). |
| `HD` | Hit dice; health is rolled from it and scaled by depth. |
| `AC` | Armour class the player's attack is checked against. |
| `ATK` | To-hit bonus. |
| `DMG` | Damage die. |
| `MORALE` | The 1d6 hold threshold. |
| `SPEED` | Turn order; higher acts sooner. |
| `XP` | Experience granted on a kill. |
| `FLAGS` | Bitfield, see below. |
| `MODEL` | Combat sprite id; omit (use `-`) to fall back to a drawn glyph. |
| `AREAS` | A `+` list of the areas the monster roams. |
| `"Name"` | Display name, quoted. |

## FLAGS

- `1` undead
- `2` ranged
- `4` lycanthrope
- `8` mage
- `16` healer

## AREAS

A `+`-joined list, such as `crypt+cave`. The areas are:

`forest coast desert frozen volcanic crypt cave infernal`

The set drives both the encounter table the monster is drawn from (see
[encounters.md](encounters.md)) and the per-area sprite cache.

## Tags

Optional `key:value` tags after `AREAS`, before the name. The loader reads `size:`;
the rest tune combat and are consumed elsewhere or ignored.

- `size:<class>` the drawn bulk: `tiny small medium large huge colossal` (default
  `medium`).
- Combat tags documented in the file header: `elem: weak: resist: immune: inflict:
  statusimm: harry:`. Elements are `phys fire frost shock holy`.

## Example

```
mon RAT   1  6 0 3 3 2  2 - cave          "Giant Rat"
mon DEMON 8 16 6 8 5 10 40 2 crypt+infernal size:large "Pit Demon"
```
