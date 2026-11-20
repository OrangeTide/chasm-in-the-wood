# Changelog

All notable changes to Chasm in the Wood are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow semantic versioning. Each minor release gets a dated section and an
annotated git tag whose message is that release's changes.

Releases 0.1.0 through 0.3.0 were cut together after the fact, in one commit
that bumped VERSION straight to 0.3.0. Their tags sit on the matching milestone
commits, which predate that bump, so VERSION reads 0.0.1 at those tags. This is
expected, not a mismatch to fix. From 0.4.0 on, each release has its own cut
commit that bumps VERSION, and the tag sits on it.

## [Unreleased]

## [0.19.0] - 2026-11-19

Art and audio pass: the procedural placeholders give way to authored voxel models and
real sound. The world is built from Quaternius kits voxelized through a new asset
pipeline, the whole bestiary and most loot are modeled, the core actions have sound, and
each place loops its own music.

### Added
- A data-driven asset pipeline under `tools/`: a staging step pulls each source from its
  kit archive, and a converter voxelizes it to a `.vox` at the one object voxel-unit,
  driven by a manifest. Voxelization is set by voxel size and a per-axis phase offset, the
  voxelizer samples an OBJ material's `map_Kd` texture per voxel, and a `pose` step
  retargets an idle animation onto a rigged character so a humanoid stands naturally rather
  than voxelizing in its T-pose. A per-asset `scale=` factor sizes a stylized kit's models
  to a common scale, and a `tex=` override stages a kit's external base-colour image for a
  GLB that bakes its texture inside.
- Authored tiles for all three environments: the dungeon (brick, four floor variants, wall,
  corner post, door and leaf, up and down stairs), the town of Brackenridge (brick floor,
  plaster wall, timber post, door and leaf), and the forest clearing (rock-path floor, rock
  wall, boulder post). A procedural primitive still stands in wherever a tile is absent.
- Models for all 26 monsters, each mapped to a real creature: the Monster Pack skeleton,
  ooze, bat, and demon; the scaled easy enemies (rat, spider, frog, serpent, viper, wasp);
  the posed humanoid foes (bandit, cultist, acolyte, witch, orc, ogre, dark elf, elf
  archer); the bestiary imp and puglin; the saurians (raptor, drake, gorehorn, spineback);
  the shark; and the self-animated dire wolf. The bestiary table was rewritten so every
  monster id maps to a model.
- Loot models: weapons and shields from the Medieval Weapons Pack and the common
  consumable, light, key, book, tool, and treasure items from the Fantasy Props MegaKit.
  Small hand props are magnified to read as floor loot.
- Core sound effects: six OGG one-shots (swing, hit, hurt, pickup, stairs, menu) from the
  Kenney CC0 audio packs, fired by the game's actions and silent when absent.
- Music that loops one track per place: the hamlet, the surface forest around it, and the
  dungeon below each play their own track through the existing audio path.

### Changed
- Monster, creature, and loot models now load from `content/models/<id>.vox` by content id,
  falling back to the procedural primitive when the file is absent, so an art drop is a file
  drop with no code change.

### Notes
- Most kits are CC0; the Fantasy Races and Bestiary kits are the Quaternius Asset License
  (QAL) v1.0, which permits this use. Each source's licence is documented per kit in
  `PROVENANCE.md`. The development music is the ELVGames "Cosy Melodies" pack, which is not
  CC0 and whose redistribution terms are unconfirmed, so its `.ogg` files are gitignored and
  sourced locally rather than shipped; the game runs silent without them.
- Armour, a few miscellaneous items, the relic, the locked chest, and the townsfolk remain
  on the procedural placeholder, left for 1.0.

## [0.18.0] - 2026-11-17

Quests and dialogue: goals beyond the one relic, given by the people of Brackenridge and
tracked in a real quest log, with townsfolk and dungeon shrines worth talking to. The
single carry-home relic gives way to a three-shard descent, and locked doors gate routes
behind a found key.

### Added
- A quest system driven entirely by flags. A `quests.txt` table of flag-gated quests,
  derived flags, and journal lines loads into the content tables; a flag set (`flags.pas`)
  with the runtime in `quests.pas` reports the active quests, the current objective, and
  the journal, rebuilding all of it from the flags alone.
- A quest-log panel, toggled with `J`, listing completed and active quests with their
  current stage and the journal. The HUD compass is driven by the quest flags, pointing at
  the chasm, the elder, the depth's live interaction point, or the stairs toward the next
  step, in place of the old hardcoded chain.
- Branching dialogue from `dialogs.txt`: dialogs of numbered nodes and responses, parsed
  by `dialogtext.pas` and walked over the flag set. A conversation window shows the
  speaker, the narration, and a button per response. Townsfolk open their dialogue instead
  of a one-line greeting: the barkeep, the elder who sets the main quest, and the
  apothecary, while the trader still opens the store.
