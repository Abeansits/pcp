.PHONY: project build test open clean unsigned sign install release

# Where `make install` puts the app. Override with PREFIX=/Applications.
PREFIX ?= $(HOME)/Applications
# Stable local identity. See scripts/ensure-signing-cert.sh.
SIGN_ID ?= PCP Local
SIGN_KEYCHAIN ?= $(HOME)/Library/Keychains/pcp-signing.keychain-db
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
APP := build/Build/Products/Release/PCP.app

project:
	xcodegen generate

open: project
	open PCP.xcodeproj

build: project
	xcodebuild -project PCP.xcodeproj -scheme PCP -configuration Release \
		-allowProvisioningUpdates -derivedDataPath build build
	@echo "Built: $(APP)"

# No paid team. CloudKit entitlements need a provisioning profile, so they
# are omitted; iCloud sync stays off.
unsigned: project
	xcodebuild -project PCP.xcodeproj -scheme PCP -configuration Release \
		-derivedDataPath build \
		CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= build

sign: unsigned
	bash scripts/ensure-signing-cert.sh
	codesign --force --sign "$(SIGN_ID)" --keychain "$(SIGN_KEYCHAIN)" --timestamp=none "$(APP)"

install: sign
	mkdir -p "$(PREFIX)"
	ditto "$(APP)" "$(PREFIX)/PCP.app"
	codesign --force --sign "$(SIGN_ID)" --keychain "$(SIGN_KEYCHAIN)" --timestamp=none "$(PREFIX)/PCP.app"
	@echo "Installed: $(PREFIX)/PCP.app"
	@echo "Signed with \"$(SIGN_ID)\". Quit any running PCP, then open this copy."

# Zip a signed app and publish it. NOTES is the release text.
#   make release NOTES="First release."
release: sign
	@test -n "$(NOTES)" || { echo 'Set NOTES="..." to the release text.'; exit 1; }
	rm -rf build/release
	mkdir -p build/release
	ditto "$(APP)" build/release/PCP.app
	codesign --force --sign "$(SIGN_ID)" --keychain "$(SIGN_KEYCHAIN)" --timestamp=none build/release/PCP.app
	ditto -c -k --keepParent build/release/PCP.app "build/PCP-$(VERSION).zip"
	gh release create "v$(VERSION)" "build/PCP-$(VERSION).zip" \
		--title "PCP $(VERSION)" \
		--notes "$(NOTES)"

test:
	cd Core && swift test

clean:
	rm -rf build Core/.build PCP.xcodeproj
