# Unit tests. Each tests/t_*.pas is a standalone program that exits non-zero on
# failure. They exercise the GL-free logic (generation, the RNG, and the world's
# streaming via the null mesh backend), so they need no window or OpenGL context.

TESTSRC   = $(wildcard tests/t_*.pas)
TESTFLAGS = -Mobjfpc -Scghi $(MODE) $(UNITDIRS) -Fl$(SDL_PREFIX)/lib \
            -Fi$(BUILD) -FE$(BUILD)/tests -FU$(BUILD)/tests

.PHONY: test
test: | $(BUILD)/tests
	@fail=0; \
	for s in $(TESTSRC); do \
	  b=$(BUILD)/tests/`basename $$s .pas`; \
	  if ! $(FPC) $(TESTFLAGS) -o$$b $$s > $(BUILD)/tests/compile.log 2>&1; then \
	    echo "COMPILE FAIL: $$s"; cat $(BUILD)/tests/compile.log; fail=1; continue; \
	  fi; \
	  echo "== `basename $$s .pas` =="; \
	  if ! $$b; then fail=1; fi; \
	done; \
	if [ $$fail -ne 0 ]; then echo "SOME TESTS FAILED"; exit 1; fi; \
	echo "ALL TESTS PASSED"

$(BUILD)/tests: | $(BUILD)
	mkdir -p $(BUILD)/tests
