FRAMEWORK_FILENAME := LibXrayGo.xcframework
IOS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.iOS\(\.v([0-9]+)\)/' Package.swift)
MACOS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.macOS\(\.v([0-9]+)\)/' Package.swift)
TVOS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.tvOS\(\.v([0-9]+)\)/' Package.swift)
XROS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.visionOS\(\.v([0-9]+)\)/' Package.swift)
GOMOBILE_TARGETS := ios,iossimulator,macos,maccatalyst,appletvos,appletvsimulator,xros,xrsimulator
GOMOBILE_BUILD_FLAGS := -target $(GOMOBILE_TARGETS) -iosversion=$(IOS_VERSION) -macosversion=$(MACOS_VERSION) -tvosversion=$(TVOS_VERSION) -xrosversion=$(XROS_VERSION)

XRAY_CORE_DIR := .tmp/xray-core

default: xray-core
	@if [ ! -d ".tmp/mobile" ]; then \
		  mkdir .tmp || true ;\
                  git clone https://go.googlesource.com/mobile .tmp/mobile ;\
                  pushd .tmp/mobile ;\
                  git apply ../../patches/gomobile.patch ;\
                  go build -o gomobile ./cmd/gomobile ;\
                  chmod +x gomobile ;\
                  popd ;\
	fi
	PATH="$(PWD)/.tmp/mobile:$(PATH):$(HOME)/go/bin" gomobile init
	PATH="$(PWD)/.tmp/mobile:$(PATH):$(HOME)/go/bin" gomobile bind $(GOMOBILE_BUILD_FLAGS) -x -o $(FRAMEWORK_FILENAME)
	@if [ ! -d build ]; then mkdir build; fi
	@cp -r Sources build ;\
	cp Template/LocalPackage.template build/Package.swift ;\
	cp README.md build ;\
	rm -rf build/$(FRAMEWORK_FILENAME) ;\
	mv $(FRAMEWORK_FILENAME) build

# The xray-core version that go.mod requires, with the patches in patches/xray-core.
# go.mod replaces xray-core with this directory.
xray-core:
	@set -e ;\
	VERSION=$$(awk '$$1 == "github.com/xtls/xray-core" && $$2 ~ /^v/ { print $$2 }' go.mod) ;\
	test -n "$$VERSION" ;\
	SOURCE=$$(cd "$$(mktemp -d)" && go mod download -json "github.com/xtls/xray-core@$$VERSION" | awk -F '"' '$$2 == "Dir" { print $$4 }') ;\
	test -d "$$SOURCE" ;\
	rm -rf $(XRAY_CORE_DIR) ;\
	mkdir -p .tmp ;\
	cp -R "$$SOURCE" $(XRAY_CORE_DIR) ;\
	chmod -R u+w $(XRAY_CORE_DIR) ;\
	for PATCH in patches/xray-core/*.patch; do \
		patch -d $(XRAY_CORE_DIR) -p1 --forward --batch --quiet < "$$PATCH" ;\
	done ;\
	echo "Patched xray-core $$VERSION in $(XRAY_CORE_DIR)"

clean:
	@rm -rf .tmp $(FRAMEWORK_FILENAME) build


.PHONY: clean xray-core
