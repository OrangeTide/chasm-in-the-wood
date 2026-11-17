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
- What ships: only the baked bitmap. The source `.ttf` is kept out of the
  repository. Embedding the face as baked bitmap data is treated as a separate
  grant that the Solid Frame licence allows.
- Licence: TODO. Record the exact licence name and version, the source where the
  font was obtained, and the author or foundry. Keep a copy of the licence text that
  states the baked-bitmap redistribution grant, so the claim above is backed by a
  document and not only this note.

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
