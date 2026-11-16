# Roadmap

Planned work for Chasm in the Wood, grouped by the minor release that should
carry it. This is a plan, not a promise: items move between releases as the work
takes shape. The end goal is a third-person voxel dungeon-crawl roguelike (see
README.md for the setting).

Entries here cover the game. The voxel tooling (the voxelizer and the mesh
utilities) is not part of the game's release process.

## 0.1.0 - Voxel render foundation (released 2026-11-15)

- SDL3 window and OpenGL 3.3 core renderer. (done)
- MagicaVoxel `.vox` loading and greedy meshing. (done)
- Diorama camera and the FBX-to-voxel asset pipeline. (done)
- A ground grid to place the view in a scene. (done)

## 0.2.0 - Player and follow camera (released 2026-11-15)

- A player voxel model placed on the grid. (done)
- Grid movement with input. (done)
- Camera follows the player by moving the orbit rig's target. (done)

## 0.3.0 - Dungeon generation (released 2026-11-15)

- Procedural rooms and corridors on the grid. (done)
- Voxel tile kit for walls and floors. (done, placeholder colours)
- Chunked voxel world in a global coordinate space, frustum-culled. (done)
- Chunk streaming and a room/portal graph, toward the continuous world. (done)
- Unbounded tile world: regions generated on demand, seamless across region
  boundaries. (done)
- Evict far tile regions (safe because generation is deterministic). (done, LRU)
- Doors at room entrances, and stairs between depths. (done)
- Scatter stairs beyond the origin region. (done)
- Vary regions by zone and theme through a higher generation layer. (done)
- Use the portal structure to stitch separate zones into one seamless space. (done)

The releases below are ordered so each one depends only on work already done, and
each groups features that touch the same code area. The interface layer comes first
because it stands on the finished renderer and gives the later gameplay systems a
place to show their state. The gameplay spine follows, dungeon to entities to the
turn loop, then the places and systems that build on it.

## 0.4.0 - Interface and HUD (released 2026-11-16)

A retained-mode GUI layer over the renderer. Depends only on the render stack, and
is the surface the entity, combat, and town systems below draw into.

- Retained-mode widget toolkit: System 7 style windows floating over the live
  diorama, drawn through a GL overlay canvas. (done)
- A live info HUD: depth, zone theme, seed, player tile, resident region and chunk
  counts. (done)
- Panels and menus for the later systems: inventory, character, and options.
  (done, placeholder contents until the entity and item systems land)

## 0.5.0 - Entities and content (released 2026-11-16)

The start of the gameplay spine. Depends on the dungeon (0.3.0); nothing here needs
the interface, though it reads better through the HUD.

- Load the `content/*.txt` tables (monsters, items, species, classes). (done)
- Spawn monsters and props as voxel models in the dungeon. (done, placeholder
  procedural creatures until authored art lands)

## 0.6.0 - Turn loop and combat (released 2026-11-16)

Depends on entities (0.5.0), and surfaces health, turns, and death through the HUD
(0.4.0).

- Turn scheduling for the player and monsters. (done, energy by speed)
- Basic melee combat and death. (done, player respawns at depth 0)

## 0.7.0 - Town hub and descent (released 2026-11-16)

Depends on entities for the townsfolk and on the interface for dialogue and trade.

- Town hub at Brackenridge and the descent between town and dungeon. (done)
- Townsfolk with flavor dialogue, and a basic coin economy: loot picked up below sells
  to the trader, and the innkeeper trades coin for rest. (done)

## 0.8.0 - Save and load (released 2026-11-16)

Depends on a settled world and entity state (through 0.6.0), so there is a complete
game state to serialize and restore.

- Save and load the world, the depths visited, and entity state. (done, a single slot
  keyed only on the seed, the location, the player, and the change registries, since the
  world regenerates from the seed)

## 0.9.0 - Items and inventory depth (released 2026-11-16)

Depends on entities and content (0.5.0) for the item tables, the turn loop (0.6.0) for
the combat stats the gear feeds, and the interface (0.4.0) for the panels it fills.

- Worn gear drives combat: a weapon, a suit of armour, and a shield, each read from the
  content item table, set the derived damage die, armour class, and to-hit. (done)
- Equip and unequip by dragging in the inventory and equipment panels, which now mirror
  the live pack, worn gear, and derived stats instead of placeholders. (done)
- Consumable healing potions, quaffed from the pack. (done)
- The worn gear is saved and restored (save format version 2). (done)

