# Provenance

This file records where the project's shipped art and type assets come from, and
the terms under which they are included. The game code itself is released under the
Unlicense (see `UNLICENSE.txt`). The assets below carry their own terms, recorded
here so the grant is auditable rather than only described in prose.

For the policy that governs what art the project accepts, see the Art policy section
of `docs/build-and-assets.md`.

## Font: Solid Frame (baked as `content/fonts/ui.cfn`)

- Tracked file: `content/fonts/ui.cfn`, a CFN bitmap font.
- Compiled-in fallback: the same face is baked into `src/gui/guigl.pas` as the
  default when no CFN file loads.
- Source: the Solid Frame TTF, baked to a bitmap at pixel size 9 across printable
  ASCII (32..126). The baking process is described in `content/fonts/README.md`.
- Author: potatotastegood, https://potatotastegood.itch.io/solid-frame
- What ships: only the baked bitmap. The source `.ttf` is kept out of the
  repository. A 9-pixel ASCII bitmap does not expose the TTF for extraction, so the
  licence terms below permit it as embedded data in a finished project.
- Licence: a custom licence that ships with the font download. Its terms, quoted:
  - You can use this font in commercial and non-commercial projects.
  - You can't edit, resell, redistribute or share the font file separately.
  - Redistribution is allowed only when the font is embedded as part of a finished
    project that does not expose the font for extraction.
  - Credit is not required, but greatly appreciated.
- Note: the licence forbids redistributing the font file itself, so the `.ttf` is
  not committed. Only the baked `ui.cfn` bitmap ships, as embedded data in the
  finished game. Attribution is given above though the licence does not require it.

## Font: Hollow Crown (wordmark art `docs/wordmark.png`, icon `packaging/chasm.png`)

- Tracked files: `docs/wordmark.png`, the gothic wordmark shown in the README, and
  `packaging/chasm.png`, the same wordmark laid out as the square application icon
  that `make install` and `make bundle` install.
- Source: the Hollow Crown TTF, a blackletter pixel font, rendered to the wordmark
  at pixel size 16 and gold on dark green.
- Author: potatotastegood, https://potatotastegood.itch.io/hollow_crown
- What ships: only the rendered PNGs. The source `.ttf` is kept out of the
  repository. A rasterized image of a few words does not expose the TTF for
  extraction, so the licence terms below permit it as embedded data in a finished
  project.
- Licence: the same custom licence as Solid Frame, shipped with the font download.
  Its terms, quoted:
  - You can use this font in commercial and non-commercial projects.
  - You can't edit, resell, redistribute or share the font file separately.
  - Redistribution is allowed only when the font is embedded as part of a finished
    project that does not expose the font for extraction.
  - Credit is not required, but greatly appreciated.
- Note: the licence forbids redistributing the font file itself, so the `.ttf` is
  not committed. Only the rendered PNGs ship. Attribution is given above though the
  licence does not require it.

## Reference character (build-time voxel asset)

- What ships: nothing in git. The character is generated at build time from an FBX
  through `assimp` to OBJ and then the `voxelize` tool to a MagicaVoxel `.vox`. The
  FBX, the intermediate OBJ, and the generated `.vox` are all build output and are
  ignored by git. See `docs/build-and-assets.md` for the pipeline.
- Terms: the reference character is CC0 (public domain dedication), human-made art,
  per the Art policy in `docs/build-and-assets.md`.
- Source: TODO. Record where the FBX was obtained, the author or pack name, and a
  link to the CC0 dedication. CC0 requires no attribution, but recording the source
  keeps the provenance verifiable.

## Not included

- Music: no tracks ship. The player supplies their own licensed `.ogg` files. See
  `content/music/README.md`.
- Reference asset packs under `REF/` are local reference material only. They are
  excluded by a global git ignore and are never committed or shipped. Many carry
  commercial licences and are not part of the distributed project.
