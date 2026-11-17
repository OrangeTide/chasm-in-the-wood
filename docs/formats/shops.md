# shops.txt

What each shop stocks, with a depth gate so the stock grows as the player
descends. Read by `LoadShops` in `content.pas`. See [README](README.md) for the
shared line syntax.

## Record

```
shop  ID  [@N]  ITEM  ITEM  ...
```

Keyword `shop`, the shop id, then the item ids it stocks, in order. A shop id may
repeat across lines to continue its stock. A line with fewer than two fields is
skipped.

| Token | Meaning |
| --- | --- |
| `ID` | The shop id (`GENERAL`, `APOTHECARY`). A dialogue opens a shop by id. |
| `@N` | A depth gate: the items after it on the line are stocked only once the player's deepest dungeon depth reached is at least `N`. |
| `ITEM` | An item id from [items.txt](items.md). Unknown ids are skipped. |

`@N` applies to the items that follow it on the same line and resets to `0` (always
stocked) at the start of each line. Prices come from the item's `VALUE`: the trader
buys at full value and pays half when buying the pack back.

The deepest depth reached is tracked across the session and saved (see
[save.md](save.md)), so returning to town after a deeper run reveals sterner wares.

## Example

```
# Always on the shelf, then gated tiers.
shop GENERAL DAGGER SWORD SPEAR LARMOR SHIELD TORCH KEY
shop GENERAL @2 BOW MARMOR
shop GENERAL @4 GREATAXE HARMOR

shop APOTHECARY POTION SCRMEND
shop APOTHECARY @3 ELIXIR SCRLIGHT
```
