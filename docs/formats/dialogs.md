# dialogs.txt

Conversations: the lines townsfolk and dungeon interaction points speak, and the
responses the player picks. Read by `LoadDialogs` in `dialogtext.pas`; the runtime
that walks a conversation is in `dialogtext.pas` too, over a flag set (`flags.pas`).
See [README](README.md) for the shared line syntax.

A dialog is a list of nodes. A node shows a line of narration and a set of
responses. Choosing a response acts: move to another node, raise a quest flag,
open a shop, or hand a world action (recruit, revive, identify, fight) back to the
game. A response guarded by `needflag` is offered only once that flag is set.
Raising a flag goes through the quest system (see [quests.md](quests.md)), so a
conversation drives quests and the journal.

## Records

```
dialog  ID
  node   N
    text  "the speaker's line"
    resp  "player response"  ACTION  [needflag FLAG]
```

A `dialog` line opens a dialog; the `node`, `text`, and `resp` lines that follow
attach to it until the next `dialog`. Nodes are numbered from 0 in file order, and a
`goto` names a node by that number.

| Token | Meaning |
| --- | --- |
| `dialog ID` | Opens a dialog with an id, named by a town role or an interaction point. |
| `node N` | Opens a node. Nodes are taken in order, so `N` matches their position from 0. |
| `text "..."` | The narration shown at the current node. |
| `resp "..." ACTION` | A response: its text, and the action taken when it is chosen. |

A `node`/`text`/`resp` before any `dialog`, or a `resp` with fewer than three
fields, is skipped.

## Response actions

The action is the field after the response text. One of:

| Action | Effect |
| --- | --- |
| `goto N` | Move to node `N` and stay in the conversation. |
| `setflag FLAG` | Raise `FLAG` through the quest system, then close the conversation. |
| `shop ID` | Open the trade window for shop `ID` (see [shops.md](shops.md)); the talk stays open. |
| `recruit` | Hand a recruit action to the game; the talk stays open. |
| `revive` | Hand a revive action to the game; the talk stays open. |
| `identify` | Hand an identify action to the game; the talk stays open. |
| `fight ENEMY FLAG` | Start a fight with `ENEMY`; `FLAG` is granted on the win. Closes the talk. |
| `end` | Close the conversation. |

An unrecognised action is treated as `end`.

## needflag

Any response may end with `needflag FLAG`. The response is offered only when `FLAG`
is set, so a conversation can reveal a new choice once the player has reached a
quest stage. The keyword may sit anywhere after the action; the action is read from
the tokens before it.

```
resp "I bear the relic you sought."  goto 2  needflag QUEST_RELIC
```

## Semantics

- A conversation begins at a dialog's node 0. `ConvoText` returns the current
  node's narration, `ConvoResps` the responses offered after dropping any whose
  `needflag` is unset, and `ConvoChoose` applies the chosen response.
- `goto` moves the node; `setflag`, `fight`, and `end` close the conversation;
  `shop`, `recruit`, `revive`, and `identify` leave it open so the player can pick
  again once the game has acted.
- Flags are shared with the quests and the save (see [quests.md](quests.md) and
  [save.md](save.md)), so raising one from a conversation advances the quest log and
  persists.

## Example

```
dialog ELDER
node 0
text "You there. The town has need of brave sorts. Will you help us?"
resp "What is wrong?" goto 1
resp "I bear the relic you sought." goto 2 needflag QUEST_RELIC
resp "Not now." end
node 1
text "An old relic broke into three shards. Gather all three and bring it to me."
resp "I accept the charge." setflag QUEST_MAIN
resp "I must decline." goto 0
```
