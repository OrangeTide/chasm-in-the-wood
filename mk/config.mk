# Toolchain, paths, and flags shared by every build fragment.

FPC   ?= fpc
MODE  ?= -O2
BUILD ?= build

# SDL3 was built from source and lives under /usr/local by default. Override
# SDL_PREFIX if it is installed elsewhere. We link libSDL3 at build time but load
# OpenGL entry points at runtime through SDL, so there is no libGL link here.
SDL_PREFIX ?= /usr/local

# Offline asset converters. assimp turns the reference FBX into an OBJ; the
# convert program (ImageMagick) is not needed yet but is kept here for when
# textured voxel sources arrive.
ASSIMP ?= assimp

# Windows FPC appends .exe to its output; mirror that so target names match the
# binaries the recipes invoke on every host.
ifeq ($(OS),Windows_NT)
  EXE := .exe
else
  EXE :=
endif

# One unit search path per source concern. A new concern adds its directory
# here and nowhere else.
UNITDIRS = -Fusrc/platform -Fusrc/gfx -Fusrc/math -Fusrc/voxel -Fusrc/render \
           -Fusrc/world -Fusrc/game -Fusrc/util

# -Mobjfpc: Object Pascal dialect. -Scghi: C ops, goto, inline, nested procs.
# -Fl: link search path for libSDL3. Units and objects land under $(BUILD).
FPCFLAGS  = -Mobjfpc -Scghi $(MODE) $(UNITDIRS) -Fl$(SDL_PREFIX)/lib \
            -Fi$(BUILD) -FE$(BUILD) -FU$(BUILD)
TOOLFLAGS = -Mobjfpc -Scghi $(MODE) $(UNITDIRS) -Fl$(SDL_PREFIX)/lib \
            -Fi$(BUILD) -FE$(BUILD)/tools -FU$(BUILD)/tools

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/tools: | $(BUILD)
	mkdir -p $(BUILD)/tools