- Response actions: move between nodes, raise a quest flag, open a shop, start a fight, or
  hand a recruit, revive, or identify action to the game. A response can be gated behind a
  `needflag` so it appears only once a quest stage is reached.
- The three-shard quest. Each depth stands an interaction point in its objective room: the
  crypt altar and the grotto crystal give their shards, and the bottom holds the demon
  lord, whose defeat grants the infernal shard. The three shards make the relic whole, the
  elder opens the road, and the sealed gate below ends the descent, which is the new
  victory condition in place of carrying a single relic home.
- The apothecary's temple blessing restores a wounded player to full.
- Locked doors in dungeon generation, a deterministic share of the doors, opened by the
  same key item that unlocks chests. An opened door stays open when its region
  regenerates.

### Changed
- The save format is version 6: it now persists the quest and story flags and the
  opened-door registry alongside the slain and taken registries, so a saved game keeps its
  quest progress and the doors it opened. Older saves are refused.
- The loadable formats are documented: `docs/formats/quests.md` and `docs/formats/dialogs.md`,
  with `save.md` updated for the version 6 layout.

## [0.17.0] - 2026-11-17

Packaging and hardening: the game installs as a desktop application, its user-visible text
moves into a loadable string table, and an opt-in checks build hardens the engine against
latent faults.

### Added
- Desktop install and packaging. `make install` places the binary, a `chasm.desktop`
  launcher, and the application icon in the hicolor theme at several sizes, honouring
  `PREFIX` and `DESTDIR`; `make uninstall` reverses it. On macOS, `make bundle` assembles
  `Chasm.app` with an `Info.plist` versioned from the `VERSION` file and a `chasm.icns`.
  The icon is the gold-on-green Hollow Crown wordmark.
- User-visible text in a loadable string table. The HUD stat labels and other on-screen
  text move out of the code into a string table loaded at runtime, and the loadable file
  formats are documented under `docs/formats`.
- An opt-in checks build. `make CHECKS=1` turns on FPC's range, overflow, I/O, stack, and
  method-call checks with debug info, and `make CHECKS=1 valgrind` runs the binary under
  Valgrind for the memory checks FPC 3.2.2 cannot do itself, since it has no `-fsanitize`.
  The checks apply to the demo, the tools, and the tests.

### Fixed
- Non-deterministic entity placement. The entity constructors left some record fields
  uninitialised, so a region could regenerate with different contents across two builds in
  one process. Each record is now cleared before use.

## [0.16.0] - 2026-11-17

Item depth: the item table's unused kinds and flags come into play, so what you find and
carry matters more than one weapon and one potion.

### Added
- Light sources. A carried torch burns for a set time and pushes the underground fog out
  to a full room's depth; the next torch in the pack takes over when one gutters. Run out
  and the fog closes to the player's feet. The opening kit packs torches, the trader sells
  them, and the status window shows the burn left or that the player is in the dark. Town
  is daylit and burns nothing.
- Locked chests and keys. Some underground loot rooms hold a locked chest, tinted brass,
  whose contents are the richest of several hash-fixed loot draws. Walking into reach
  opens it only if the pack holds a key, which is then spent; with no key it stays shut
  and says so once. Keys (the key kind) drop as loot and sit in the trader's stock, and
  the status window shows the count carried.
- Scrolls and a data-driven use effect. An item may carry an `eff:` and `pow:` tag that
  sets what using it does, so single-use items are added in content without new code.
  `heal` restores hit points (a power of zero is a full restore) and `light` extends the
  carried torch. Two scrolls ship: a Scroll of Mending and a Scroll of Daylight. F reads
  the first usable scroll, mirroring R for potions.
- Depth-weighted loot. A room's loot is drawn by a weight that scales with its value and
  the depth, so treasure and elixirs crowd out torches and rations the deeper the descent
  goes. Treasure-kind items are sale-only reward.
- Depth-gated shop stock. A `@N` token in shops.txt gates the stock after it behind
  reaching dungeon depth N, and the trader offers only what the player's deepest reach has
  passed. The cheap starting kit is always on the shelf; chain, plate, a great axe, and
  the silvered and dragonscale gear appear as the descent deepens and town is revisited.
- Two-handed weapons bar a shield. Wielding one frees the off-hand to the pack and drops
  the shield's armour bonus while it is held; strapping a shield back on bumps the
  two-handed weapon off instead.

### Changed
- The save format is version 5: the save now stores the deepest depth reached, which
  drives the depth-gated shop stock. Saves from earlier versions are not loadable.

## [0.15.0] - 2026-11-17

A front end for the loop: a title screen, and victory and death endings, all drawn with
the window toolkit.

