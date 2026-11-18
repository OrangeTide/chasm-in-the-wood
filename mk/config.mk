# Toolchain, paths, and flags shared by every build fragment.

FPC   ?= fpc
MODE  ?= -O2
BUILD ?= build

# Opt-in instrumentation: `make CHECKS=1` (and likewise `make CHECKS=1 test`).
# FPC 3.2.2 has no -fsanitize, so this leans on FPC's own runtime checks instead:
# -Cr range, -Co integer overflow, -Ci I/O, -Ct stack, -CR object method-call
# validity, and -Sa to keep assertions live. -g -gl add debug and line info so
# backtraces carry source lines. Built at -O1 so the checks are not optimised
# away. Heaptrc (-gh) is left out on purpose: it halts on every block still held
# at exit, and the tile-region cache is reachable-at-exit by design, not leaked.
# Leaks and use-after-free are the Valgrind target's job: `make CHECKS=1 valgrind`.
# MODE threads into the demo, the tools, and the tests alike.
ifdef CHECKS
  MODE := -O1 -g -gl -Cr -Co -Ci -Ct -CR -Sa
endif

# SDL3 was built from source and lives under /usr/local by default. Override
# SDL_PREFIX if it is installed elsewhere. We link libSDL3 at build time but load
# OpenGL entry points at runtime through SDL, so there is no libGL link here.
SDL_PREFIX ?= /usr/local

# Offline asset converters. assimp turns the reference FBX into an OBJ; the
# convert program (ImageMagick) is not needed yet but is kept here for when
# textured voxel sources arrive.
ASSIMP ?= assimp

# C compiler for the one vendored C object, the public-domain stb_vorbis decoder.
CC     ?= cc
CFLAGS ?= -O2

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
           -Fusrc/world -Fusrc/game -Fusrc/gui -Fusrc/util

# -Mobjfpc: Object Pascal dialect. -Scghi: C ops, goto, inline, nested procs.
# -Fl: link search path for libSDL3. Units and objects land under $(BUILD).
FPCFLAGS  = -Mobjfpc -Scghi $(MODE) $(UNITDIRS) -Fl$(SDL_PREFIX)/lib \
            -Fi$(BUILD) -Fo$(BUILD) -FE$(BUILD) -FU$(BUILD)
TOOLFLAGS = -Mobjfpc -Scghi $(MODE) $(UNITDIRS) -Fl$(SDL_PREFIX)/lib \
            -Fi$(BUILD) -FE$(BUILD)/tools -FU$(BUILD)/tools

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/tools: | $(BUILD)
	mkdir -p $(BUILD)/tools
