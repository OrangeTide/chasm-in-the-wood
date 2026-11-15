# Coordinate systems

Several spaces meet in the engine. Keeping them straight avoids the classic bugs:
models on their side, floors at the wrong height, chunks in the wrong place.

## The spaces

**Tile space.** The logical grid, one unit per dungeon tile, integers. The tile map
and the player use it. A tile is `(tx, ty)` with `ty` running in the ground plane,
not up.

**Voxel space.** Integer voxel coordinates. A chunk stores a dense `CHUNK^3` grid in
local voxel coordinates `0..CHUNK-1`. Global voxel coordinates place a chunk in the
world: `global = chunkCoord * CHUNK + local`.

**World space.** The continuous space OpenGL draws in, right-handed, `y` up. One
world unit is one tile edge.

## The scale constants

These live in `world.pas` and are the single place the grids meet:

```
TILE_VOX = 4      voxels per tile edge
VOX      = 0.25   world units per voxel
TILE     = 1.0    world units per tile  (TILE_VOX * VOX)
WALL_VOX = 6      wall height in voxels  (1.5 world units)
CHUNK    = 16     voxels per chunk edge  (from voxchunk.pas; 4 tiles)
```

A tile is four voxels across, a voxel is a quarter of a world unit, so a tile is one
world unit. The player model is scaled to 1.6 world units tall, so it stands above
the 1.5-unit walls and the camera sees over them.

## Which way is up

This is the one real trap. There are two voxel conventions in play.

**MagicaVoxel `.vox` files are `z` up.** The format stores height along `z`. The
voxelizer maps the source OBJ, which is `y` up, into `z` up when it writes a `.vox`.
When the renderer loads a `.vox` model, such as the player, it rotates the model by
`-90` degrees about `x` to stand `z` up into the world's `y` up.

**In-engine chunk voxels are `y` up.** The world builds chunk voxels directly, with
the floor at voxel `y = 0` and walls rising in `+y`. No rotation is needed, so chunk
model matrices are only a translate and a uniform scale.

Keep the rule in mind: anything read from a `.vox` file needs the `z`-up to `y`-up
rotation; anything the engine authors as voxels is already `y` up.

## Converting

- Tile to world, at a tile centre on the floor:
  `world = ((tx + 0.5) * TILE, FLOOR_TOP_Y, (ty + 0.5) * TILE)`, where
  `FLOOR_TOP_Y = VOX` is the top of the floor layer.
- World voxel to chunk: `chunk = floordiv(voxel, CHUNK)`, with a floor division so
  negative coordinates work.
- Voxel to world: `world = voxel * VOX`, applied by the chunk's model matrix as a
  translate to the chunk origin times a scale of `VOX`.
