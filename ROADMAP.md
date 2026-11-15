# Roadmap

Planned work for Chasm in the Wood, grouped by the minor release that should
carry it. This is a plan, not a promise: items move between releases as the work
takes shape. The end goal is a third-person voxel dungeon-crawl roguelike (see
README.md for the setting).

Entries here cover the game. The voxel tooling (the voxelizer and the mesh
utilities) is not part of the game's release process.

## 0.1.0 - Voxel render foundation

- SDL3 window and OpenGL 3.3 core renderer. (done)
- MagicaVoxel `.vox` loading and greedy meshing. (done)
- Diorama camera and the FBX-to-voxel asset pipeline. (done)
- A ground grid to place the view in a scene. (done)

## 0.2.0 - Player and follow camera

- A player voxel model placed on the grid. (done)
- Grid movement with input. (done)
- Camera follows the player by moving the orbit rig's target. (done)

## 0.3.0 - Dungeon generation

- Procedural rooms and corridors on the grid. (done)
- Voxel tile kit for walls and floors. (done, placeholder colours)
- Chunked voxel world in a global coordinate space, frustum-culled. (done)
- Doors and stairs between levels.
- Chunk streaming and a room/portal graph, toward the continuous world.

## 0.4.0 - Entities and content

- Load the `content/*.txt` tables (monsters, items, species, classes).
- Spawn monsters and props as voxel models in the dungeon.

## 0.5.0 - Turn loop and combat

- Turn scheduling for the player and monsters.
- Basic melee combat and death.

## Unassigned

- Town hub at Brackenridge and the descent between town and dungeon.
- Audio: music and sound effects.
- Save and load.
- HUD and menus.
- Lighting and shadows beyond the single directional term.
- Scene chunking and level-of-detail for larger dungeons.

## Asset replacements

Purchased or otherwise human-made art and audio are preferred. Any AI-generated
placeholder must be listed here and replaced before the release that ships it.

- The reference character is CC0 human-made art.
- Dungeon tiles (floor and wall) are flat placeholder colours generated in code,
  not art. Replace with authored voxel tiles before release.
