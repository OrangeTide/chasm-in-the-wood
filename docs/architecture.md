# Architecture

The engine is a set of small Pascal units, each with one concern, compiled into a
single program. Source is grouped by subsystem under `src/`, and the build finds
each group through its own unit search path (see [Build and assets](build-and-assets.md)).

## Module layout

```
src/platform/sdl3      minimal SDL3 binding: window, GL context, events, timing
src/gfx/glcore         OpenGL 3.3 core entry points, loaded at runtime
src/math/vecmath       vectors and 4x4 matrices
src/voxel/voxfile      MagicaVoxel .vox read and write
src/voxel/voxmesh      greedy mesher: voxel grid -> triangle mesh
src/render/gpumesh     a mesh resident on the GPU
src/render/meshshader  the shared lit shader program
src/render/camera      the diorama orbit camera
src/render/frustum     view-frustum culling
src/util/rng           seeded random generator
src/world/tilemap      a bounded logical tile grid
src/world/roomgraph    rooms and the portals between them
src/world/worldgen     hierarchical dungeon carving primitives
src/world/themes       zones and themes, the layer above regions
src/world/tileworld    the unbounded, region-generated tile source
src/world/worldgraph   traversal over the stitched world portal graph
src/world/voxchunk     a cubic block of voxels with a cached mesh
src/world/world        the streaming voxel world
src/gui/gui            retained-mode widget core, backend-agnostic
src/gui/guitheme       the System 7 theme: window and widget chrome
src/gui/guigl          the OpenGL canvas: a 2D overlay of coloured quads
src/game/player        the player position and movement
src/game/panels        inventory, equipment, character, and options panels
src/game/gameui        the desktop, the status window, and event glue
chasm.pas              the program: init, generate, main loop
```

A unit depends only downward, from game and world toward render, voxel, math, and
platform. Nothing in `render` or below knows about the dungeon, and nothing in
`world` knows about SDL.

## The logical map and the voxel geometry

The most important split is between what a tile *is* and how it *looks*. The
[tile map](worldgen.md) is a grid of codes: rock, floor, wall, door. It drives
movement, collision, and later line of sight and spawning. The player moves on the
tile map and is blocked by walls; none of that logic depends on geometry.

The voxel world is a rendering of the tile map. It rasterizes tiles into voxels,
meshes them, and draws them. Gameplay could run with no renderer at all, and the
renderer could draw a different tile source without changing gameplay. This
separation is standard roguelike practice and it keeps each side simple.

## Zones and the world graph

Above the region generator sit two small layers. [Themes](worldgen.md) divide the
world into zones and give each one its look and carving parameters, so `tileworld`
reads the zone theme when it generates a region and `world` reads it when it colours
the voxels. The room graphs the regions produce are stitched at the seam crossings
into one connected graph, which `worldgraph` traverses to confirm the zones form one
seamless space. Both layers are pure functions of the seed and coordinates, so they
need no state beyond the tile world they sit on.

## Data flow

```
seed -> worldgen -> tile map + room graph
                       |
            player <---+ (spawn, collision)
                       |
            world streams chunks around the player:
               tile map -> chunk voxels -> greedy mesh -> GPU
                       |
            camera -> view and projection
                       |
            frustum cull -> draw visible chunks + player
```

Generation runs once. Streaming, culling, and drawing run every frame. The tile
map is the authority the world reads from; the world holds only the chunks near the
player (see [World streaming](world-streaming.md)).

## The frame loop

`chasm.pas` holds the loop. Each frame it reads input and moves the player, streams
the world for the player's new neighbourhood, eases the camera target toward the
player, then clears, binds the shader once, draws the visible chunks and the player,
draws the interface overlay on top, and swaps buffers. A screenshot mode draws one
frame to a PPM and exits, which doubles as a headless render check.

## The interface layer

A retained-mode widget toolkit draws floating windows over the diorama: a status
panel now, inventory and menus later. It is backend-agnostic, drawing through an
abstract canvas that the OpenGL layer renders as a 2D overlay of coloured quads. The
main program drives it through a small wrapper and never sees the toolkit's own
types. See [Interface and HUD](gui.md).
