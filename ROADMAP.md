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

## 0.18.0 - Quests and dialogue (released 2026-11-17)

Goals beyond the one relic, given by the people of Brackenridge and tracked in a real
quest log, with townsfolk worth talking to.

- The quest system reads quests.txt: flag-gated stages, an active and complete state, and
  a current objective, replacing the hardcoded compass chain. (done)
- A quest log panel, and the HUD objective and compass driven by the active quest. (done)
- Branching townsfolk dialogue from dialogs.txt: nodes and responses, rumors that hint at
  goals and seed quests, and the shop hook that opens the trader. (done)
- A few starter quests: clear a named foe, retrieve an item from a depth, and the relic
  descent tracked as a quest rather than a special case. (done; the relic descent is now
  the three-shard quest, with the demon lord as the named foe and the shard shrines as the
  retrieval points)
- Locked doors in generation, opened by the same key item that unlocks chests (0.16.0),
  so a quest or a depth can gate a route behind a found key. (done)

Recruit (hiring a follower) and identify (an unidentified-item system) are stubbed, left
for a later release. Depends on the town (0.7.0), the goal (0.10.0), the key mechanic
(0.16.0), and the interface (0.4.0).

## 0.19.0 - Art and audio pass (released 2026-11-19)

Procedural placeholders give way to authored or purpose-built generative art at the
settled voxel scale, and the core actions gain sound, so the world looks and sounds like a
place rather than primitives. The source plan and licence rules are in Asset replacements.

- Tiles per environment (dungeon, forest, town), with a door-leaf and richer ground
  variety than one floor each. (done: all three environments have authored tiles)
- The player, monsters, creatures, and loot props as models, in place of the ball, plate,
  arch, and steps. (player done; all 26 monsters modeled; weapons, shields, and the common
  consumable and treasure loot modeled; armour, a few misc items, and the relic still on the
  placeholder; see Asset replacements)
- Core sound effects for the actions that carry the loop: a swing and a hit, taking
  damage, picking up loot, using stairs, and the menu clicks. (done: the six one-shots are
  in, from the Kenney CC0 audio packs; see Asset replacements)
- Each art and audio source's licence confirmed before the release that distributes it.

Note on voxelization quality: a mesh's texture, sampled before voxelization, makes a large
difference to the output. The voxelizer now samples an OBJ material's `map_Kd` image per
voxel (textured kits came out flat grey without it), and the character/tile conversions stage
each source's base-colour textures so they are sampled. A GLB that bakes its texture *inside*
the file (an embedded image rather than an external one) does not resolve through the OBJ
pipeline on its own, which once left such models flat grey. The manifest's `tex=` closes that
when the kit also ships the base-colour image as an external file: it stages that image beside
the source and points the material at it (the Fantasy Races and Bestiary creatures keep their
colours this way). The remaining gap is a GLB whose texture is *only* embedded, with no external
file to fall back on; there the image bytes would have to be unpacked from the GLB itself. If a
converted model looks washed out or single-toned, check whether its `tex=` is set and staged.

Note on model size: a model's in-game size is its voxel count at the one object voxel-unit,
so size comes from the kit scale. A kit whose own models are not to a common scale (a stylized
creature pack) leaves some models tiny and others huge under one scale. The converter manifest
carries a per-asset `scale=f` factor for that case, used to size each enemy-kit creature to its
combat size class beside the hero. The default remains one scale per kit; the factor only tunes
an outlier pack. A larger factor also samples the mesh more finely, so it adds detail as it grows.

Depends on the fixed voxel scale (0.13.0) and the audio playback path (0.13.0).

## 0.20.0 - Balance and tuning

A pass across the whole descent so the difficulty, loot, and economy curves feel
deliberate rather than placeholder. This tunes the content tables, not new systems, and
is the last step before 1.0.

- The danger curve from the forest edge to the bottom: monster strength, numbers, and the
  weighted encounter picks tuned per depth.
- Loot and reward: drop weights, item values, and the depth-weighted draw tuned so finds
  feel earned and the best gear is worth the descent.
- The economy: shop prices, trader margins, starting coin, and rest cost, so coin stays
  meaningful from the first run to the last.
