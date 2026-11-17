# strings.txt

The game's user-visible text: window titles, button captions, menu and dialogue
lines, place and theme names, and the combat and status messages. Keeping the
wording here lets it change without touching the sources. Read by `UIStrLoad` in
`uitext.pas`. See [README](README.md) for the shared line syntax.

## Record

```
str  KEY  "value"
```

Keyword `str`, a key with no spaces, then the value. The value is everything
between the first and last double quote on the line, so it may hold spaces, `%`
placeholders, and `|` separators.

| Token | Meaning |
| --- | --- |
| `KEY` | The lookup key the sources reference (`win_status`, `msg_hit`). |
| `"value"` | The text, quoted. |

## Placeholders

A value may carry `Format`-style placeholders the game fills in at the call site:

- `%s` a string (a name).
- `%d` a number.

For example `str msg_hit "You hit %s for %d."` is filled with the foe's name and
the damage. The order and count of placeholders must match what the caller passes.

## Multi-line values

A `|` in the value separates lines, for a menu body or any text drawn over several
rows. A double `||` keeps a blank line between.

```
str menu_death_body "The dark takes you.|Brackenridge will raise you,|your purse and pack intact."
```

## Lookup

- `UIStr(key)` returns the value, or `[key]` when the key is missing, so a gap shows
  in play rather than passing silently.
- `UIStrFmt(key, args)` fills the placeholders.
- `UIStrList(key)` splits the value on `|` into its lines.

Identifiers, debug output, and error messages are not in this file; they stay in
the code.

## Example

```
str win_status  "STATUS"
str btn_quit    "QUIT"
str msg_pickup  "You pick up the %s."
str theme_town  "Brackenridge"
```
