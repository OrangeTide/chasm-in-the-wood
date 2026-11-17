# Fonts

The interface loads `ui.cfn` at startup as the HUD and window font. When the file
is absent or will not decode, the canvas keeps its compiled-in Solid Frame face,
so the game still runs.

## CFN format

CFN is a compact bitmap font the canvas renders directly. Every field is a byte,
so there is nothing to byte-swap. Glyphs cover one contiguous code range.

```
'C' 'F' 'N' '1'
u8 CellH        rows per glyph cell
u8 Asc          baseline row from the top of the cell
u8 Lo, u8 Hi    first and last code point
u8 RowBytes     bytes per glyph row
Adv[Lo..Hi]     one advance-width byte per glyph
Bits[Lo..Hi]    CellH*RowBytes bytes per glyph, rows top to bottom,
                bit 7 of the first byte the leftmost column
```

`ui.cfn` here is baked from the Solid Frame face across printable ASCII (32..126).

## Baking a font

`tools/bdf2cfn.awk` turns a BDF bitmap font into CFN. Produce a BDF from a pixel
TTF with `otf2bdf`, then bake it. Run the bake under `LC_ALL=C` so the high byte
values are written raw rather than as UTF-8.

```
otf2bdf -p 9 MyFont.ttf -o myfont.bdf
LC_ALL=C gawk -f tools/bdf2cfn.awk myfont.bdf > content/fonts/ui.cfn
```

Only the baked `ui.cfn` is tracked. A source `.ttf` whose licence forbids
redistribution is kept out of the repository; embedding it as baked bitmap data
is a separate grant that the Solid Frame licence allows.