- The experience and leveling curve set against the tuned danger.

Depends on the finished gameplay spine (through 0.16.0) and the content tables.

## Voxel engine and pipeline (pre-1.0)

Engine and tooling work that supports the asset pass (0.19.0) and the larger authored
models it brings. This is cross-cutting infrastructure, not a game minor release, but it
should land before 1.0. The voxel format is a 3D quantization: the conversion knobs are
the sampling rate (voxel size) and the sampling phase (a per-kit, per-axis offset), and
colour is a separate palette-quantization problem. Each `.vox` carries its own 256-colour
palette, so a scene freely mixes many palettes and there is no global one.

- Sparse voxel storage in memory. The model holds a dense `sx*sy*sz` byte array today, so
  a large or mostly-empty model costs memory and mesh-build time by its bounding volume,
  not its solid count. Move to a sparse representation so cost tracks the solid voxels.
- Disk compression for `.vox`, a `.voz` container. The format stores each solid voxel as
  four raw bytes with no compression. Compress the payload on disk. For a large file,
  compress it in independently restartable chunks with an index section near the front
  that a reader loads early to locate the chunks spatially. This lets a very large model
  stream in by region rather than load whole, complementing the world streaming.
- Filtering in voxelization. Add filter formulas that smooth the source before or during
  sampling, to ease or erase high-frequency detail that would otherwise sample as noise
  and aliasing. This is a third conversion knob beside rate and phase. Filter the
  occupancy geometry by prefiltering, not by dithering, since dithering a hard grid
  produces the speckle it is meant to remove; dithering is reserved for the colour channel.

## 1.0.0 - First complete descent

The slice sealed into a complete game: create a character, descend a finite dungeon of
rising danger, spend and resupply between runs, follow quests toward the depths, defeat
the guardian, and carry the relic back to Brackenridge to win, with the title, victory,
and death screens framing it and authored art throughout. Every art and audio source's
licence confirmed for distribution.

- The desktop install resolves its game data from the install location, so a menu-launched
  copy finds its `content/` beside the binary or at a prefix path, not only in the working
  directory. Install and the macOS bundle shipped in 0.17.0, but this last step is what
  lets an installed copy run on its own.
- An options surface: the placeholder options panel from 0.4.0 made real, with at least
  audio volume for the music and effects, so the game is adjustable without editing files.

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

World generation (concepts lifted from the sister project's worldgen; take what fits the
dungeon and the overworld, do not adopt the archipelago system wholesale):

- One worldgen descriptor. Collapse the seed and every generation parameter (zone and
  theme weights, depth count, density knobs) into a single struct declared once as a field
  list, so the cache keys, the save format, and the equality check are generated from that
  list rather than remembered field by field. Key caches on a hash of the whole descriptor,
  not on whichever fields a reader thought mattered, which is the bug this prevents.
- Seeded scatter by biome rule. Place forest and town surface detail (trees, rocks, grass,
  props) by Poisson-disk sampling with per-biome density rules from the seed chain,
  regenerated per region and never stored. This is where the stylized-nature and village
  kits land, rather than hand placement.
- Feature placement by flood-fill and classification. Identify connected areas, classify
  them by size, and place special rooms, shrines, or vaults with a minimum spacing so they
  do not crowd.
- Site search by rejection sampling. Place the town, the stairs, and quest sites by drawing
  candidates and scoring them against criteria (reachable, correct depth, clear footing),
  memoized on the seed. This generalizes the current spawn and stair scatter.
- Bounded outdoor fields. If a forest or overworld surface lands, build it as a heightfield
  with a radial falloff so the edge returns to water or cliff and hems the player in without
  a hard wall, with the coastline emerging from the field.
- Paths over a cost grid. Connect key sites (the town gate, the stairs, quest points) with
  A* over a slope or cost grid where corridors alone do not reach.

Presentation and performance:

- Lighting and shadows beyond the single directional term, with torches as light sources
  (emissive materials self-light today but cast no light).
- Audio beyond the core effects and one looping track per place: a fuller sound set and
  more than one track per place.
