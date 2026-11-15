# Offline tools. voxelize rasterizes an OBJ mesh into a MagicaVoxel .vox file,
# reusing the engine's voxfile writer so tool and runtime agree on the format.

VOXELIZE = $(BUILD)/tools/voxelize$(EXE)

.PHONY: tools
tools: $(VOXELIZE)

$(VOXELIZE): tools/voxelize.pas $(wildcard src/*/*.pas) | $(BUILD)/tools
	$(FPC) $(TOOLFLAGS) -o$(VOXELIZE) tools/voxelize.pas
