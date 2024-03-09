
XRAY = Xray-core-1.8.8
PLATFORM ?= 

default: libxray

libxray: patched
	make -C $(XRAY) -f MakefileFramework $(PLATFORM)

patched:
	@for patchfile in patches/libxray*.patch; do \
		git apply --check $$patchfile; \
		if [ $$? == 0 ]; then \
			git apply --whitespace=fix $$patchfile || true; \
		fi; \
	done;
	touch $(XRAY)/patched

clean:
	@git checkout $(XRAY)
	@git clean -dxf $(XRAY)

install:

.PHONY: clean install build libxray
