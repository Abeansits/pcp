.PHONY: project build test open clean unsigned sign install release

# Where `make install` puts the app. Override with PREFIX=/Applications.
PREFIX ?= $(HOME)/Applications
# Stable local identity. See scripts/ensure-signing-cert.sh.
SIGN_ID ?= PEA Local
SIGN_KEYCHAIN ?= $(HOME)/Library/Keychains/pea-signing.keychain-db
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
APP := build/Build/Products/Release/PEA.app

project:
	xcodegen generate

open: project
	open PEA.xcodeproj

build: project
	xcodebuild -project PEA.xcodeproj -scheme PEA -configuration Release \
		-allowProvisioningUpdates -derivedDataPath build build
	@echo "Built: $(APP)"

# No paid team. CloudKit entitlements need a provisioning profile, so they
# are omitted; iCloud sync stays off.
unsigned: project
	xcodebuild -project PEA.xcodeproj -scheme PEA -configuration Release \
		-derivedDataPath build \
		CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= build

sign: unsigned
	bash scripts/ensure-signing-cert.sh
	codesign --force --sign "$(SIGN_ID)" --keychain "$(SIGN_KEYCHAIN)" --timestamp=none "$(APP)"

install: sign
	mkdir -p "$(PREFIX)"
	ditto "$(APP)" "$(PREFIX)/PEA.app"
	codesign --force --sign "$(SIGN_ID)" --keychain "$(SIGN_KEYCHAIN)" --timestamp=none "$(PREFIX)/PEA.app"
	@echo "Installed: $(PREFIX)/PEA.app"
	@echo "Signed with \"$(SIGN_ID)\". Quit any running PEA, then open this copy."
	@test ! -d "$(PREFIX)/PCP.app" || echo "$(PREFIX)/PCP.app is the old name of this app. Quit it and move it to the Trash."

# Zip a signed app and publish it. NOTES is the release text.
#   make release NOTES="First release."
release: sign
	@test -n "$(NOTES)" || { echo 'Set NOTES="..." to the release text.'; exit 1; }
	rm -rf build/release
	mkdir -p build/release
	ditto "$(APP)" build/release/PEA.app
	codesign --force --sign "$(SIGN_ID)" --keychain "$(SIGN_KEYCHAIN)" --timestamp=none build/release/PEA.app
	ditto -c -k --keepParent build/release/PEA.app "build/PEA-$(VERSION).zip"
	gh release create "v$(VERSION)" "build/PEA-$(VERSION).zip" \
		--title "PEA $(VERSION)" \
		--notes "$(NOTES)"

test:
	cd Core && swift test

clean:
	rm -rf build Core/.build PEA.xcodeproj