The releases below drive toward 1.0 as a vertical slice: a complete, winnable descent
with the least of each system that makes it whole, rather than any one system in full.
Each still depends only on work already done. The systems the content tables already
describe (spells, skills, quests, branching dialogue) arrive in full after 1.0; the
slice takes only what the loop needs.

## 0.10.0 - A bottom and a goal (released 2026-11-16)

The descent gains an end and a reason. The chasm bottoms out at a deepest level that
holds one objective, the thing worth the descent, and the danger grows with depth so
each layer is deadlier than the last. Carrying the objective back to Brackenridge is the
win the game has lacked.

- A finite dungeon: a deepest depth with no stairs down past it. (done)
- Difficulty that scales with depth, in monster strength and number. (done)
- An objective on the deepest level, taken like loot and carried out. (done)
- A win state when the objective reaches town, surfaced in the log at first. (done)

Depends on dungeon generation (0.3.0), combat (0.6.0), and the town descent (0.7.0).

## 0.11.0 - Character creation and progression (released 2026-11-16)

A played character instead of a fixed vagrant. At a new game the player chooses a species
and a class from the authored tables, which set the starting stats, the hit points, and
the opening kit. Slain monsters grant experience, and levels raise health and the to-hit,
so the descent has growth. The character sheet shows the real identity and numbers.

- Species and class selection at a new game, from species.txt and classes.txt, with the
  pregen defaults in newgame.txt as a quick start. (done, a creation window offers every
  species and one class per quick-start archetype)
- Starting stats, hit points, and kit derived from the choice. (done)
- Experience from a monster's XP value on a kill, and leveling. (done)
- The character sheet and the save reflect the chosen character and its level. (done)

Depends on items and combat (0.6.0, 0.9.0) and the interface (0.4.0).

## 0.12.0 - Encounters and a guardian (released 2026-11-16)

Each layer draws its own foes, and a guardian stands between the player and the
objective. The authored encounter tables drive spawning by area and depth, in place of
the flat selection, and the deepest level holds a boss that must be beaten to take the
objective.

- Weighted encounter tables (encounters.txt) wired by area and depth. (done)
- A guardian on the deepest level, tougher than the rank and file. (done)
- A pass on the danger curve from the forest edge to the bottom. (done, deeper levels
  tilt the weighted pick toward tougher foes)

Depends on the finite descent (0.10.0) and progression (0.11.0).

## 0.13.0 - Front end and endings

The loop gets a frame. A title screen starts a new game or continues a saved one, a
victory screen marks the objective returned, and a death screen offers the respawn the
game already performs. All of it is drawn with the existing window toolkit.

- A title screen: new game, continue, quit.
- A victory ending when the objective reaches town.
- A death screen surfacing the respawn choice.

Depends on the interface (0.4.0), save and load (0.8.0), and the goal (0.10.0).

## 1.0.0 - First complete descent

The slice sealed into a complete game: create a character, descend a finite dungeon of
rising danger, defeat the guardian, carry the objective back to Brackenridge to win, with
the title, victory, and death screens framing it and the authored art throughout. A
balance pass across the whole descent, and the reference-pack licences confirmed for
distribution.

Depends on everything above.

## After 1.0

Point releases that deepen each system once the complete loop ships, grouped by area.
They move into numbered releases as the work is taken up.

Character and combat:

- The full species and class features: darkvision, prime bonuses, class kits and tracks.
- Spells and skills in play, from spells.txt and skills.txt, with a magic pool and a
  per-encounter skill budget.
- Ranged and thrown attacks (the ranged item flag), with line of fire.

World and story:

- Quests with flag-gated stages (quests.txt) and branching dialogue with shops
  (dialogs.txt), given by the townsfolk.
- More biomes, deeper layers, and set-piece rooms.

Presentation and performance:

- Lighting and shadows beyond the single directional term, with torches as light sources.
- Music and sound effects.
- Scene chunking and level-of-detail for larger dungeons.

## Asset replacements

Purchased or otherwise human-made art and audio are preferred. Any AI-generated
placeholder must be listed here and replaced before the release that ships it.

- The reference character is CC0 human-made art.
- Tiles are authored voxel art, extracted from human-made MagicaVoxel packs and baked at
  build time, one set per environment: the dungeon (brick), the forest (grass and
  trees), and the town (packed earth and stone cottages). The flat placeholder colours
  are gone, and loot props are authored models too (a chest, a torch, skulls), baked
  from the dungeon pack. Still open: a door-leaf tile (doors draw the floor for now),
  richer ground variety (one floor tile per environment today), and authored trees.
  Confirm each pack's licence before shipping a release that distributes the baked tiles
  and props.
