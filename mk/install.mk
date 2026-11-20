# Packaging and desktop integration. Two paths from the same icon and binary:
# `make install` wires the game into a Linux desktop (binary, .desktop entry, and
# hicolor icons), and `make bundle` assembles a macOS Chasm.app. The icon is the
# gold-on-green wordmark in packaging/chasm.png; see PROVENANCE.md for its font.

PREFIX  ?= /usr/local
DESTDIR ?=
bindir   = $(PREFIX)/bin
datadir  = $(PREFIX)/share
appsdir  = $(datadir)/applications
icondir  = $(datadir)/icons/hicolor
# The game's own data root. The binary resolves content/ here at runtime
# (<prefix>/share/chasm/content), relative to its own location, so a
# menu-launched copy finds its data without a working directory set.
gamedatadir = $(datadir)/chasm

CONVERT ?= convert

ICON_MASTER = packaging/chasm.png
# Powers of two that divide the 1024 master cleanly, so point sampling keeps the
# pixel-art icon crisp at every installed size.
ICON_SIZES  = 16 32 64 128 256 512

# ---- Linux desktop install ----
.PHONY: install uninstall
install: $(DEMO)
	install -d $(DESTDIR)$(bindir)
	install -m 755 $(DEMO) $(DESTDIR)$(bindir)/chasm
	install -d $(DESTDIR)$(gamedatadir)
	cp -R content $(DESTDIR)$(gamedatadir)/
	install -d $(DESTDIR)$(appsdir)
	install -m 644 packaging/chasm.desktop $(DESTDIR)$(appsdir)/chasm.desktop
	for s in $(ICON_SIZES); do \
	  install -d $(DESTDIR)$(icondir)/$${s}x$${s}/apps; \
	  $(CONVERT) $(ICON_MASTER) -filter point -resize $${s}x$${s} \
	    $(DESTDIR)$(icondir)/$${s}x$${s}/apps/chasm.png; \
	done

uninstall:
	rm -f $(DESTDIR)$(bindir)/chasm
	rm -rf $(DESTDIR)$(gamedatadir)
	rm -f $(DESTDIR)$(appsdir)/chasm.desktop
	for s in $(ICON_SIZES); do \
	  rm -f $(DESTDIR)$(icondir)/$${s}x$${s}/apps/chasm.png; \
	done

# ---- macOS .app bundle ----
# Built on macOS, where sips and iconutil ship with the system. The version
# strings in Info.plist come from the VERSION file at bundle time.
APP       = $(BUILD)/Chasm.app
APP_BIN   = $(APP)/Contents/MacOS/chasm
APP_PLIST = $(APP)/Contents/Info.plist
APP_ICNS  = $(APP)/Contents/Resources/chasm.icns
SIPS     ?= sips
ICONUTIL ?= iconutil

.PHONY: bundle
bundle: $(APP)

$(APP): $(DEMO) packaging/Info.plist $(ICON_MASTER)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(DEMO) $(APP_BIN)
	sed 's/@VERSION@/'"`cat VERSION`"'/g' packaging/Info.plist > $(APP_PLIST)
	iconset=$(BUILD)/chasm.iconset; rm -rf $$iconset; mkdir -p $$iconset; \
	for s in 16 32 128 256 512; do \
	  d=$$((s * 2)); \
	  $(SIPS) -z $$s $$s $(ICON_MASTER) --out $$iconset/icon_$${s}x$${s}.png >/dev/null; \
	  $(SIPS) -z $$d $$d $(ICON_MASTER) --out $$iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done; \
	$(ICONUTIL) -c icns $$iconset -o $(APP_ICNS)
