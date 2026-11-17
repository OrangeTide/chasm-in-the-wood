# Chasm in the Wood: top-level build.
#
# This file stays thin on purpose. The real rules live in mk/*.mk, one file per
# concern, so the build grows by adding a fragment rather than by swelling a
# single script. config.mk must come first; it defines the toolchain and paths
# the other fragments use. The others are pulled in by wildcard, and the leading
# dash keeps make quiet if the directory is ever empty.
#
# `all` is declared here, before the includes, so it stays make's default goal
# rather than the first target a fragment happens to define. Its real
# prerequisites are added below, once the fragments have defined them.
all:

include mk/config.mk
-include mk/engine.mk
-include mk/tools.mk
-include mk/tests.mk

# Default goal: the demo binary. The world is drawn from procedurally generated
# placeholders, so the build no longer bakes any art or needs the reference packs.
all: $(DEMO)

.PHONY: all run clean
run: all
	./$(DEMO)

clean:
	rm -rf $(BUILD)