### Added
- A title screen that starts a new game or continues a saved one, and victory and death
  screens that end a run. A front-end state machine wraps the world: the title opens over
  the town, and the run ends on a victory or death screen instead of a log line. One
  centered menu window serves all three screens, reconfigured per screen, and the world
  freezes behind a menu or the creation window.
- The GUI gains a button tag payload and a settable window title, so one window can be
  reconfigured for each screen.

## [0.14.0] - 2026-11-17

### Added
- A unified trade window. Speaking to the town trader opens a two-column barter screen:
  shop stock to buy on one side, the pack to sell on the other. Clicking rows stages a
  deal, a running balance and the resulting purse show at the foot, and confirming
  settles it. Selling is giving only, buying is taking only, and barter is both, with
  coin covering the difference.
- A shop table (shops.txt): each shop lists the item ids it stocks, resolved to content
  indices at load.
- GL-free trade logic: the trader buys at half an item's value and sells at full, the
  relic is never tradable, and a deal is refused when the pack is full or the purse
  cannot cover the payment.
- Character backgrounds (backgrounds.txt): a past life chosen at creation that brings
  starting coin, rolled from a dice expression. The creation window gains a background
  picker, and the new-game default line carries a default background.
- A dice-expression evaluator (the `dice` unit) for expressions like `5*2d6`, `2d6+5`,
  or a plain number, rolled against the seeded RNG with multiplication binding over
  addition.

### Changed
- The save format is version 4: the player record now stores the chosen background. Saves
  from earlier versions are not loadable.

## [0.13.0] - 2026-11-16

### Added
- Rock backfill and distance fog enclose the dungeon. Rock that borders carved space
  draws as a wall-height block, so rooms and corridors sit in solid stone, and the view
  fades toward the background dark with distance.
- Emissive voxel materials. A `.vox` colour index flagged `_emit` lights itself and
  thins the fog over it, so a torch or rune reads as a beacon in the dark.
- An objective compass in the upper-right points along a small quest chain: find the
  chasm in town, descend to the bottom, take the Heart, and climb back out.
- Looping OGG Vorbis background music, one track per place, decoded once and streamed.
  It is optional, so a headless or silent run is unaffected. No tracks ship.
- A proportional bitmap UI font with real lowercase, loadable at runtime from a CFN file
  (`content/fonts/ui.cfn`) so the face is swappable without a rebuild. A BDF to CFN baker
  is included.

### Changed
- Movement and combat are now real-time, replacing the turn loop. The player holds a
  continuous position and walks relative to the camera, sliding along walls; an awake
  monster chases and strikes on its own cooldown, and the player swings at the nearest
  foe and gathers loot by walking over it. The d20 rolls stay; the energy scheduler is
  gone.
- Every free-standing model sits at one voxel scale (0.0625), so a model's size is its
  voxel count. Until new art lands the world draws procedural placeholders built by
  formula: a ball for actors and loot, a plate for walls and floors, an arch for doors,
  and steps for stairs. The authored-art baking pipeline is removed, so the build is made
  from source alone.
- The status window now shows only the live stats; the message log moved to its own
  transparent HUD overlay along the lower-left.

## [0.12.0] - 2026-11-16

### Added
- A guardian stands beside the relic on the bottom of the chasm, a boss far tougher than
  the rank and file. It must be beaten to carry the relic out, and once felled it stays
  down.

### Changed
- Which monster fills a room now comes from the authored encounter tables
  (encounters.txt): each area points at a weighted list, and the room's seed makes the
  pick. Deeper levels tilt toward tougher foes, so the danger curve rises from the forest
  edge to the bottom.

## [0.11.0] - 2026-11-16

