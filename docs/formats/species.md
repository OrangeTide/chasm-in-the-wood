# species.txt

The playable species and their ability modifiers. Read by `ReadSpecies` in
`content.pas`. See [README](README.md) for the shared line syntax.

## Record

```
species  ID  "Name"  STR  DEX  CON  INT  WIS  CHA  FLAGS  XP%
```

Keyword `species`, the id, the quoted name, six ability modifiers, a flag bitfield,
and an experience percent. A line with fewer than ten fields is skipped.

| Field | Meaning |
| --- | --- |
| `ID` | Unique id (`HUMAN`, `DWARF`). |
| `"Name"` | Display name, quoted. |
| `STR DEX CON INT WIS CHA` | Ability score modifiers, applied at creation. May be negative. |
| `FLAGS` | Bitfield, see below. |
| `XP%` | A bonus percent to experience earned. |

## FLAGS

- `1` darkvision
- `2` prime +1 (a human-style floating bonus)

## Example

```
species HUMAN  "Human"  0  0  0  0  0  0 2 10
species DWARF  "Dwarf"  0  0  1  0  0 -1 1  0
species ELF    "Elf"    0  1 -1  0  0  0 1  0
```
