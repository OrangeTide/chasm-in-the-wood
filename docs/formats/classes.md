# classes.txt

The playable classes. Read by `ReadClass` in `content.pas`. See [README](README.md)
for the shared line syntax.

## Record

```
class  ID  "Name"  TRACK  HITDIE  PRIME  KIT  DOMAIN  [SCHOOL]
```

Keyword `class`, the id, the quoted name, then six fields of which the last
(`SCHOOL`) is optional. A line with fewer than eight fields is skipped.

| Field | Meaning |
| --- | --- |
| `ID` | Unique id (`FIGHTER`). |
| `"Name"` | Display name, quoted. |
| `TRACK` | Broad role: `warrior priest specialist mage`. |
| `HITDIE` | Hit die size for health per level. |
| `PRIME` | Prime ability: `STR DEX CON INT WIS CHA`. |
| `KIT` | Starting-gear archetype: `soldier heavy archer priest thief mage`. |
| `DOMAIN` | Spell list drawn from: `none cleric druid magicuser`. |
| `SCHOOL` | Optional favoured arcane school; makes a mage a specialist. |

## SCHOOL

Omit (the field absent) for a generalist. A named school makes a mage a
specialist, barred from its opposition schools (Lesser Divination is always
allowed). The schools are:

`abjuration conjuration divination enchantment evocation illusion necromancy
transmutation`

The `KIT` value selects which loadout a new character of this class begins with.

## Example

```
class FIGHTER   "Fighter"   warrior  8 STR soldier none
class BERSERKER "Berserker" warrior 10 STR heavy   none
class WIZARD    "Wizard"    mage     4 INT mage    magicuser evocation
```
