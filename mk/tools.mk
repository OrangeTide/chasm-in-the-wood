# Offline tools. voxelize rasterizes an OBJ mesh into a MagicaVoxel .vox file, and
# voxpack extracts a named model from a multi-model .vox pack into a lone .vox. Both
# reuse the engine's voxfile reader and writer so tool and runtime agree on the format.

VOXELIZE = $(BUILD)/tools/voxelize$(EXE)
VOXPACK  = $(BUILD)/tools/voxpack$(EXE)

.PHONY: tools
tools: $(VOXELIZE) $(VOXPACK)

$(VOXELIZE): tools/voxelize.pas $(wildcard src/*/*.pas) | $(BUILD)/tools
	$(FPC) $(TOOLFLAGS) -o$(VOXELIZE) tools/voxelize.pas

$(VOXPACK): tools/voxpack.pas $(wildcard src/*/*.pas) | $(BUILD)/tools
	$(FPC) $(TOOLFLAGS) -o$(VOXPACK) tools/voxpack.pas
