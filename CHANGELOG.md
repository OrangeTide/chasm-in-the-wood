# Changelog

All notable changes to Chasm in the Wood are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow semantic versioning. Each minor release gets a dated section and an
annotated git tag whose message is that release's changes.

## [Unreleased]

### Added
- SDL3 window with an OpenGL 3.3 core renderer, through hand-rolled minimal
  bindings loaded at runtime.
- MagicaVoxel `.vox` reader and writer.
- Greedy voxel mesher that merges same-colour faces into large quads.
- Diorama camera built as an orbit rig around a target point.
- `voxelize` tool: surface-voxelizes an OBJ mesh into a `.vox`, taking colours
  from the material's diffuse term.
- Asset pipeline that bakes the reference CC0 modular character (FBX) into a
  voxel model through assimp and the voxelizer.
- Modular Makefile split into `mk/*.mk` fragments by concern.
- Player voxel model that moves a tile at a time with WASD or the arrow keys,
  blocked by walls.
- Follow camera that eases its target toward the player each frame, with Q/E to
  orbit and `-`/`=` to zoom.
- Seeded xorshift RNG so a seed reproduces a level.
- Logical tile map (rock, floor, wall, door) kept separate from the voxel
  geometry, driving movement and collision.
- Hierarchical BSP dungeon generator: rooms, connecting corridors, and a wall
  ring.
- Chunked voxel world in one global coordinate space, with chunks held in a hash
  map, rasterized from the tile map, and greedy-meshed per chunk.
- Frustum culling that draws only the chunks the camera can see.
- Chunk streaming: a load-and-evict window keeps only the player's
  neighbourhood resident, so a large level costs its local area.
- Room and portal graph from generation, with portal prefetch that keeps the
  current room and its doorway neighbours resident ahead of the player.
- Engine documentation under `docs/`, one article per subsystem.
- A swappable mesh backend so chunk streaming runs without an OpenGL context, and
  `make test` unit tests for the RNG, generation, and the streaming load and evict
  cycle.

### Changed
- Split the renderer into a shared mesh shader and per-object GPU meshes, so the
  world chunks, the player, and later props draw through one program.
- The world now streams chunks from the tile map instead of building the whole
  level up front; the demo level grew to 128x128 tiles.

### Removed
- Stale tool stubs from the earlier software renderer that no longer compiled.
