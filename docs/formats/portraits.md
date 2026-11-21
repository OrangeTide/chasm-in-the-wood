# Portrait atlas (`.por`)

A `.por` file is a 1-bit portrait atlas: a set of small monochrome portraits the
GUI draws through the same bitmap path as the font. The decoder is
`src/gui/portrait.pas`; atlases are cooked from a source sheet by
`tools/portraitcrop`. The engine draws a portrait with `TCanvas.DrawBitmap`, which
fills one quad per set pixel in a chosen ink colour, so a portrait takes the UI's
colour rather than the sheet's.

This page documents the binary format and the cook manifest. No portrait art
ships in the repository; a sheet is supplied at cook time and the atlas is built
from it.

## Binary layout

All multi-byte integers are little-endian. The file is a header, a directory,
then the packed bitmaps.

```
+-----------------------------+  offset 0
| 'P' 'O' 'R' '1'             |  magic (4 bytes)
| u16 count                   |  number of portraits
+-----------------------------+  offset 6
| dir[0]   (12 bytes)         |
| dir[1]   (12 bytes)         |
| ...                         |
| dir[count-1]                |
+-----------------------------+  6 + count*12
| bitmap 0                    |  in directory order, back to back
| bitmap 1                    |
| ...                         |
+-----------------------------+
```

### Directory entry (12 bytes)

| off | size | field      | meaning                                        |
|-----|------|------------|------------------------------------------------|
| 0   | 8    | `name`     | portrait name, uppercase ASCII, NUL-padded     |
| 8   | 1    | `w`        | width in pixels                                |
| 9   | 1    | `h`        | height in pixels                               |
| 10  | 1    | `rowBytes` | bytes per row, `(w + 7) div 8`                 |
| 11  | 1    | `flags`    | reserved, zero                                 |

A name shorter than 8 bytes is NUL-padded; an 8-byte name has no terminator.
Lookups (`PortraitFind`) are case-insensitive. Portraits may differ in size
within one atlas.

### Bitmaps

Each portrait's bits follow the directory, in the same order, with no gaps. A
bitmap is `h * rowBytes` bytes: `h` rows of `rowBytes` bytes, top row first. In a
row, bit 7 is the leftmost column. A set bit is ink (drawn); a clear bit is
transparent. The loader derives each portrait's offset by summing the sizes of
the earlier entries, and rejects a file whose declared sizes do not match its
length.

## Cook manifest

`tools/portraitcrop <manifest> <out.por>` builds an atlas from a text manifest.
Lines are whitespace-separated; `#` starts a comment.

| directive | meaning |
| --- | --- |
| `sheet <path>` | set the current source image (PNG, read via FPImage) |
| `threshold <0..255>` | luminance cut for ink; default 128 |
| `portrait <NAME> <x> <y> <w> <h>` | cut one named portrait from the sheet |
| `grid <PREFIX> <x0> <y0> <w> <h> <cols> <rows>` | cut a grid, naming cells `PREFIX0`, `PREFIX1`, ... left to right, top row first |

A source pixel becomes ink when it is opaque (alpha >= 128) and darker than the
threshold, so dark art on a transparent or a light background cooks the same.
Names are upper-cased and truncated to 8 characters.

Example: slice a 14x20 grid of 32x32 cells into 280 portraits `FACE0`..`FACE279`.

```
sheet assets/portraits/faces.png
grid FACE 0 0 32 32 14 20
```

## Licence note

The cook tool and this format carry no art. A portrait sheet must be CC0 or
otherwise redistributable before its cooked `.por` is committed, and its source
and licence recorded in `PROVENANCE.md`, like every other shipped asset.
