# encounters.txt

Weighted monster tables, and the mapping from an area to a table. Read by
`LoadEncounters` in `content.pas`, which dispatches on the first field. See
[README](README.md) for the shared line syntax.

## Records

```
area   NAME  N     assign area NAME to table number N
table  N           begin filling table number N
mon    ID    W     add monster ID with weight W to the current table
```

| Keyword | Fields | Meaning |
| --- | --- | --- |
| `area` | `NAME N` | Point an area at a table number. |
| `table` | `N` | Start a numbered table; later `mon` rows fill it. |
| `mon` | `ID W` | Add a monster to the current table with weight `W`. |

`NAME` is one of the areas `forest coast desert frozen volcanic crypt cave
infernal`. `ID` is a monster id from [monsters.txt](monsters.md); an unknown id, or
a weight of zero or less, is skipped. A `mon` row only takes effect after a `table`
row has set the current table.

Table `0` is conventionally left empty, so safe areas (the town and interiors,
which resolve to area `0`) spawn nothing. A monster is drawn from a table with
probability proportional to its weight.

## Example

```
area crypt 3
area cave  1

table 1
mon RAT    6
mon SPIDER 3

table 3
mon SKELETON 5
mon GHOUL    2
```
