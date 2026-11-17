# backgrounds.txt

A past life chosen at character creation. It brings starting coin and favours a
kind of check. Read by `ReadBackground` in `content.pas`. See [README](README.md)
for the shared line syntax.

## Record

```
bg  ID  "Name"  "Helps"  GOLD
```

Keyword `bg`, the id, two quoted fields, and a dice expression. A line with fewer
than five fields is skipped.

| Field | Meaning |
| --- | --- |
| `ID` | Unique id (`SOLDIER`). |
| `"Name"` | Display name, quoted. |
| `"Helps"` | The skill or situation it favours, quoted. The benefit is a +2 to related checks. |
| `GOLD` | A dice expression for the starting coin it brings. |

## GOLD dice expressions

Evaluated by the `dice` unit against the seeded RNG. The grammar is sums and
products of dice terms and numbers:

- `NdM` rolls N dice of M sides (`2d6`, `3d6`).
- `+` and `-` add and subtract; `*` multiplies and binds tighter than `+`/`-`.
- A bare number is a constant.

Examples: `5*2d6`, `2d6+5`, `10*3d6`, `5*2d6+10`, `4d6+8`, or a plain `12`. A
malformed expression evaluates to `0`.

## Example

```
bg SMITH    "Apprentice Smith"  "metalwork"     5*2d6
bg SOLDIER  "Disgraced Soldier" "military lore" 10*2d6
bg ACOLYTE  "Temple Acolyte"    "religious lore" 5*2d6+10
```
