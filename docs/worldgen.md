# World generation

Generation produces two things from a seed: the logical tile map that gameplay reads,
and a room and portal graph that streaming and later systems use. The same seed always
produces the same level.

## The tile map

`src/world/tilemap.pas` is a grid of tile codes: rock, floor, wall, door. Rock is
unexcavated and neither walkable nor drawn. The map answers the queries gameplay needs,
chiefly "is this tile walkable", and carries the spawn tile. It holds no geometry; the
voxel world renders it. For now the map is one bounded region. When the world streams
across a larger space, this becomes a chunked, unbounded structure behind the same
queries.

## Seeded randomness

`src/util/rng.pas` is a xorshift64* generator. The engine uses it instead of the
platform RNG so a seed reproduces the same world on every host, which matters for a
roguelike and for reproducing bugs. It gives a next value, a value below a bound, and a
value in an inclusive range.

## Hierarchical layout

`src/world/worldgen.pas` lays the level out with a binary space partition, which is the
bottom layer of the generation hierarchy, region down to rooms. Higher layers that place
zones and themes come later.

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

## Tiles to geometry

Generation stops at the tile map and the graph. The voxel world rasterizes tiles into
chunk voxels on demand: a floor or door tile fills a floor voxel layer, a wall tile fills
a solid column `WALL_VOX` voxels tall, and rock fills nothing. The tile colours are flat
placeholders generated in code, to be replaced by authored voxel tiles before release.
