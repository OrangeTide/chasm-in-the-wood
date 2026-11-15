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

.PHONY: assets
assets: $(DEMO_VOX)

$(FBX_OUT): | $(BUILD)
	mkdir -p $(BUILD)/fbx
	unzip -o -j "$(FBX_ZIP)" "$(FBX_MEMBER)" -d $(BUILD)/fbx

$(OBJ_OUT): $(FBX_OUT)
	mkdir -p $(BUILD)/obj
	$(ASSIMP) export "$(FBX_OUT)" "$(OBJ_OUT)"

$(DEMO_VOX): $(OBJ_OUT) $(VOXELIZE)
	mkdir -p $(dir $(DEMO_VOX))
	$(VOXELIZE) "$(OBJ_OUT)" "$(DEMO_VOX)" $(VOX_RES)
