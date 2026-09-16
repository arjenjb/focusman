APP_NAME := Focusman
BUNDLE_ID := nl.arjenjb.focusman
BUNDLE := build/$(APP_NAME).app
SWIFT_BUILD_FLAGS ?=
BIN = $(shell swift build -c release $(SWIFT_BUILD_FLAGS) --show-bin-path)/$(APP_NAME)
# GoReleaser supplies the numeric tag version before the bundle is signed.
VERSION ?=

# Override with a Developer ID / Apple Development identity when needed.
# Local builds use ad-hoc signing ("-").
SIGN_IDENTITY ?= -
CLI_DIR ?= $(HOME)/.local/bin

.PHONY: all build bundle run install install-cli notarize clean

all: bundle

build:
	swift build -c release $(SWIFT_BUILD_FLAGS)

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	if [ -n "$(VERSION)" ]; then \
		plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(BUNDLE)/Contents/Info.plist && \
		plutil -replace CFBundleVersion -string "$(VERSION)" $(BUNDLE)/Contents/Info.plist; \
	fi
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/focusman $(BUNDLE)/Contents/Resources/focusman
	chmod +x $(BUNDLE)/Contents/Resources/focusman
	codesign --force --options runtime $(if $(filter -,$(SIGN_IDENTITY)),,--timestamp) --identifier $(BUNDLE_ID) --sign "$(SIGN_IDENTITY)" $(BUNDLE)

	ln -sfn $(APP_NAME).app/Contents/Resources/focusman build/focusman

run: bundle
	-pkill -x $(APP_NAME) || true
	open $(BUNDLE)

install: bundle
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(BUNDLE) /Applications/

install-cli: install
	mkdir -p "$(CLI_DIR)"
	ln -sf /Applications/$(APP_NAME).app/Contents/Resources/focusman "$(CLI_DIR)/focusman"

# Notarize an already-built Developer ID-signed bundle without rebuilding it.
notarize:
	bash Scripts/notarize.sh "$(BUNDLE)"

clean:
	rm -rf .build build
