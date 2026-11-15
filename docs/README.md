# Chasm Engine Documentation

These articles describe the design and the technologies behind the Chasm engine, a
third-person voxel renderer and world for the dungeon-crawl roguelike described in
the top-level README. Each article covers one subsystem and points at the units
that implement it.

## Articles

- [Architecture](architecture.md). The module layout, the data flow from
  generation to pixels, and the split between the logical map and the voxel
  geometry.
- [Coordinate systems](coordinates.md). Tiles, voxels, chunks, and world units,
  and where the engine converts between them.
- [Rendering](rendering.md). SDL3, the OpenGL 3.3 core context, the hand-rolled
  bindings, the mesh shader, and frustum culling.
- [Voxels](voxels.md). The MagicaVoxel `.vox` format, the greedy mesher, and the
  OBJ voxelizer that feeds the asset pipeline.
- [World generation](worldgen.md). Hierarchical dungeon generation, the tile map,
  and the room and portal graph.
- [World streaming](world-streaming.md). The chunked world, the chunk hash map, the
  load and evict cycle, and portal prefetch.
- [Build and assets](build-and-assets.md). The modular Makefile, the FBX to voxel
  pipeline, and the release process.

## Reading order

Start with [Architecture](architecture.md) for the shape of the whole system, then
[Coordinate systems](coordinates.md) because several spaces meet in the renderer.
The remaining articles stand on their own.

## Scope

The documentation tracks the engine as it is built, release by release. Where a
subsystem is a foundation with more to come, the article says so and points at the
roadmap entry. Design decisions and their reasons live here; the changelog records
what shipped and when.
