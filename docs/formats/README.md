# File formats

This directory documents the runtime-loadable files the game reads from
`content/`. The game loads its data and its user-visible text from plain files so
the wording, the tables, and the balance can change without touching the sources.
Each format below has its own page.

## Shared syntax

All the text tables share one line-based grammar, parsed by the tokenizer in
`src/game/content.pas` (and mirrored by the loaders in `src/game/uitext.pas` and
elsewhere).

- One record per line. Leading and trailing whitespace is ignored.
- A blank line, or a line whose first non-space character is `#`, is a comment and
  is skipped.
- Fields are separated by runs of spaces or tabs. The count of spaces does not
  matter, so columns may be aligned for reading.
- The first field is a keyword that names the record kind (`item`, `mon`, `str`,
  and so on). A line whose keyword does not match the file's expected keyword is
  ignored, so one file can hold more than one kind of record.
- A run wrapped in double quotes is one field with the quotes stripped, so a
  display name may contain spaces: `"Short Sword"`. An empty `""` is a valid empty
  field.
- Parsing is tolerant. Unknown trailing `key:value` tags are ignored, so a table
  can gain new tags without breaking an older loader. A malformed numeric field
  reads as `0`.

Values that are ids (an item id, a species id, a monster id) are the cross
references between tables. They are matched exactly and are conventionally
uppercase. A reference to an id that no table defines is skipped at load.

## The formats

| File | Page | Loaded by |
| --- | --- | --- |
| `content/items.txt` | [items.md](items.md) | `content.pas` |
| `content/monsters.txt` | [monsters.md](monsters.md) | `content.pas` |
| `content/species.txt` | [species.md](species.md) | `content.pas` |
| `content/classes.txt` | [classes.md](classes.md) | `content.pas` |
| `content/backgrounds.txt` | [backgrounds.md](backgrounds.md) | `content.pas` |
| `content/newgame.txt` | [newgame.md](newgame.md) | `content.pas` |
| `content/encounters.txt` | [encounters.md](encounters.md) | `content.pas` |
| `content/shops.txt` | [shops.md](shops.md) | `content.pas` |
| `content/quests.txt` | [quests.md](quests.md) | `content.pas` |
| `content/dialogs.txt` | [dialogs.md](dialogs.md) | `dialogtext.pas` |
| `content/strings.txt` | [strings.md](strings.md) | `uitext.pas` |
| `chasm.sav` | [save.md](save.md) | `saveload.pas` |

## Not covered here

Some files under `content/` belong to an earlier or aspirational design and are
not read by the current build: `world.txt`, `gear.txt`, `skills.txt`, and
`spells.txt`. They are kept as design notes, not live formats. The modular tileset
kit (`content/tilesets.txt`) and the voxel and map
assets under `content/tiles`, `content/maps`, `content/models`, and the media
folders have their own formats and are documented with the render pipeline, not
here.

When a new loadable format is added, document it here as its own page and add a row
to the table above.
