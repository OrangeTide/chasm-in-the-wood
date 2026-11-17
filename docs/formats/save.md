# chasm.sav

The single save slot, written beside the executable. Unlike the content tables this
is a binary stream, not a text file. Written and read by `saveload.pas`.

## Layout

The stream is a header, the world location, the player record, and the two change
registries, in order. Integers are 32-bit little-endian (`LongInt`); `Seed` is a
64-bit `QWord`.

| Field | Type | Meaning |
| --- | --- | --- |
| magic | 8 bytes | `CHASMSV5`; the trailing digit is the format version. |
| version | LongInt | `5`; must match exactly or the load is refused. |
| seed | QWord | The world seed. |
| in town | LongInt | `1` in the town, `0` in the dungeon. |
| depth | LongInt | The current dungeon depth. |
| deepest reached | LongInt | The deepest depth reached, which gates shop stock. |
| player | record | The player, see below. |
| slain | registry | Monsters killed, see below. |
| taken | registry | Loot and chests removed, see below. |

### Player record

In order: tile `Cx Cy`; `Hp MaxHp`; derived `Ac Atk DmgDie DmgBonus`; `Alive`
(0/1); `Gold`; `NCarry` followed by that many pack item indices; the three worn
equip slots; the fixed-size `Name`; `Species Klass Background`; `Level Xp`; and the
six ability scores `Str Dex Con Int Wis Cha`. All are `LongInt` except `Name`,
which is a Turbo-Pascal short string written whole.

### Registries

Each registry is a count followed by that many keys. A key is four `LongInt` fields
`depth rx ry idx`, the stable identity of a slain monster or a taken prop, so a
regenerated region leaves the dead dead and the looted rooms empty.

## Versioning

The format has no backward compatibility: the loader checks the magic and the exact
version, and refuses anything else, leaving the live game untouched. Any change to
the serialized layout bumps both the magic's trailing digit and `SAVE_VERSION` in
`saveload.pas`, which invalidates older saves. This is acceptable before 1.0.
