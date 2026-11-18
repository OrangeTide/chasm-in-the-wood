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

The releases below drive toward 1.0 as a complete, winnable descent that feels like a
game, not just a working loop: a closed economy, loot worth finding, goals beyond the
one relic, people worth talking to, and authored art in place of placeholders. Each
still depends only on work already done. The deeper systems the content tables describe
(spells, skills, more biomes, and the sub-maps) arrive after 1.0; the slice takes the
breadth that makes the loop satisfying without any one system in full.

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

## 0.13.0 - Real-time play and presentation (released 2026-11-16)

A pivot and a polish pass on the finished spine: the turn loop becomes real-time,
the dungeon reads as an enclosed space, and the interface gains sound, a readable
font, and objective cues.

- Real-time movement replaces the turn loop. The player holds a continuous
  position and walks from the held keys relative to where the camera looks,
  sliding along walls one axis at a time, with the tile under the player derived
  for streaming, stairs, and generation. (done)
- Real-time combat. An awake monster chases and strikes on its own cooldown as it
  closes to melee, a faster one more often; the player swings on command at the
  nearest foe and gathers loot by walking over it. The d20 rolls stay. (done,
  supersedes the energy scheduler of 0.6.0)
- The dungeon reads as enclosed. Rock bordering carved space draws as a
  wall-height block so rooms sit in solid stone, and fragments fade toward the
  background dark with view distance. (done)
- Emissive voxel materials. A `.vox` colour index flagged `_emit` lights itself
  and thins the fog over it, so a torch or rune reads as a beacon. (done)
- One voxel scale for every free-standing model, the object voxel-unit (0.0625),
  so a model's size is its voxel count. Authored art does not fit that scale yet,
  so the world draws procedural placeholders built by formula and the old
  authored-art baking pipeline is removed. (done, see Asset replacements)
- The message log moves to its own transparent HUD overlay along the lower-left,
  leaving the status window to the live stats. (done)
- An objective compass in the upper-right points to the current goal along a small
  quest chain: find the chasm in town, descend to the bottom, take the Heart,
  climb back out. (done)
- Looping OGG Vorbis background music, one track per place, decoded once and
  streamed. Optional, so a headless or silent run is unaffected. (done)
- A proportional bitmap UI font with real lowercase, loadable at runtime from a
  CFN file so the face is swappable without a rebuild. (done)

Depends on the render stack (0.3.0), combat (0.6.0), the interface (0.4.0), and
the goal and quest target (0.10.0).

## 0.14.0 - A closed economy and trade (released 2026-11-17)

Coin earned below becomes something to spend, so the loop closes: descend for loot and
coin, return to town to re-equip and resupply. One trade window unifies selling, buying,
and barter the modern way.

- A trade window that stages two piles: items the player hands over from the pack, and
  items taken from the shop stock (shops.txt), with coin settling the difference. Selling
  is giving only, buying is taking only, and barter is both at once. The trader buys at a
  fraction of value and sells at full, the spread its margin. (done)
- Opened by speaking to the trader. It shows the shop stock and prices against the pack
  and the purse, with a running balance and a confirm. (done; the dialogue shop hook
  waits on the 0.18.0 dialogue system)
- Character backgrounds (backgrounds.txt) set starting coin, rolled from a dice
  expression and chosen at creation. (done; the skill leaning is recorded but inert until
  skills arrive post-1.0)

Depends on the town economy (0.7.0), items (0.9.0), character creation (0.11.0), and the
interface (0.4.0).

## 0.15.0 - Front end and endings (released 2026-11-17)

The loop gets a frame. A title screen starts a new game or continues a saved one, a
victory screen marks the objective returned, and a death screen offers the respawn the
game already performs. All of it is drawn with the existing window toolkit.

- A title screen: new game, continue, quit. (done)
- A victory ending when the objective reaches town. (done)
- A death screen surfacing the respawn choice. (done)

Depends on the interface (0.4.0), save and load (0.8.0), and the goal (0.10.0).

## 0.16.0 - Item depth (released 2026-11-17)

The item table's unused kinds and flags come into play, so what you find and carry
matters more than one weapon and one potion.

- Light sources (the light kind): a carried torch or lantern pushes back the dark and the
  fog with a burn time, so descending unlit has a cost. (done)