- Scene chunking and level-of-detail for larger dungeons.

## Asset replacements

Purchased or human-made art and audio are preferred, and art from purpose-built
generative tools (for example VoxelAI or Hyper3D) counts as production art, subject to
the usual licence confirmation. Art generated by Claude is only ever a placeholder: it
must be listed here and replaced before the release that ships it.

The world now draws authored models for the player, the whole bestiary, every environment tile,
and most loot, with procedural placeholders remaining only for townsfolk, a few item types, and
the geometry primitives: a ball, a plate for walls and floors, an arch for doors, and steps for
stairs. The player is a VoxelAI character
(see PROVENANCE.md); the tiles and the monsters are voxelized from Quaternius kits through
`tools/convert`, with the primitive standing in wherever a model's file is absent. The earlier
authored-art pipeline, which baked MagicaVoxel tiles and props and loaded a reference character,
was removed, so the build depends on no reference packs and makes the binary from source alone.

Done so far (Quaternius kits, see PROVENANCE.md and the tools manifests):

- Tiles for all three environments: the dungeon (brick, four floor variants, wall, post,
  door and leaf, stairs), the town (brick floor, plaster wall, timber post, door and leaf),
  and the forest (a rocky clearing: rock-path floor, rock wall, boulder post).
- All 26 monsters as models: the Monster Pack (skeleton, ooze, bat, demon); the easy enemies
  (rat, spider, frog, serpent, viper, wasp, each scaled to its size class); the posed humanoid
  foes (bandit, cultist, acolyte, witch from the outfit kit; orc, ogre, dark elf, elf archer
  from the Fantasy Races kit); the bestiary fiends (imp, puglin); the saurians reskinned from
  the dinosaur pack (raptor, drake, gorehorn, spineback); the shark; and the self-animated
  dire wolf. The bestiary was rewritten so every monster id maps to a real model.
- Loot models: weapons and shields from the Medieval Weapons Pack (dagger, sword, mace,
  silvered mace, great axe, spear, staff, bow, shield, dragonscale shield), and the common
  consumable, light, key, book, tool, and treasure loot from the Fantasy Props MegaKit (torch,
  key, the three potions, two scrolls, rations, holy symbol, spellbook, thieves tools, woodcraft
  kit, gold). Small hand props are magnified by a per-asset scale to read as floor loot.
- Core sound effects: six OGG one-shots (swing, hit, hurt, pickup, stairs, menu) from the
  Kenney CC0 audio packs (RPG Audio, Impact Sounds, Interface Sounds), shipped as delivered.
- Music: the game loops one track per place (hamlet, surface forest, dungeon), wired to
  `content/music/{town,forest,dungeon}.ogg`. The tracks used in development are three loops
  from the ELVGames "Cosy Melodies Music Pack", but unlike the other assets they are not CC0,
  so they are kept out of the repository (gitignored, sourced locally); see PROVENANCE.md and
  `content/music/README.md`. The game runs silent when they are absent.

Licence note: most kits are CC0, but the Fantasy Races and Bestiary kits are the Quaternius
Asset License (QAL) v1.0, not CC0 (orc, ogre, dark elf, elf archer, imp, puglin come from
them). The QAL grants royalty-free, no-attribution use and modification and lets the assets be
incorporated into a product such as this game; it only forbids reselling them as standalone
assets, which this does not. The Fish and Medieval Weapons packs ship no licence file but are
part of Quaternius's CC0 "by Quaternius" series. Both CC0 and QAL are acceptable for this
project as long as every kit's licence is documented; all of it is recorded per kit in
PROVENANCE.md.

Still to do before 1.0, at the same voxel scale:

- The remaining loot: armour (leather, chain, plate, hide), the beast trophy, and the geode
  have no fitted source yet, and the relic and locked chest are drawn specially; all stay on
  the placeholder. Townsfolk still use the primitive.
- Richer ground variety for the forest and town, and fuller forest tiles than a clearing.
- Confirm each source's licence before shipping a release that distributes its art.

The UI font is the exception already in place: `content/fonts/ui.cfn` is baked
bitmap data, not a redistributed font file, so it ships as is.
