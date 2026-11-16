# Changelog

All notable changes to Chasm in the Wood are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow semantic versioning. Each minor release gets a dated section and an
annotated git tag whose message is that release's changes.

## [Unreleased]

### Added
- Content tables loaded into records: monsters, items, species, and classes are
  parsed from `content/*.txt`, tolerant of unknown trailing tags and a quoted display
  name.
- Monsters and item props placed in the dungeon as a pure function of the depth and
  region, so a region regenerates the same inhabitants after eviction or a revisit. A
  zone's theme maps to a roaming area that selects the local monsters; the HUD reports
  the live foe and loot counts.
- Placeholder procedural voxel models for the inhabitants: a blocky biped for
  monsters, scaled by the creature's size, and a cube for props, both coloured per
  entity by a new tint uniform in the mesh shader. The entities are static until the
  turn loop lands.

## [0.4.0] - 2026-11-16

### Added
- A retained-mode GUI toolkit: System 7 style windows floating over the live diorama,
  with a backend-agnostic core, the System 7 theme, and an OpenGL canvas that draws
  every primitive, text included, as coloured screen-space quads in one blended pass.
  A draggable status window shows live depth, zone, seed, player tile, and resident
  region and chunk counts. Mouse input is routed to the windows; the keyboard still
  drives the player.
- Interface panels over the diorama: a tabbed multi-page inventory, an equipment
  paperdoll with slots that accept matching item categories, a character sheet with
  a scrolling skill list, and an options window of toggles. Contents are placeholders
  until the entity and item systems land. Each panel opens and closes from a toggle
  key (I, C, O) and from a button on the status window.

### Changed
- Adopted one idiomatic Object Pascal style across the source: PascalCase built-in
  type names and record and class fields, matching the GUI units. Renamed the main
  program from `chasm.lpr` to `chasm.pas`, since the project is plain FPC with a
  Makefile rather than Lazarus.

## [0.3.0] - 2026-11-15

### Added
- Seeded xorshift RNG so a seed reproduces a level.
- Logical tile map (rock, floor, wall, door) kept separate from the voxel
  geometry, driving movement and collision.
- Hierarchical BSP dungeon generator: rooms, connecting corridors, and a wall
  ring.
- Chunked voxel world in one global coordinate space, with chunks held in a hash
  map, rasterized from the tile map, and greedy-meshed per chunk.
- Frustum culling that draws only the chunks the camera can see.
- Chunk streaming: a load-and-evict window keeps only the player's
  neighbourhood resident, so a large level costs its local area.
- Room and portal graph recorded by generation, used for connectivity and reserved
  for future portal occlusion and zone linking.
- Engine documentation under `docs/`, one article per subsystem.
- A swappable mesh backend so chunk streaming runs without an OpenGL context, and
  `make test` unit tests for the RNG, generation, and the streaming load and evict
  cycle.
- An unbounded tile world: fixed-size regions generated on demand from a seed, with
  deterministic edge crossings so neighbouring regions join seamlessly. The level
  has no fixed bounds; the player can walk any direction and new dungeon generates.
- Least-recently-used eviction of tile regions, so resident regions stay under a cap
  and memory is bounded however far the player walks; deterministic generation makes
  an evicted region regenerate identically.
- Doors at room entrances, walkable and rendered as a framed wood threshold.
- Stacked dungeon depths: each depth is a distinct seamless world seeded by its
  depth, connected by stairs down and up. Return takes the stairs under the player,
  rebuilding the world at the next depth.
- Zones and themes: a layer above regions assigns each square block of regions a
  theme from the world seed, varying the tile colours, wall height, and room size.
  A zone keeps its theme, and folding the depth into the seed changes the theme map
  from one depth to the next, so areas and depths read as distinct places.
- Stairs scattered across the world instead of only at the origin: a region hosts a
  down-stair by a hash of the seed, depth, and region, and the matching up-stair sits
  in the same region one depth down, so every descent has an ascent back and the
  player arrives standing on a stair wherever they went down.
- A stitched world portal graph: the per-region room graphs are joined at the seam
  crossings into one connected graph across regions and zones, traversed by a
  breadth-first search over the on-demand world. The engine uses it to confirm that
  separate zones form one seamless space, reporting the portal distance from the
  spawn room to a neighbouring zone at startup.

### Changed
- Split the renderer into a shared mesh shader and per-object GPU meshes, so the
  world chunks, the player, and later props draw through one program.
- The voxel world streams chunks from tiles instead of building the whole level up
  front, now reading from the unbounded tile world rather than a single bounded map.
- The generator exposes reusable carving primitives shared by the bounded level and
  per-region generation.

## [0.2.0] - 2026-11-15

### Added
- Player voxel model that moves a tile at a time with WASD or the arrow keys,
  blocked by walls.
- Follow camera that eases its target toward the player each frame, with Q/E to
  orbit and `-`/`=` to zoom.

## [0.1.0] - 2026-11-15

### Added
- SDL3 window with an OpenGL 3.3 core renderer, through hand-rolled minimal
  bindings loaded at runtime.
- MagicaVoxel `.vox` reader and writer.
- Greedy voxel mesher that merges same-colour faces into large quads.
- Diorama camera built as an orbit rig around a target point.
- `voxelize` tool: surface-voxelizes an OBJ mesh into a `.vox`, taking colours
  from the material's diffuse term.
- Asset pipeline that bakes the reference CC0 modular character (FBX) into a
  voxel model through assimp and the voxelizer.
- Modular Makefile split into `mk/*.mk` fragments by concern.

### Removed
- Stale tool stubs from the earlier software renderer that no longer compiled.
