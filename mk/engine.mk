# The demo binary: an SDL3 window with a GL 3.3 core renderer that draws one
# voxel model under a static diorama camera.

DEMO     = $(BUILD)/chasm$(EXE)
DEMOSRC  = chasm.pas $(wildcard src/*/*.pas)

# The vendored OGG decoder, compiled once and linked into the binary by the audio
# unit's {$L} directive (found via -Fo$(BUILD) in FPCFLAGS).
STBVORBIS = $(BUILD)/stbvorbis.o
$(STBVORBIS): third_party/stb_vorbis.c | $(BUILD)
	$(CC) $(CFLAGS) -c third_party/stb_vorbis.c -o $(STBVORBIS)

$(DEMO): $(DEMOSRC) $(STBVORBIS) | $(BUILD)
	$(FPC) $(FPCFLAGS) -o$(DEMO) chasm.pas
