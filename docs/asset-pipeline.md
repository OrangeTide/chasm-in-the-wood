# Asset pipeline and scale

How source art becomes voxels at one consistent world scale. The pipeline converts a
source mesh (FBX exported to OBJ, then the `voxelize` tool) into a `.vox` model sized so
that art from different kits shares a single world. Voxelization is 3D quantization: the
conversion is governed by a sampling rate (the voxel size), a sampling phase (a per-kit,
per-axis offset), and a separate palette quantization for colour. The parameters on this
page are pinned, and an asset converts from them mechanically, with no per-asset tuning
beyond the small facts carried in the asset manifest (slot, solid or surface, variant).

## The reference

Every scale is anchored to the character, because a character is the one asset whose real
size is unambiguous and is shared in spirit across kits. The quaternius base character
measures 1.82 units tall and is modelled at metre scale, so the world is calibrated to a
**1.8 m adult**. From that, a grid cell is one character space and a wall stands above
head height.

## Global parameters

| Parameter | Value | Meaning |
| --- | --- | --- |
| Cell size | **1.5 m** | One grid cell. One world unit (the engine's `TILE`). A corridor one cell wide. |
| Voxel size | **0.0625 m** (1/16 m) | One voxel. Fixed, the same physical size for every asset. |

Derived from those two:

- **24 voxels per cell** (1.5 / 0.0625), and **96 voxels per 4-cell tile module** (see the
  dungeon kit below).
- A 1.8 m character is **29 voxels** tall; a 2.4 m wall is **38 voxels**; a 0.7 m chest is
  **11 voxels**.

The voxel size is set by the styloo prison bars, the finest periodic feature we care to
resolve. At 0.0625 m a bar comes out about one voxel thick with about four voxels between
bars, which is the rate that keeps the bars from aliasing (see the dungeon-tile pitch note
in `content/tiles/README.md`). Cell size then follows: 1.5 m is the coarsest cell that
still keeps those bars above one voxel, and it gives the round 24 voxels per cell.

Engine constants these imply, to apply when the tile and model scale is reworked (not yet
done): the object voxel-unit `VU` becomes `voxel / cell` = **0.04167** world units per
voxel (it is 0.0625 today, which oversizes models), and the generated tile footprint is
**24** voxels per cell, not the 96 the current pitch note labels (96 is per module, which
is four cells).

## Per-kit scale

Each kit is in its own arbitrary unit, so each carries one scale: units to metres,
calibrated once from a reference feature of known real size. `scale = real_metres /
measured_units`. Prefer a humanoid height (about 1.8 m) for creature kits, a wall or storey
(about 3 m) or a door for architecture, and a known prop for prop kits.

| Kit | Reference feature (units) | Assumed real size | Scale (m/unit) |
| --- | --- | --- | --- |
| styloo `dungeon-asset-pack` | floor module 263, wall 106, door 83 | module 6.0 m (4 cells) | **0.0227** |
| quaternius `universal-base-characters` | character 1.82 | 1.82 m | **1.0** |
| quaternius `modular-character-outfits-fantasy` | worn on the base character | same family | **1.0** |
| quaternius `fantasy-props-megakit` | chest 71 | 0.70 m | **0.0099** |
| quaternius `medieval-village-megakit` | wall corner 300 | 3.0 m | **0.0100** |
| quaternius `lowpoly-medieval-weapons` | sword 545 | 1.00 m | **0.00184** |
| quaternius `lowpoly-animated-monsters` | skeleton 509 | 1.80 m | **0.00354** |
| quaternius `stylized-nature-megakit` | path tile 205, tall grass 187 | path tile ~1.0 m | **0.005** |

Notes on the table:

- The dungeon scale is cross-checked two ways that agree: it is the voxel size over the bar
  pitch (0.0625 / 2.75 styloo-units = 0.0227), and it makes the 263-unit floor module span
  very nearly four cells (5.97 m). It also puts the wall at 2.41 m and the door at 1.89 m,
  which admits the 1.8 m character.
- `stylized-nature` is anchored on its wide square rock-path tile at about 1.0 m, the
  walkable ground piece, since the kit is a scatter kit with no floor module. The kit is
  stylized and not internally to scale (its grass is large next to its trees), so a tree is
  a poor anchor. The chosen scale reads tree 3.6 m, tall grass 0.94 m, and short grass
  0.67 m against the 1.8 m character.
- The real-size assumptions (sword 1.0 m, skeleton 1.8 m, chest 0.7 m, village storey 3 m)
  are design choices. They are stated here so they can be adjusted in one place.

## From parameters to a conversion

- **Resolution is derived, never set per asset.** For an asset of extent `E` metres on an
  axis, the voxel count is `E / 0.0625`. In native units that is `extent_units * scale /
  0.0625`. So `voxelize` should take a voxel size, not a resolution, and apply the kit
  scale, so every asset in a kit converts at the same physical voxel size with no per-file
  numbers. A styloo wall module (263 units) comes out at 96 voxels; a one-cell slice of it
  at 24.
- **Phase and anchor** are the per-kit, per-axis offset. Standalone props and characters
  centre on the horizontal axes with a half-voxel offset so they voxelize symmetrically,
  and seat their base at zero on the vertical axis (feet on the floor). Tile pieces take a
  zero, module-aligned phase so neighbours tile without a seam.
- **Solid fill is the default** (flood the exterior, fill the enclosed interior). Grates,
  foliage, and other open shapes pass `surface` to keep the bare shell.
- **Colour** is a separate palette quantization. Each `.vox` carries its own 256-colour
  palette, so a scene mixes many palettes and there is no global one. Reduce a mesh's
  materials to the palette with a real colour quantizer, and reserve dithering for colour,
  never for occupancy, since dithering a hard grid is what produces speckle.

## The converter

The pipeline is three files under `tools/` and is run with no per-asset numbers:

- `tools/kits.txt`: the global voxel size and each kit's scale and up-axis.
- `tools/assets.txt`: the manifest, one line per asset: its kit, its source, its output,
  and the optional `surface` flag and `offset`.
- `tools/convert`: the driver. For each manifest line it looks up the kit, derives the
  units per voxel as `voxel / scale`, runs the source through assimp when it is not already
  an OBJ, and runs the voxelizer at that voxel size with the kit's up-axis and the asset's
  offset and surface flag.

```
make tools                        # build the voxelizer
ASSET_ROOT=<staged sources> tools/convert
```

`ASSET_ROOT` is the directory holding the extracted kit sources. Staging the sources out of
the kit archives is a separate step, because the archive layout is per kit and the archives
are read-only. A styloo wall converts to 96 voxels and a character stands at 29, both
without a resolution in the manifest.

## Status

Calibrated: the dungeon, character, props, village, weapons, monster, and nature kits
above. Not yet measured: `animated-easy-enemies`, the fertile-soil terrain packs, and the
styloo weapon and animal packs. Calibrate each the same way, from one reference feature,
when it is first converted.
