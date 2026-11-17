# newgame.txt

New-game data: the random name pool, the quick-start pregenerated party, and the
character-creation default selections. Read by `LoadNewgame` in `content.pas`,
which dispatches on the first field, so three record kinds share the file. See
[README](README.md) for the shared line syntax.

## Records

```
name    NAME                one entry in the random name pool
pregen  SPECIES  CLASS      one quick-start party slot, in order
default SPECIES  CLASS  BG   the character-creation starting selections
```

| Keyword | Fields | Meaning |
| --- | --- | --- |
| `name` | `NAME` | A name added to the pool a random character draws from. |
| `pregen` | `SPECIES CLASS` | One quick-start archetype; order is the party order. |
| `default` | `SPECIES CLASS [BG]` | The selections the creation screen opens on. |

`SPECIES` is an id from [species.txt](species.md), `CLASS` an id from
[classes.txt](classes.md), and `BG` (on `default`, optional) an id from
[backgrounds.txt](backgrounds.md). A `pregen` needs at least two fields and a
`default` at least two (the background may be omitted). Unknown ids fall back to
the first entry of the matching table.

## Example

```
name THORNE
name MAEVE
pregen HUMAN FIGHTER
pregen ELF   WIZARD
default HUMAN FIGHTER SOLDIER
```
