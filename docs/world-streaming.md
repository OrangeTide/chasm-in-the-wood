# World streaming

The world is one continuous voxel space, but only the neighbourhood around the player is
ever built and resident. This is what gives a large level the feel of a seamless world
without paying to hold or draw all of it.

## Why streaming, and what streams

The diorama camera sees a bounded region, the player and a room or two, never a vista. So
"massive and seamless" does not mean drawing a huge world. It means two things: coherent
generation so areas connect, and streaming a local window with no load screens. The engine
never needs the whole world resident or on screen.

Two layers stream together. The logical tiles come from the unbounded
[tile world](worldgen.md), which generates a region the first time a tile inside it is
read and keeps the most recently used ones, evicting the least recently used past a cap.
Regions are cheap, a byte per tile, and evicting one is safe because generation is
deterministic: walking back regenerates it identically. The expensive visual layer, the
voxels and meshes, is what the chunk cycle below loads and frees. Reading a chunk's tiles
pulls the regions it overlaps into existence, so the two advance together as the player
moves, with no fixed world bounds and bounded memory.

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

`WorldStream` runs every frame with the player's tile position. It does two things:

1. **Load.** For every chunk within `LOAD_RADIUS` chunks of the player, ensure the chunk
   exists. There is no bound on the coordinates; the world is unbounded. A missing chunk
   is created, filled from the tile world, which generates any regions it needs,
   greedy-meshed, uploaded, and inserted. An existing one is left alone.
2. **Evict.** Scan the live chunks and free any past the larger `KEEP_RADIUS`. Freeing
   releases the GPU buffers and tombstones the slot.

`LOAD_RADIUS` is smaller than `KEEP_RADIUS` on purpose. The gap is hysteresis: a chunk at
the boundary is not loaded and evicted on alternate frames as the player jitters across a
chunk edge.

The load radius reaches a little past a region boundary, so the next region is generated
and its chunks are built before the player arrives, which is what keeps crossing a seam
from stalling. The world therefore keeps only a local window resident no matter how far
the player walks; the rest exists only as tile regions, or not yet at all.

The [room and portal graph](worldgen.md) is produced per region and stitched across region
and zone boundaries into one connected graph. It is not the streaming driver, since the
radius load pulls in whatever is near, but it is the connectivity backbone the engine uses
to confirm that separate zones form one seamless space, and the place future portal
occlusion will attach.

## Rendering the resident set

`WorldRender` builds the frustum from the clip matrix once, then walks the live chunks and
draws each one whose bounding box survives the [frustum test](rendering.md). The diorama
view sees over walls, so the frustum test over chunk bounds is the right culler here, not
strict portal culling. Of the resident chunks, only those actually in view are drawn, a
further cut below the resident count.

## Toward the continuous world

The tile world is already unbounded, seamless across regions, and bounded in memory by
least-recently-used eviction, so a single dungeon layer has no edge and walking forever is
free. Zones and themes give it variety, and the stitched portal graph confirms those zones
join into one connected space. The remaining steps, tracked in the roadmap, build content
on top of that source rather than reshape the streaming cycle: entities, a turn loop, and
the town hub joined to the dungeon.
