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
src/world/tileworld    the unbounded dungeon, or the bounded town, as a tile source
src/world/town         the fixed layout of the Brackenridge hamlet
src/world/worldgraph   traversal over the stitched world portal graph
src/world/voxchunk     a cubic block of voxels with a cached mesh
src/world/world        the streaming voxel world
src/gui/gui            retained-mode widget core, backend-agnostic
src/gui/guitheme       the System 7 theme: window and widget chrome
src/gui/guigl          the OpenGL canvas: a 2D overlay of coloured quads
src/game/player        the player position, movement, and combat stats
src/game/content       loads the content tables: monsters, items, species, classes
src/game/entities      deterministic monster and prop placement, plus the slain registry
src/game/critters      procedural placeholder voxel models for the inhabitants
src/game/turns         the turn loop: scheduling, monster AI, melee combat, and death
src/game/townsfolk     the people of Brackenridge and the builder that places them
src/game/saveload      serialize and restore the game state to a file
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

## Entities and content

The content tables under `content/` are loaded once into plain records by `content`:
monsters, items, species, and classes. On top of them, `entities` places monsters
and item props in the dungeon the same way tiles are made, as a pure function of the
depth and region, so a region regenerates the same inhabitants after eviction or a
revisit. A zone's theme maps to a roaming area, which selects the local monsters.

The inhabitants are drawn as placeholder voxel models from `critters`: a blocky
biped for monsters and a cube for props, both plain white and coloured per entity by
a tint uniform the mesh shader multiplies in.

## The turn loop and combat

`turns` drives the game clock. Nothing moves in real time: a player action advances
the world by one turn, and a key that only bumps a wall advances nothing. A step onto
a monster's tile is an attack instead of a move. After the player acts, each live
monster gains energy equal to its speed and acts while it holds at least the player's
speed, so a monster faster than the player takes more than one action per player turn
and a slower one takes fewer. Monster state (health, the energy counter, and the awake
flag) lives on the entity record, so it is ephemeral and resets when a region
regenerates.

Melee is a d20 roll plus the attacker's to-hit bonus against the target's ascending
armour class, then a damage die. A monster idles until it sights the player along a
clear tile line, then paths toward the player one axis at a time and strikes when
adjacent. A killed monster is recorded in the entities slain registry by its stable
identity (depth, region, room), so the deterministic placement leaves it out when the
region regenerates, and the kill persists for the session. Combat is reported through a
small log the HUD tails.

## The town hub and the descent

The surface hamlet of Brackenridge is a second kind of place the same renderer draws.
Where the dungeon is unbounded and generated per region, the town is one fixed region:
`town` carves the green, the timber buildings, and the chasm into region (0,0), and
every region beyond it is solid rock, so the hamlet is bounded. The tile world runs in
a town mode (`TileWorldInitTown`) that paints the whole region with the town theme and
reports the hamlet's landmarks. Because the voxel world reads tiles and theme through
the ordinary tile-world interface, it draws the town with no change.

The descent reuses the stair plumbing. The chasm is recorded as the town region's
down-stair and the spawn as its up-stair, so stepping onto the chasm and pressing the
stair key enters dungeon depth 0, and the climb out of depth 0 (an up-stair the origin
region now hosts) returns to the surface. Health, purse, and pack carry across every
transition; only a new game resets them, and a slain player revives back in town.

The townsfolk are peaceful entities (`townsfolk`) the combat path never selects. In
town the entity set holds them instead of monsters. Speaking to an adjacent townsperson
runs through the turn loop, which holds the player's purse: the trader buys the pack for
the summed item values, and the innkeeper restores health for coin. Loot is gathered by
stepping onto a prop in the dungeon, which moves it into the pack and records it in the
taken registry, the prop-pickup counterpart of the slain registry, so a gathered item
stays gone when its region regenerates.

## Save and load

Because the world is a pure function of its seed, a save does not store generated
tiles, chunks, or entity placements: all of that is recomputed on load. `saveload`
writes only what cannot be derived, the seed, whether the player is in town or at a
depth, the player's own state (position, combat stats, purse, and pack), and the two
registries of change, the monsters slain and the loot taken. Those registries are
keyed by depth, so a single pair of them records the state of every depth the player
has touched.

Loading reverses it: the registries are cleared and refilled from the file, the player
state is restored, and the world is rebuilt from the seed at the saved location, which
regenerates each depth exactly as it was left, the dead still dead and the loot still
gone. A file that is missing, not a save, or from an incompatible version is refused
without disturbing the game in progress.
