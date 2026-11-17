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
src/render/tilekit     generated placeholder tile meshes (floor, wall, door, stairs)
src/render/prims       procedural placeholder voxel shapes (ball, plate, arch, steps)
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
src/game/turns         real-time update: movement collision, monster AI, melee, death
src/game/townsfolk     the people of Brackenridge and the builder that places them
src/game/saveload      serialize and restore the game state to a file
src/game/audio         OGG Vorbis background music, decode-once and loop
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

The dungeon is drawn from voxel tiles (see [Tiles and environments](#tiles-and-environments)
below). An earlier path rasterized tiles into a streaming grid of voxel chunks
(`voxchunk`, `world`); that subsystem still exists and is unit-tested, but the live
render path now draws one tile mesh per visible cell. A rock tile that borders
carved space is drawn as a wall-height block, so rooms and corridors sit in solid
stone rather than a void; rock buried behind that face is skipped. Underground the
mesh shader fades fragments toward the background dark by view-space distance, so the
view closes in rather than hanging as a lit island.

A voxel colour index can be marked emissive through the `.vox` MATL material (type
`_emit`, strength in 0..1). The reader keeps the emission per palette entry, the
mesher stamps it on each vertex, and the shader lets an emissive voxel light itself
and thins the fog over it, so a torch or a rune glows and carries through the dark
instead of being swallowed by it. Ordinary voxels are unaffected.

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

The authored tiles are being replaced, so the world draws procedural placeholders in
the meantime, generated by formula in `prims` rather than built by hand: a floor is a
plate one tile tall, a wall a taller plate, a door an arch, and stairs a short flight of
steps. `tilekit` builds each once, rotates it from the file's z-up into the engine's
y-up, and meshes it to a single GPU mesh. The frame loop draws a cell by drawing its
mesh at the cell origin, the same way the player and monsters are drawn, a few hundred
draws in the diorama's window. Every environment shares the one set for now.

The generated footprint is 16 voxels, so a tile scales to fill one world cell by the
object voxel-unit (see [Scale](#scale)); tiles and free-standing models sit on the same
scale. The environment of a cell is still a property of where it is: the dungeon below,
or on the surface the hamlet (region 0,0 of the town) versus the forest in every region
around it, ready for distinct tile sets to return per environment.

## Scale

Every free-standing voxel model, the player, monsters, and loot, is placed at one fixed
world size per voxel, the object voxel-unit (`VU`, 0.0625 world units). A model's
physical size is therefore its voxel count: a thing is bigger because it is built from
more voxels, not because it is scaled up. Sixteen voxels span one tile, so a tile's
footprint fill equals `VU` and the tiles share the scale. The placeholders size by voxel
count too: the player ball is a fixed diameter, a monster's ball grows with its bulk
class, and loot is a small ball.

## The frame loop

`chasm.pas` holds the loop. Each frame it reads input, measures the elapsed time,
moves the player from the held keys relative to where the camera looks, advances the
world (`turns`) by that time, gathers any loot in reach, streams the world for the
player's new neighbourhood, eases the camera target toward the player, then clears,
binds the shader once, draws the visible cells and the entities, draws the interface
overlay on top, and swaps buffers. Held keys are tracked from key-up and key-down
events; the elapsed time is clamped so a stall cannot tunnel anyone through a wall. A
screenshot mode draws one frame to a PPM and exits, which doubles as a headless render
check.

Movement is camera-relative: the player's forward is the direction the camera looks on
the ground plane, so pressing forward walks into the screen whatever the camera's yaw.
The player holds a continuous world position (tile units); the tile under them is
derived for streaming, stairs, and generation. Each move is taken one axis at a time so
a wall stops one axis without stopping the other, which slides the body along walls, and
the tile a body ends in is never a wall.

## The interface layer

A retained-mode widget toolkit draws floating windows over the diorama: a status
panel, inventory, the character sheet, and menus. It is backend-agnostic, drawing
through an abstract canvas that the OpenGL layer renders as a 2D overlay of coloured
quads; the canvas colours carry alpha, so a panel can be drawn translucent. The
message log rides in its own transparent overlay along the lower-left, bright text with
a drop shadow and no window chrome, and it never intercepts the mouse, so the status
window carries only the live stats. The main program drives the toolkit through a small
wrapper and never sees its own types. See [Interface and HUD](gui.md).

## Entities and content

The content tables under `content/` are loaded once into plain records by `content`:
monsters, items, species, and classes. On top of them, `entities` places monsters
and item props in the dungeon the same way tiles are made, as a pure function of the
depth and region, so a region regenerates the same inhabitants after eviction or a
revisit. A zone's theme maps to a roaming area, which selects the local monsters.

The inhabitants are drawn as procedural placeholder balls from `prims`, sized by the
object voxel-unit: a monster's ball grows with its bulk class and loot is a small ball.
They are plain white and coloured per entity by a tint uniform the mesh shader
multiplies in (the objective glows in its own colour).

## Music

`audio` loops one OGG Vorbis track per place, chosen by the main loop (town or dungeon).
The vendored public-domain stb_vorbis, the one C object in the build, decodes a whole
track once into interleaved 16-bit samples; those are copied into a Pascal buffer and
streamed through one SDL audio stream, topped up each frame from the buffer and wrapped
at the end, so a loop-authored track plays seamlessly without an audio-thread callback.
Audio is optional: if the device or a track will not open the unit goes quiet and every
call is a no-op, so a headless or silent run is unaffected. No tracks ship with the
source; they are dropped into `content/music/` as `town.ogg` and `dungeon.ogg`.

## Real-time combat

`turns` advances the world every frame by the elapsed time. A monster idles until it
sights the player along a clear tile line, then chases across open floor, each axis
taken on its own so it slides along walls, and stops a touch short of melee range. In
range it strikes on its own attack cooldown, so a faster monster both moves and swings
more often. Monster state (health, the attack cooldown, and the awake flag) lives on the
entity record, so it is ephemeral and resets when a region regenerates.

The player swings on command, striking the nearest monster within reach if its own swing
cooldown has elapsed. Melee is a d20 roll plus the attacker's to-hit bonus against the
target's ascending armour class, then a damage die. Loot is gathered by walking within
reach of it. A killed monster is recorded in the entities slain registry by its stable
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

The descent is finite: the deepest depth (`DUNGEON_BOTTOM`) hosts no down-stairs, so it
is the bottom of the chasm. Which monster fills a room comes from the authored encounter
tables (`encounters.txt`): each area points at a weighted table, and a room's hash makes
a deterministic weighted pick, with the monster's own area set as a fallback. Danger
grows with depth, through `entities`: deeper down a second draw can supplant the first
with a tougher foe, deeper monsters are hardier and strike harder, and rooms that would
be empty up top crowd with monsters, more of them the deeper the level. The bottom's
origin region carries the objective, a single relic placed in its far room with a
reserved identity, and a guardian beside it, a boss far tougher than the rank and file
that must be beaten to carry the relic out. The relic is taken like loot and the guardian
is recorded slain, each by its reserved identity, so neither returns; the relic never
spawns as random loot and is never sold. Carrying it up to Brackenridge wins, which the
game surfaces in the log for now. The victory screen that frames the win arrives later.

The townsfolk are peaceful entities (`townsfolk`) the combat path never selects. In
town the entity set holds them instead of monsters. Speaking to an adjacent townsperson
runs through `turns`, which holds the player's purse: the trader buys the pack for
the summed item values, and the innkeeper restores health for coin. Loot is gathered by
walking within reach of a prop in the dungeon, which moves it into the pack and records
it in the taken registry, the prop-pickup counterpart of the slain registry, so a gathered item
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

## Characters and progression

A new game forges a character in `player`. The player chooses a species and a class,
both read from the content tables: the species shifts the six ability scores from an
average base and a human-style species sharpens the class's prime ability, while the
class sets the hit die, from which the hit points come (the die plus the constitution
modifier), and the opening kit, which is worn. The derived combat stats fold it all in,
so armour and dexterity set the armour class, strength and level set the to-hit, and a
weapon sets the damage die. Combat reads only the derived numbers. Slain monsters grant
their experience, and banked experience raises levels, each lifting the hit-point maximum
and the to-hit. The creation picker, the character sheet, and the save all follow the
chosen character.

The interface for creation reuses the window toolkit: a creation window offers every
species and one class per quick-start archetype through popups, built from the content
names, and on Begin it hands the chosen content indices and name back to the game, which
forges the character and sets it on the town spawn. The default character stands in until
then, so the game is playable the moment it opens.

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
