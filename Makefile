
DESTDIR ?= build
PACKAGE ?= XrayKit
PLATFORM ?= all

default: $(DESTDIR)/$(PACKAGE)

$(DESTDIR)/$(PACKAGE): export DESTDIR := $(CURDIR)/$(DESTDIR)
$(DESTDIR)/$(PACKAGE): $(DESTDIR)/LibXray.xcframework

$(DESTDIR)/LibXray.xcframework: export PLATFORM := $(PLATFORM)
$(DESTDIR)/LibXray.xcframework: export DESTDIR := $(CURDIR)/$(DESTDIR)
$(DESTDIR)/LibXray.xcframework:
	$(MAKE) -C thirdparty libxray
 
local: $(DESTDIR)/$(PACKAGE)
	rm -rf "$(DESTDIR)/$(PACKAGE)"
	mkdir -p "$(DESTDIR)/$(PACKAGE)/xcframeworks"
	cp -r "$(DESTDIR)/LibXray.xcframework" "$(DESTDIR)/$(PACKAGE)/xcframeworks/"
	cp "Templates/Package.local.template" "$(DESTDIR)/$(PACKAGE)/Package.swift"
	cp -r "Sources" "$(DESTDIR)/$(PACKAGE)/"
	cp README.md "$(DESTDIR)/$(PACKAGE)/"

clean:
	$(MAKE) -C thirdparty clean
	@rm -rf "$(DESTDIR)" "$(PACKAGE)"

.PHONY: all clean local