### Added
- A new game forges a character instead of a fixed vagrant. The player picks a species
  and a class, shown in a creation window at the start: the species shifts the six
  ability scores (and a human-style species sharpens the class's prime ability), and the
  class sets the hit die the hit points come from and the opening kit, worn on creation.
  A default character stands in until Begin, so the game is playable at once.
- Experience and levels. Slain monsters grant their experience, and banked experience
  raises levels, each lifting the hit-point maximum and the to-hit. The character sheet
  shows the real name, class, species, level, experience, and ability scores.

### Changed
- The combat stats now fold in abilities and level: armour and dexterity set the armour
  class, strength and level set the to-hit, strength adds to melee damage, and a weapon
  sets the damage die. Combat reads only the derived numbers.
- The save format records the character and its progression, so it is version 3. Saves
  from earlier versions are refused.

## [0.10.0] - 2026-11-16

### Added
- The descent has a bottom and a goal. The deepest dungeon level hosts no stairs down,
  so it is the bottom of the chasm, and a single relic, the Heart of the Chasm, waits in
  the far room of its origin region. Carrying the relic up to Brackenridge wins, surfaced
  in the log for now. The relic is taken like loot but never respawns, never appears as
  random loot, and is never sold, and it glows in its own colour so it reads as the goal.

### Changed
- Danger now grows with depth. Deeper monsters are hardier and strike harder, and rooms
  that would sit empty near the top crowd with monsters, more of them the deeper the
  level. The top level is left exactly as it was.

## [0.9.0] - 2026-11-16

### Added
- Gear the player carries can be worn and now drives combat. Three slots hold a weapon,
  a suit of armour, and a shield; a weapon sets the damage die and steadies the to-hit
  roll, armour sets the armour class, and a shield adds to it. With nothing worn the
  player falls back to an unarmed base. A new character starts with a dagger and leather
  worn. Open the pack and the equipment doll with I, then drag a weapon, armour, or
  shield onto the doll to wear it and drag it off to stow it; the inventory, the
  equipment doll, and the character sheet all show the live pack, worn gear, and derived
  stats. R quaffs a healing potion from the pack. The worn slots are saved and restored
  with the rest of the game.
- Loot on the ground is drawn from authored voxel props instead of coloured cubes. Each
  item kind maps to a small model (a chest for treasure, a torch for light, skulls for
  the rest), extracted from the dungeon pack and meshed once, then stood upright on its
  tile with the same base transform the creatures use.
- The hamlet now sits in a clearing: walkable forest (grass with scattered trees)
  surrounds it, generated per tile from the seed, and gates through the hamlet wall let
  the player leave for the woods. The chasm still descends to the dungeon.

### Changed
- The world is drawn from authored voxel tiles instead of flat placeholder colours,
  with a distinct set per environment: the dungeon (brick), the forest (grass and
  trees), and the town (packed earth and stone cottages). Each tile kind is a human-made
  voxel model, extracted from a MagicaVoxel pack by the new `voxpack` tool and baked once
  into a mesh drawn per visible cell. The render path moved from the streaming
  voxel-chunk world to this tile-mesh instancing. The sets differ in native resolution
  (the dungeon brick is 50 voxels across, the forest grass 16), so each tile is scaled by
  its footprint to fill one cell, which lets the detailed dungeon and the chunky forest
  share one grid. Doors draw the floor until a door leaf lands.
- The save format now records the worn gear, so it is version 2. Saves written by 0.8.0
  are refused rather than loaded wrongly.

## [0.8.0] - 2026-11-16

### Added
- Save and load, on F5 and F9, to a single slot beside the executable. Because the
  world regenerates from its seed, a save holds only what cannot be recomputed: the
  seed, whether the player is in town or at a depth, the player's position, stats,
  purse, and pack, and the two registries of change (the monsters slain and the loot
  taken). Loading restores those and rebuilds the world from the seed at the saved
  place, so every visited depth returns exactly as it was left.
- The registries can be enumerated, and a load that fails (a missing, malformed, or
  wrong-version file) is refused without disturbing the game in progress.

### Added
- The surface hamlet of Brackenridge: a bounded town of green ground, timber buildings,
  and townsfolk, rendered through the same voxel world as the dungeon under its own
  theme. The game now starts in town.
- The descent. The chasm at the heart of the hamlet drops into dungeon depth 0, and the
  climb out of depth 0 returns to the surface. Health, purse, and pack carry across;
  only a new game resets them.
- Townsfolk: the innkeeper, trader, reeve, and a villager stand by their doors as
  peaceful entities the turn loop never fights. Speaking to an adjacent townsperson
  with the action key opens with a line of their own.
- A basic coin economy. Loot props are picked up by stepping onto them in the dungeon,
  kept in a pack, and sold to the trader for the sum of their values; the innkeeper
  restores full health for a few coins. A picked-up prop stays taken when its region
  regenerates, like a slain monster stays dead.
- The HUD reports gold and pack size, names the town or the depth, and prompts the
  action key in town.

## [0.6.0] - 2026-11-16

### Added
- A turn loop over the placed entities. A player action, a step or a melee attack into
  an occupied tile, spends one turn; bumping a wall spends none. After the player acts,
  each monster gains energy by its own speed and acts while it holds enough, so a
  faster monster takes more actions per player turn.
- Basic melee combat: a d20 to-hit roll plus the attacker's bonus against the target's
  armour class, then a damage die. The player and every monster carry the stats the
  rolls read, the player's fixed for now until class and species selection lands.
- Monster behaviour: a monster idles until it sights the player along a clear line,
  then chases over open floor and strikes when adjacent. It will not share a tile with
  another monster or walk onto the player except to attack.
- Death. A slain monster is removed and recorded by its stable identity, so the room it
  held regenerates empty for the rest of the session. A slain player respawns at the
  depth 0 entrance at full health, with earlier kills left dead.
- The HUD leads with the player's health and shows the tail of a combat log, so hits,
  misses, and deaths read as they happen.

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
