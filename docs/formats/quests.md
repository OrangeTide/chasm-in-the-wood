# quests.txt

The quest log: titled quests with flag-gated stages, derived flags, and journal
lines. Read by `LoadQuests` in `content.pas`; the runtime logic is in `quests.pas`
over a flag set (`flags.pas`). See [README](README.md) for the shared line syntax.

Quests carry no world positions. They are driven entirely by flags, which the
dialogue (see [dialogs.txt](dialogs.md)) and map events raise. A flag is a short
upper-case id such as `QUEST_MAIN` or `SHARD_CRYPT`.

## Records

```
quest  ID  "Title"
  stage  FLAG  "objective shown once FLAG is set"
  done   FLAG  "line shown when the quest completes"

derive  TARGET  SRC  SRC  ...
log     FLAG    "journal line added when FLAG is first set"
```

A `quest` line opens a quest; the `stage` and `done` lines that follow attach to it
until the next `quest`. `derive` and `log` lines stand on their own.

| Token | Meaning |
| --- | --- |
| `quest ID "Title"` | Opens a quest with an id and a display title. |
| `stage FLAG "..."` | An ordered stage. Its text is the objective shown once `FLAG` is set. |
| `done FLAG "..."` | The quest is complete once `FLAG` is set; the text is its closing journal line. |
| `derive TARGET SRC...` | Sets `TARGET` once every `SRC` flag is set (a composite objective, like assembling a relic from its shards). |
| `log FLAG "..."` | Adds a journal line when `FLAG` is first set, for events that are not a quest stage. |

A line with fewer than three fields, or a `stage`/`done` before any `quest`, is
skipped.

## Semantics

- A quest is **active** once any of its stage flags is set, and **complete** once its
  `done` flag is set.
- The **current objective** of a quest is the last stage whose flag is set, so setting
  a later stage's flag advances the objective. The HUD shows the current objective of
  the first active, incomplete quest.
- `derive` rules settle whenever a flag is raised: a target whose sources are all set is
  raised too, which can cascade into further derives. After a load restores the raw
  flags, `QuestSettle` re-runs the derives.
- The journal is rebuilt from the flags: a line per set `log` flag, then a closing line
  per completed quest, in file order. Only the flags are saved (see [save.md](save.md));
  the journal and the objective are derived from them.

## Example

```
quest Q_RELIC "The Broken Relic"
  stage QUEST_MAIN   "Gather the three relic shards: crypt, cave, and the infernal deep."
  stage QUEST_RELIC  "The relic is whole. Return it to the elder."
  done  QUEST_WON    "You walked into the lost cities of the Sunless Depths."

derive QUEST_RELIC SHARD_CRYPT SHARD_CAVE SHARD_INFER

log SHARD_CAVE "Took the cave shard from the grotto."
```
