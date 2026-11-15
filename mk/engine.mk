# The demo binary: an SDL3 window with a GL 3.3 core renderer that draws one
# voxel model under a static diorama camera.

DEMO     = $(BUILD)/chasm$(EXE)
DEMOSRC  = chasm.lpr $(wildcard src/*/*.pas)

$(DEMO): $(DEMOSRC) | $(BUILD)
	$(FPC) $(FPCFLAGS) -o$(DEMO) chasm.lpr
