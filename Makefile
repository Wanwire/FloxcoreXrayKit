FRAMEWORK_FILENAME := LibXrayGo.xcframework
IOS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.iOS\(\.v([0-9]+)\)/' Package.swift)
MACOS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.macOS\(\.v([0-9]+)\)/' Package.swift)
TVOS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.tvOS\(\.v([0-9]+)\)/' Package.swift)
XROS_VERSION := $(shell perl -0ne 'print "$$1.0" if /\.visionOS\(\.v([0-9]+)\)/' Package.swift)
GOMOBILE_TARGETS := ios,iossimulator,macos,maccatalyst,appletvos,appletvsimulator,xros,xrsimulator
GOMOBILE_BUILD_FLAGS := -target $(GOMOBILE_TARGETS) -iosversion=$(IOS_VERSION) -macosversion=$(MACOS_VERSION) -tvosversion=$(TVOS_VERSION) -xrosversion=$(XROS_VERSION)

default:
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

clean:
	@rm -rf .tmp $(FRAMEWORK_FILENAME) build


.PHONY: clean
