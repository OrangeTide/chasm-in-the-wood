# chasm.sav

The single save slot, written beside the executable. Unlike the content tables this
is a binary stream, not a text file. Written and read by `saveload.pas`.

## Layout

The stream is a header, the world location, the player record, the quest flags, and
the change registries, in order. Integers are 32-bit little-endian (`LongInt`);
`Seed` is a 64-bit `QWord`.

| Field | Type | Meaning |
| --- | --- | --- |
| magic | 8 bytes | `CHASMSV6`; the trailing digit is the format version. |
| version | LongInt | `6`; must match exactly or the load is refused. |
| seed | QWord | The world seed. |
| in town | LongInt | `1` in the town, `0` in the dungeon. |
| depth | LongInt | The current dungeon depth. |
| deepest reached | LongInt | The deepest depth reached, which gates shop stock. |
| player | record | The player, see below. |
| slain | registry | Monsters killed, see below. |
| taken | registry | Loot and chests removed, see below. |
| flags | list | The quest and story flags, see below. |
| opened | registry | Locked doors opened, see below. |

### Player record

In order: tile `Cx Cy`; `Hp MaxHp`; derived `Ac Atk DmgDie DmgBonus`; `Alive`
(0/1); `Gold`; `NCarry` followed by that many pack item indices; the three worn
equip slots; the fixed-size `Name`; `Species Klass Background`; `Level Xp`; and the
six ability scores `Str Dex Con Int Wis Cha`. All are `LongInt` except `Name`,
which is a Turbo-Pascal short string written whole.

### Registries

The slain and taken registries are each a count followed by that many keys. A key is
four `LongInt` fields `depth rx ry idx`, the stable identity of a slain monster or a
taken prop, so a regenerated region leaves the dead dead and the looted rooms empty.

The opened-door registry is a count followed by that many keys of three `LongInt`
fields `depth tx ty`, the depth and global tile of each locked door the player has
opened, so a regenerated region leaves those doors open.

### Flags

A count followed by that many flag names. Each name is a `LongInt` length followed by
that many bytes. The flags are the whole quest and story state (see
[quests.md](quests.md) and [dialogs.md](dialogs.md)); the quest log, the objective,
and the journal are all rebuilt from them on load, and the composite `derive` flags
are re-settled.

## Versioning

The format has no backward compatibility: the loader checks the magic and the exact
version, and refuses anything else, leaving the live game untouched. Any change to
the serialized layout bumps both the magic's trailing digit and `SAVE_VERSION` in
`saveload.pas`, which invalidates older saves. This is acceptable before 1.0.
