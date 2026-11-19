# Offline tools. voxelize rasterizes an OBJ mesh into a MagicaVoxel .vox file, and
# voxpack extracts a named model from a multi-model .vox pack into a lone .vox. Both
# reuse the engine's voxfile reader and writer so tool and runtime agree on the format.
#
# pose and gltf2glb handle the rigged character kits: gltf2glb packs a glTF plus its
# external .bin into a self-contained .glb, and pose skins that glb at an animation pose
# (a clip retargeted from the Universal Animation Library) and writes a posed OBJ, so the
# character voxelizes standing rather than in its bind (T) pose. Both are C, built on the
# vendored cgltf reader/writer and HandmadeMath and the glTF loader/animator from aldeby
# (tools/model.*, tools/anim.*).

VOXELIZE = $(BUILD)/tools/voxelize$(EXE)
VOXPACK  = $(BUILD)/tools/voxpack$(EXE)
POSE     = $(BUILD)/tools/pose$(EXE)
GLTF2GLB = $(BUILD)/tools/gltf2glb$(EXE)

# The glTF loader and animator shared by pose and gltf2glb, and their vendored headers.
CHARTOOL_SRC    = tools/model.c tools/anim.c
CHARTOOL_HDR    = tools/model.h tools/anim.h third_party/cgltf.h \
                  third_party/cgltf_write.h third_party/HandmadeMath.h
CHARTOOL_CFLAGS = -Ithird_party -Itools -Wno-format-truncation

.PHONY: tools
tools: $(VOXELIZE) $(VOXPACK) $(POSE) $(GLTF2GLB)

$(VOXELIZE): tools/voxelize.pas $(wildcard src/*/*.pas) | $(BUILD)/tools
	$(FPC) $(TOOLFLAGS) -o$(VOXELIZE) tools/voxelize.pas

$(VOXPACK): tools/voxpack.pas $(wildcard src/*/*.pas) | $(BUILD)/tools
	$(FPC) $(TOOLFLAGS) -o$(VOXPACK) tools/voxpack.pas

$(POSE): tools/pose.c $(CHARTOOL_SRC) $(CHARTOOL_HDR) | $(BUILD)/tools
	$(CC) $(CFLAGS) $(CHARTOOL_CFLAGS) -o $(POSE) tools/pose.c $(CHARTOOL_SRC) -lm

$(GLTF2GLB): tools/gltf2glb.c tools/model.c $(CHARTOOL_HDR) | $(BUILD)/tools
	$(CC) $(CFLAGS) $(CHARTOOL_CFLAGS) -o $(GLTF2GLB) tools/gltf2glb.c tools/model.c -lm