- Keys and locks (the key kind): locked chests that a key opens, gating better loot.
  (done; locked doors are left to the generator's later work, chests carry the mechanic)
- Treasure (the treasure kind): sale-only valuables, so some loot is pure reward. (done)
- Weapon variety from the flags: two-handed weapons that bar a shield. (done; ranged
  weapons and their line of fire come post-1.0)
- More consumables than the healing potion: scrolls and other single-use items the pack
  holds, on a data-driven use-effect system. (done)
- Depth-weighted loot: what drops, and what the shop stocks, shifts with depth. (done)

Depends on items and combat (0.6.0, 0.9.0) and the enclosed-dark presentation (0.13.0,
so light has something to push back).

## 0.17.0 - Packaging and hardening (released 2026-11-17)

The game becomes something to ship and to trust. It installs as a desktop application,
its user-visible text moves out of the code into a loadable string table, and an opt-in
checks build hardens the engine against latent faults.

- Desktop install and a macOS app bundle, with the application icon. (done)
- User-visible text moved into a loadable string table, the HUD stat labels among it, with
  the loadable file formats documented. (done)
- An opt-in checks build: FPC's range, overflow, I/O, stack, and method-call checks, plus
  a Valgrind target for the memory checks the compiler cannot do itself. (done; it caught
  and fixed a placement non-determinism bug)

Depends on the interface (0.4.0) and the build system.

## 0.18.0 - Quests and dialogue

Goals beyond the one relic, given by the people of Brackenridge and tracked in a real
quest log, with townsfolk worth talking to.

- The quest system reads quests.txt: flag-gated stages, an active and complete state, and
  a current objective, replacing the hardcoded compass chain.
- A quest log panel, and the HUD objective and compass driven by the active quest.
- Branching townsfolk dialogue from dialogs.txt: nodes and responses, rumors that hint at
  goals and seed quests, and the shop hook that opens the trader.
- A few starter quests: clear a named foe, retrieve an item from a depth, and the relic
  descent tracked as a quest rather than a special case.

Depends on the town (0.7.0), the goal (0.10.0), and the interface (0.4.0).

## 0.19.0 - The art pass

Procedural placeholders give way to authored or purpose-built generative art at the
settled voxel scale, so the world looks like a place rather than primitives. The source
plan and licence rules are in Asset replacements.

- Tiles per environment (dungeon, forest, town), with a door-leaf and richer ground
  variety than one floor each.
- The player, monsters, creatures, and loot props as models, in place of the ball, plate,
  arch, and steps.
- Each art source's licence confirmed before the release that distributes it.

Depends on the fixed voxel scale (0.13.0), and is the last step before 1.0.

## 1.0.0 - First complete descent

The slice sealed into a complete game: create a character, descend a finite dungeon of
rising danger, spend and resupply between runs, follow quests toward the depths, defeat
the guardian, and carry the relic back to Brackenridge to win, with the title, victory,
and death screens framing it and authored art throughout. A balance pass across the whole
descent, and every art and audio source's licence confirmed for distribution.

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

- Deeper quest chains and dialogue trees built on the pre-1.0 system, with reputation and
  branching outcomes.
- The sub-maps in world.txt (caves, catacombs) with their return portals, more biomes,
  deeper layers, and set-piece rooms.

Presentation and performance:

- Lighting and shadows beyond the single directional term, with torches as light sources
  (emissive materials self-light today but cast no light).
- Sound effects, and music beyond one looping track per place.
- Scene chunking and level-of-detail for larger dungeons.

Packaging and distribution:

- Resolve game data from an install location. Desktop install and the macOS `.app` bundle
  ship in 0.17.0, but the installed binary still reads its `content/` data relative to the
  working directory, so a menu-launched install needs the data found beside the binary or
  at a prefix path first.

## Asset replacements

Purchased or human-made art and audio are preferred, and art from purpose-built
generative tools (for example VoxelAI or Hyper3D) counts as production art, subject to
the usual licence confirmation. Art generated by Claude is only ever a placeholder: it
must be listed here and replaced before the release that ships it.

The world currently draws procedural placeholders, not art. Every free-standing
model and tile is generated by formula at one voxel scale (see 0.13.0): a ball for
the player, monsters, and loot, a plate for walls and floors, an arch for doors,
and steps for stairs. The earlier authored-art pipeline, which baked MagicaVoxel
tiles and props and loaded a reference character, was removed, so the build
depends on no reference packs and makes the binary from source alone.

Before 1.0 these placeholders give way to purchased, human-made, or purpose-built
generative art at the same voxel scale:

- Tiles per environment: the dungeon (brick), the forest (grass and trees), and
  the town (packed earth and stone cottages), with a door-leaf tile and richer
  ground variety than one floor per environment.
- Loot props (a chest, a torch, skulls), and the player, monsters, and creatures.
- Confirm each source's licence before shipping a release that distributes its art.

The UI font is the exception already in place: `content/fonts/ui.cfn` is baked
bitmap data, not a redistributed font file, so it ships as is.
