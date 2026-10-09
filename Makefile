.PHONY: project build test open clean

project:
	xcodegen generate

open: project
	open PCP.xcodeproj

build: project
	xcodebuild -project PCP.xcodeproj -scheme PCP -configuration Release \
		-allowProvisioningUpdates -derivedDataPath build build
	@echo "Built: build/Build/Products/Release/PCP.app"

test:
	cd Core && swift test

clean:
	rm -rf build Core/.build PCP.xcodeproj
