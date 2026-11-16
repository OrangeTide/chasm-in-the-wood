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

## 0.6.0 - Turn loop and combat

Depends on entities (0.5.0), and surfaces health, turns, and death through the HUD
(0.4.0).

- Turn scheduling for the player and monsters.
- Basic melee combat and death.

## 0.7.0 - Town hub and descent

Depends on entities for the townsfolk and on the interface for dialogue and trade.

- Town hub at Brackenridge and the descent between town and dungeon.

## 0.8.0 - Save and load

Depends on a settled world and entity state (through 0.6.0), so there is a complete
game state to serialize and restore.

- Save and load the world, the depths visited, and entity state.

## Unassigned

Cross-cutting work that depends only on finished systems and can land in any release
that needs it, grouped by area.

Rendering and performance:

- Lighting and shadows beyond the single directional term.
- Scene chunking and level-of-detail for larger dungeons.

Audio:

- Music and sound effects.

## Asset replacements

Purchased or otherwise human-made art and audio are preferred. Any AI-generated
placeholder must be listed here and replaced before the release that ships it.

- The reference character is CC0 human-made art.
- Dungeon tiles (floor and wall) are flat placeholder colours generated in code,
  not art. Replace with authored voxel tiles before release.
