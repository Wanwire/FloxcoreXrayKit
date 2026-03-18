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
	PATH="$(PWD)/.tmp/mobile:$(PATH):$(HOME)/go/bin" gomobile bind -target ios,iossimulator,macos,maccatalyst,appletvos,appletvsimulator,xros,xrsimulator -iosversion=16 -tvosversion=17 -x -o LibXrayGo.xcframework
	@if [ ! -d build ]; then mkdir build; fi
	@cp -r Sources build ;\
	cp Template/LocalPackage.template build/Package.swift ;\
	cp README.md build ;\
	rm -rf build/LibXrayGo.xcframework ;\
	mv LibXrayGo.xcframework build

clean:
	@rm -rf .tmp LibXrayGo.xcframework build


.PHONY: clean
