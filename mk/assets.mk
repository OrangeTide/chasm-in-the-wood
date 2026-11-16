# Asset pipeline: the reference modular FBX becomes the voxel model the demo
# displays. The chain is FBX --(assimp)--> OBJ --(voxelize)--> .vox. assimp and
# the voxelizer run only at build time; the committed product is the .vox.

# The source archive ships the mesh. Its name has spaces, so it is only ever
# named inside a recipe (quoted), never used as a prerequisite.
FBX_ZIP   = REF/3d/Free 3D Modular Game Assets For Prototyping.zip
FBX_MEMBER = Free 3D Modular Game Assets For Prototyping/Character/Character.fbx

FBX_OUT   = $(BUILD)/fbx/Character.fbx
OBJ_OUT   = $(BUILD)/obj/character.obj
DEMO_VOX  = content/models/character.vox

# Target voxel resolution: the model's longest axis maps to this many voxels.
VOX_RES  ?= 48

# Tiles: each environment (dungeon, forest, town) gets a floor, a wall, and where it
# applies a stairs, extracted by voxpack from a human-made MagicaVoxel pack into a lone
# .vox the engine bakes to a mesh. The packs live in REF (local, untracked) like the
# character source; the baked tiles under content/tiles are build output.
DUNGEON_PACK ?= REF/voxel/DungeonCrawler_Source.vox
NATURE_ZIP   ?= REF/voxel/TinyVoxelNature.zip
NATURE_VOX    = $(BUILD)/ref/voxelWorld.vox

TILES = \
  content/tiles/dungeon/floor.vox content/tiles/dungeon/wall.vox \
  content/tiles/dungeon/stairs.vox \
  content/tiles/forest/floor.vox content/tiles/forest/wall.vox \
  content/tiles/town/floor.vox content/tiles/town/wall.vox \
  content/tiles/town/stairs.vox

.PHONY: assets
assets: $(DEMO_VOX) $(TILES)

$(NATURE_VOX): | $(BUILD)/ref
	unzip -o -j "$(NATURE_ZIP)" "vox/voxelWorld.vox" -d $(BUILD)/ref

$(BUILD)/ref content/tiles/dungeon content/tiles/forest content/tiles/town:
	mkdir -p $@

# Dungeon: brick from the dungeon pack.
content/tiles/dungeon/floor.vox: $(VOXPACK) $(DUNGEON_PACK) | content/tiles/dungeon
	$(VOXPACK) get "$(DUNGEON_PACK)" FloorBlock_Top_01 "$@"
content/tiles/dungeon/wall.vox: $(VOXPACK) $(DUNGEON_PACK) | content/tiles/dungeon
	$(VOXPACK) get "$(DUNGEON_PACK)" BrickBlock_Tall_01 "$@"
content/tiles/dungeon/stairs.vox: $(VOXPACK) $(DUNGEON_PACK) | content/tiles/dungeon
	$(VOXPACK) get "$(DUNGEON_PACK)" Stairs_Straight_01 "$@"

# Forest: grass and a tree from the nature pack.
content/tiles/forest/floor.vox: $(VOXPACK) $(NATURE_VOX) | content/tiles/forest
	$(VOXPACK) get "$(NATURE_VOX)" grassTile01 "$@"
content/tiles/forest/wall.vox: $(VOXPACK) $(NATURE_VOX) | content/tiles/forest
	$(VOXPACK) get "$(NATURE_VOX)" tree01 "$@"

# Town: packed-earth ground from the nature pack, stone cottage walls and the chasm
# stairs from the dungeon pack.
content/tiles/town/floor.vox: $(VOXPACK) $(NATURE_VOX) | content/tiles/town
	$(VOXPACK) get "$(NATURE_VOX)" dirt "$@"
content/tiles/town/wall.vox: $(VOXPACK) $(DUNGEON_PACK) | content/tiles/town
	$(VOXPACK) get "$(DUNGEON_PACK)" BrickBlock_Tall_01 "$@"
content/tiles/town/stairs.vox: $(VOXPACK) $(DUNGEON_PACK) | content/tiles/town
	$(VOXPACK) get "$(DUNGEON_PACK)" Stairs_Straight_01 "$@"

$(FBX_OUT): | $(BUILD)
	mkdir -p $(BUILD)/fbx
	unzip -o -j "$(FBX_ZIP)" "$(FBX_MEMBER)" -d $(BUILD)/fbx

$(OBJ_OUT): $(FBX_OUT)
	mkdir -p $(BUILD)/obj
	$(ASSIMP) export "$(FBX_OUT)" "$(OBJ_OUT)"

$(DEMO_VOX): $(OBJ_OUT) $(VOXELIZE)
	mkdir -p $(dir $(DEMO_VOX))
	$(VOXELIZE) "$(OBJ_OUT)" "$(DEMO_VOX)" $(VOX_RES)
