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
src/render/tilekit     baked meshes for the authored dungeon tiles
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

The geometry is a rendering of the tile map. Gameplay could run with no renderer at
all, and the renderer could draw a different tile source without changing gameplay.
This separation is standard roguelike practice and it keeps each side simple.

The dungeon is drawn from authored voxel tiles (see [Dungeon tiles](#dungeon-tiles)
below). An earlier path rasterized tiles into a streaming grid of voxel chunks
(`voxchunk`, `world`); that subsystem still exists and is unit-tested, but the live
render path now draws one baked tile mesh per visible cell.

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
            tiles around the player, each drawn as its kind's baked mesh:
               tile map -> tile kind -> baked tile mesh at the tile origin
                       |
            camera -> view and projection
                       |
            frustum cull -> draw visible tiles + player + entities
```

Generation runs once. Reading, culling, and drawing run every frame. The tile map is
the authority; reading a tile generates its region on demand, so the drawn window
streams the world as the player moves.

## Tiles and environments

The world has three looks, each its own authored tile set: the dungeon (brick), the
forest (grass and trees), and the town (packed earth and stone cottages). A tile kind
in an environment (floor, wall, stairs) is one authored MagicaVoxel model, the same in
every cell of that kind.

The art is high-resolution and would be ruinous to rasterize into a dense voxel grid
per chunk, which meshes millions of hidden faces between neighbouring cells. Instead
`tilekit` bakes each environment-and-kind once: it loads the model, rotates it from the
file's z-up into the engine's y-up, and meshes it to a single GPU mesh. The frame loop
draws a cell by drawing its mesh at the cell origin, the same way the player and
monsters are drawn. The cost of the detailed art is a handful of resident meshes and
one draw per visible cell, a few hundred in the diorama's window.

The sets come from different packs at different native resolutions (the dungeon brick is
50 voxels across, the forest grass 16), so each mesh is scaled by its own footprint to
fill exactly one world cell. That lets the detailed dungeon and the chunky forest share
one grid. The environment of a cell is a property of where it is: the dungeon below, or
on the surface the hamlet (region 0,0 of the town) versus the forest in every region
around it.

The models are extracted from human-made voxel packs by the `voxpack` tool, which reads
a pack's scene graph to pull a named model out into a lone `.vox`. The bake runs at
build time, like the character model; the packs live under `REF` (local, untracked) and
the baked tiles under `content/tiles` are build output.

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
`town` carves the ground, the buildings, and the chasm into region (0,0), with gates
through its wall. Every region around it is walkable forest, generated per tile as a
deterministic scatter of trees over grass, so the player can leave the hamlet through a
gate and wander the woods, and neighbouring forest regions join seamlessly. The tile world runs in
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

## Items and equipment

The pack holds items by content index. Three of them can be worn, in `player`: a weapon,
a suit of armour, and a shield. The worn gear is the only thing that sets the combat
stats the turn loop reads. `PlayerRecalc` derives them from the base and whatever is
worn, so armour sets the armour class, a shield adds to it, and a weapon sets the damage
die and a small to-hit bonus; combat never looks at the gear, only at the derived Ac,
Atk, and DmgDie. Equipping moves an item from the pack to its slot and returns the
displaced one, so the pack size is steady; a healing potion is quaffed straight from the
pack.

The panels are the live view and the editing surface. `gameui` offers a plain
integer-and-string API, so the game pushes the pack, the worn gear, and the derived
stats in without the toolkit ever seeing a content type. Each inventory tile carries the
content index as a drag payload. When the player drags an item between the pack and the
equipment doll, the desktop fires a drag-end hook; `gameui` reads the new layout back as
a list of payloads and hands it to the game, which rebuilds the pack and the worn slots
and recomputes the stats. The doll's slot categories keep a weapon, armour, and a shield
each to their own slot.

## Save and load

Because the world is a pure function of its seed, a save does not store generated
tiles, chunks, or entity placements: all of that is recomputed on load. `saveload`
writes only what cannot be derived, the seed, whether the player is in town or at a
depth, the player's own state (position, combat stats, purse, pack, and worn gear), and the two
registries of change, the monsters slain and the loot taken. Those registries are
keyed by depth, so a single pair of them records the state of every depth the player
has touched.

Loading reverses it: the registries are cleared and refilled from the file, the player
state is restored, and the world is rebuilt from the seed at the saved location, which
regenerates each depth exactly as it was left, the dead still dead and the loot still
gone. A file that is missing, not a save, or from an incompatible version is refused
without disturbing the game in progress.
