# World streaming

The world is one continuous voxel space, but only the neighbourhood around the player is
ever built and resident. This is what gives a large level the feel of a seamless world
without paying to hold or draw all of it.

## Why streaming, and what streams

The diorama camera sees a bounded region, the player and a room or two, never a vista. So
"massive and seamless" does not mean drawing a huge world. It means two things: coherent
generation so areas connect, and streaming a local window with no load screens. The engine
never needs the whole world resident or on screen.

The logical [tile map](worldgen.md) is the authority and stays whole in memory; it is
cheap. What streams is the expensive visual layer: the voxels and meshes. The world
rasterizes tiles into chunk voxels, meshes them, and frees them again as the player moves.

## Chunks

`src/world/voxchunk.pas` defines a chunk: a `16^3` dense voxel grid sharing the world
palette, with a cached greedy mesh and GPU buffers, a dirty flag, and a world-space
bounding box. The chunk is the unit of meshing, GPU upload, culling, and streaming. A
chunk with no solid voxels holds no mesh and draws nothing.

## The chunk map

`src/world/world.pas` holds chunks in an open-addressing hash map keyed by global chunk
coordinate. The coordinate packs into a 64-bit key, and the space is unbounded, so
coordinates may be negative. This is the hook for the continuous world: the map does not
care where the chunks are, only that the live ones are reachable by coordinate.

The map supports deletion, which a plain open-addressing table does not, by marking a
removed slot as a tombstone rather than empty, so probing still passes over it. Inserts
reuse tombstone slots, and a grow pass rehashes only the live entries and drops the
tombstones, so the table does not fill with the dead. Chunks are heap-allocated and the
map holds pointers, so a chunk can be freed without disturbing the rest.

## The load and evict cycle

`WorldStream` runs every frame with the player's tile position. It does three things:

1. **Load.** For every chunk within `LOAD_RADIUS` chunks of the player, clamped to the
   level's extent, ensure the chunk exists. A missing chunk is created, filled from the
   tile map, greedy-meshed, uploaded, and inserted. An existing one is left alone.
2. **Prefetch.** Find the player's current room in the [room graph](worldgen.md) and
   ensure the chunks of that room and of every room one portal away are resident. This is
   the portal graph doing real work: the next room through a doorway is ready before the
   player reaches it.
3. **Evict.** Scan the live chunks and free any that are no longer wanted: outside the
   larger `KEEP_RADIUS`, and not part of the current room or a portal neighbour. Freeing
   releases the GPU buffers and tombstones the slot.

`LOAD_RADIUS` is smaller than `KEEP_RADIUS` on purpose. The gap is hysteresis: a chunk at
the boundary is not loaded and evicted on alternate frames as the player jitters across a
chunk edge. Prefetch overrides eviction, so a prefetched neighbour room is not immediately
thrown away.

With the current radii a large level keeps only its local window resident, a small
fraction of the whole. The rest exists only as tile codes until the player approaches.

## Rendering the resident set

`WorldRender` builds the frustum from the clip matrix once, then walks the live chunks and
draws each one whose bounding box survives the [frustum test](rendering.md). The diorama
view sees over walls, so the frustum test over chunk bounds is the right culler here, not
strict portal culling. Of the resident chunks, only those actually in view are drawn, a
further cut below the resident count.

## Toward the continuous world

The structure is shaped for more than one region. The next steps, tracked in the roadmap,
are to chunk the tile map itself and generate it per region on demand, and to use the
portal graph to stitch separate zones, so the town and the dungeon, or one dungeon depth
and the next, join through a portal with no break. None of that reshapes the chunk map or
the streaming cycle; it feeds them a larger, lazily generated source.
