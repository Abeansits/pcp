.PHONY: project build test open clean unsigned install

# Where `make install` puts the ad-hoc app. Override with PREFIX=/Applications.
PREFIX ?= $(HOME)/Applications

project:
	xcodegen generate

open: project
	open PCP.xcodeproj

build: project
	xcodebuild -project PCP.xcodeproj -scheme PCP -configuration Release \
		-allowProvisioningUpdates -derivedDataPath build build
	@echo "Built: build/Build/Products/Release/PCP.app"

# No paid team. CloudKit entitlements need a provisioning profile, so they
# are omitted; iCloud sync stays off. Ad-hoc sign so the app can be copied
# out of the build directory.
unsigned: project
	xcodebuild -project PCP.xcodeproj -scheme PCP -configuration Release \
		-derivedDataPath build \
		CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= build
	codesign --force --sign - build/Build/Products/Release/PCP.app

install: unsigned
	mkdir -p "$(PREFIX)"
	ditto build/Build/Products/Release/PCP.app "$(PREFIX)/PCP.app"
	codesign --force --sign - "$(PREFIX)/PCP.app"
	@echo "Installed: $(PREFIX)/PCP.app"
	@echo "Quit any running PCP from its menu bar, then open this copy."

test:
	cd Core && swift test

clean:
	rm -rf build Core/.build PCP.xcodeproj
