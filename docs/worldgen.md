# World generation

Generation produces two things from a seed: the logical tile map that gameplay reads,
and a room and portal graph that streaming and later systems use. The same seed always
produces the same level.

## The tile map

`src/world/tilemap.pas` is a grid of tile codes: rock, floor, wall, door. Rock is
unexcavated and neither walkable nor drawn. A tile map answers the queries gameplay
needs, chiefly "is this tile walkable", and carries a spawn tile. It holds no geometry;
the voxel world renders it. The bounded tile map is used for a single fixed level and in
tests; the game itself reads tiles from the unbounded tile world described below.

## Seeded randomness

`src/util/rng.pas` is a xorshift64* generator. The engine uses it instead of the
platform RNG so a seed reproduces the same world on every host, which matters for a
roguelike and for reproducing bugs. It gives a next value, a value below a bound, and a
value in an inclusive range.

## Hierarchical layout

`src/world/worldgen.pas` lays a level out with a binary space partition, which is the
bottom layer of the generation hierarchy, region down to rooms. The layer above it is
zones and themes, described below. The carving primitives, `CarveRooms` and `LayWalls`,
work on a flat tile buffer, so they serve both the bounded `GenerateDungeon` and the
per-region generation of the unbounded tile world. `CarveRooms` takes a `TGenParams`,
the room size and partition depth, so a theme can make its rooms larger or tighter.

The partition splits the region into leaves, preferring to cut the longer axis and
stopping when a leaf is small enough or the recursion is deep enough. Each leaf carves a
room, a random rectangle inside the leaf with a margin. As the recursion unwinds, each
pair of sibling subtrees is joined by a corridor between the representative rooms they
return. Corridors are L-shaped, a horizontal leg then a vertical leg.

After rooms and corridors are carved as floor, a wall pass sets any rock tile that
touches a floor tile, counting diagonals, to wall. That lays a one-tile wall ring around
all the carved space, including corners.

## The room and portal graph

`src/world/roomgraph.pas` records the structure the partition discovers. Every carved
room becomes a node with its tile rectangle. Every corridor becomes a portal edge joining
the two rooms it connects, with a representative tile on the connection. Because corridors
are added as the tree unwinds, the graph is connected: there is a path of portals between
any two rooms.

The graph answers "which room contains this tile", returning none for a corridor or rock,
and it exposes rooms and portals for traversal. Its first concrete use is prefetch during
streaming: keep the player's current room and the rooms one portal away resident so
crossing a doorway never stalls. See [World streaming](world-streaming.md). Later it
carries portal-based occlusion and the seams that link one zone to the next.

## The unbounded tile world

`src/world/tileworld.pas` turns generation into an infinite, streamed space. The world is
divided into fixed-size regions of tiles, and a region is generated the first time a tile
inside it is read, from a seed derived from the world seed and the region coordinates.
Generation is therefore deterministic: a region always comes back the same, so it can be
discarded and regenerated.

Regions join without seams because neighbours agree on where corridors cross the shared
edge. Each edge between two regions has a canonical identity, the lower-coordinate region
plus an axis, and both regions derive the same crossing position from it. A region carves
a short corridor from its nearest room out to each of its four edge crossings. The two
crossings on a shared edge meet at the boundary, so the dungeon is one connected space
across regions, with no fixed extent. Within a region the rooms form a connected tree, and
the edge crossings link every region to its four neighbours, so the whole infinite grid is
reachable.

Resident regions are capped. Each access stamps a region with a recency clock, and when the
count passes the cap the least recently used region is freed. Because generation is
deterministic, a region that is evicted and later needed again regenerates identically, so
eviction has no visible effect and memory stays bounded however far the player walks.

## Zones and themes

`src/world/themes.pas` is the layer above regions. The world is divided into zones,
square blocks of `ZONE_REGIONS` regions on a side, and each zone is assigned a theme from
a small table. The assignment is a hash of the zone coordinates and the world seed, so a
zone always has the same theme, and because the tile world folds the depth into its seed,
a given zone differs from one depth to the next.

A theme sets how an area looks and how it is carved: the floor, wall, door, and stair
colours, the wall height, and the room size and partition depth passed to `CarveRooms`.
The five themes range from the plain catacombs through a flooded cistern, a tight warren,
a tall cathedral, and the embers below. Region generation reads its zone's theme for the
carving parameters, and the voxel world reads each tile's zone theme for the colours and
wall height when it rasterizes. Because the theme is a pure function of the coordinates
and the seed, neither step needs the region resident to know its theme.

Zone boundaries are hard: adjacent regions in different zones meet with an abrupt change
of colour and wall height, which reads as crossing from one area into another. The seam
crossings still line up across the boundary, because the crossing positions do not depend
on the theme, so the dungeon stays one connected space even where the look changes.

## Doors

After the walls are laid, `PlaceDoors` marks a door on each floor tile that is a single
crossing through a wall, where a corridor enters a room or a wider space. It looks for a
floor tile with walls on two opposite sides where at least one side along the passage opens
out of that flanking. Long corridors with walls on both sides for their whole length are
left plain, so doors land at entrances rather than all down a passage. Doors are walkable
and render as a wood threshold framed by posts on the wall sides.

## Depths and stairs

The dungeon is a stack of depths. Each depth is its own unbounded tile world, seeded by
folding the depth number into the world seed, so every depth is a different dungeon while
staying deterministic. The player is always on one active depth; descending rebuilds the
voxel world from the next depth's tiles.

Stairs are scattered across the world rather than clustered at the origin. A region hosts
a down-stair when a hash of the raw seed, the depth, and the region coordinates says so,
about one region in four, with the origin region always included so there is a reachable
descent from the start. An up-stair is placed in a region exactly when the same region one
depth up hosts a down-stair, which keeps every descent matched by the ascent back. The
predicate uses the raw seed and the depth, not the folded per-depth seed, so a depth can
work out where the depth above put its down-stairs.

Stairs sit at room centres, so the player arrives standing on one. Descending from a
region's down-stair places the player on the same region's up-stair one depth down;
ascending reverses it, back to the down-stair they left. Because the two depths are
different dungeons, the matched stairs sit at different spots inside the region, so the
player moves as well as changes depth. A down-stair renders as dark descending steps and
an up-stair as light rising steps.

## Tiles to geometry

Generation stops at the tiles. The voxel world rasterizes tiles into chunk voxels on
demand: a floor tile fills a floor voxel layer, a wall tile a solid column as tall as the
zone theme's wall height, a door a wood threshold with jamb posts, a stair a stepped
wedge, and rock fills nothing. The colours also come from the tile's zone theme. Reading a
chunk's tiles pulls the tile regions it overlaps into existence, so the voxel window and
the generated tile regions advance together. The tile colours are flat placeholders
generated in code, to be replaced by authored voxel tiles before release.
