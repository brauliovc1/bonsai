APP_NAME = Bonsai
EXECUTABLE = Bonsai
APP_PRODUCT = CleanClaudeApp
CLI = bonsai
# The old name of the CLI: `make install` leaves a link by that name to it, so old scripts keep working.
OLD_CLI = clean-claude
INSTALL_DIR = /Applications
BIN_DIR = $(HOME)/.local/bin
# Both slices of a release build; `make universal` fails if either is missing from the result.
ARCHS = arm64 x86_64
# "-" is an ad-hoc signature (PLAN decision 3). To sign with a Developer ID later, pass SIGN_IDENTITY and
# CODESIGN_FLAGS on the command line (see the commented steps in .github/workflows/release.yml).
SIGN_IDENTITY = -
CODESIGN_FLAGS =
CODESIGN = codesign --force $(CODESIGN_FLAGS) --sign "$(SIGN_IDENTITY)"

# Paths that rm -rf, rm -f, cp and ln write to: never empty, never relative, and the names never paths. Checked
# before the first $(shell ...) below, so a bad destination is refused at once, before git or anything else runs.
ifeq ($(strip $(APP_NAME)),)
$(error APP_NAME must not be empty)
endif
ifneq ($(findstring /,$(APP_NAME)),)
$(error APP_NAME must not contain "/" (is "$(APP_NAME)"))
endif
ifeq ($(strip $(OLD_CLI)),)
$(error OLD_CLI must not be empty)
endif
ifneq ($(findstring /,$(OLD_CLI)),)
$(error OLD_CLI must not contain "/" (is "$(OLD_CLI)"))
endif
ifeq ($(filter /%,$(firstword $(INSTALL_DIR))),)
$(error INSTALL_DIR must be an absolute path (is "$(INSTALL_DIR)"))
endif
ifeq ($(filter /%,$(firstword $(BIN_DIR))),)
$(error BIN_DIR must be an absolute path (is "$(BIN_DIR)"))
endif

# The folder this Makefile is in, so `make -f <repo>/Makefile` run elsewhere never touches that folder's
# build/. Empty when it can't be worked out (a path with spaces given to -f); the `root` check then stops.
ROOT := $(shell cd -- "$(dir $(lastword $(MAKEFILE_LIST)))" 2>/dev/null && pwd -P)
BUNDLE = $(ROOT)/build/$(APP_NAME).app
DIST = $(ROOT)/dist
# swift-argument-parser is linked into the CLI only (the app binary has none of it), so this file goes
# next to bonsai in the zip and, as a courtesy, next to the app in the dmg.
NOTICES = $(ROOT)/THIRD_PARTY_NOTICES
# The app icon, made by `make icon` from Resources/Icon/MakeIcon.swift and the menu-bar glyph's shape. It is
# committed, so building the app never needs the generator.
ICNS = $(ROOT)/Resources/AppIcon.icns

# Written into the assembled bundle's Info.plist, never into Resources/Info.plist. A release passes VERSION
# (the tag without its "v"); otherwise it comes from git. `version-check` stops anything unusable.
VERSION ?= $(shell git -C "$(ROOT)" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')
BUILD ?= $(shell git -C "$(ROOT)" rev-list --count HEAD 2>/dev/null)
VERSION := $(VERSION)
BUILD := $(BUILD)
# The check reads them from the environment, so an odd value is never pasted into a shell command line.
export VERSION BUILD

UNIVERSAL_BUILD = swift build --package-path "$(ROOT)" -c release $(foreach arch,$(ARCHS),--arch $(arch))
UNIVERSAL_CLI = $(ROOT)/build/cli/$(CLI)
DMG = $(DIST)/$(APP_NAME)-$(VERSION).dmg
CLI_ZIP = $(DIST)/$(CLI)-$(VERSION)-macos.zip

# Wraps a built binary in the .app bundle. Shell steps for a recipe that has set `bin` to the folder SwiftPM
# put the products in. The version numbers go into the bundle's copy of Info.plist; signing comes last, so
# the signature covers them.
define bundle_app
test -f "$(ICNS)" || { echo "error: $(ICNS) is missing; run make icon"; exit 1; }; \
rm -rf "$(BUNDLE)"; \
mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"; \
cp "$$bin/$(APP_PRODUCT)" "$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"; \
cp "$(ROOT)/Resources/Info.plist" "$(BUNDLE)/Contents/Info.plist"; \
cp "$(ICNS)" "$(BUNDLE)/Contents/Resources/AppIcon.icns"; \
plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(BUNDLE)/Contents/Info.plist"; \
plutil -replace CFBundleVersion -string "$(BUILD)" "$(BUNDLE)/Contents/Info.plist"; \
plutil -lint -s "$(BUNDLE)/Contents/Info.plist"; \
$(CODESIGN) "$(BUNDLE)"
endef

.PHONY: app run install test clean root version-check universal dmg cli-zip checksums dist icon

root:
	@test -n "$(ROOT)" && test -f "$(ROOT)/Package.swift" && test -f "$(ROOT)/Resources/Info.plist" || \
		{ echo "error: can't find the Bonsai folder; run make there, or make -C <folder>"; exit 1; }

version-check:
	@LC_ALL=C; case "$$VERSION" in \
		""|[!A-Za-z0-9]*|*[!A-Za-z0-9._+-]*) \
			echo "error: VERSION must be letters, digits and . _ + - and start with a letter or digit (is \"$$VERSION\"); pass VERSION=1.2.3"; exit 1;; \
	esac; \
	case "$$BUILD" in \
		""|*[!0-9]*) echo "error: BUILD must be a number (is \"$$BUILD\"); pass BUILD=1"; exit 1;; \
	esac

# Release build of the app for this Mac's architecture, wrapped in an ad-hoc signed bundle.
app: root version-check
	swift build --package-path "$(ROOT)" -c release --product $(APP_PRODUCT)
	@set -e; bin="$$(swift build --package-path "$(ROOT)" -c release --show-bin-path)"; $(bundle_app)

# Runs the bundle's binary directly (not `open`), so BONSAI_SETTINGS_DIR and
# BONSAI_SCAN_ROOTS reach it during development.
run: app
	"$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"

# Replaces the installed app and puts the CLI in ~/.local/bin, with $(OLD_CLI) as a link to it. No sudo. Refuses
# while the installed copy runs.
install: app
	@for pid in $$(pgrep -x "$(EXECUTABLE)"); do \
		case "$$(ps -o command= -p $$pid)" in \
			"$(INSTALL_DIR)/$(APP_NAME).app/"*) \
				echo "error: $(APP_NAME) is running from $(INSTALL_DIR) (pid $$pid); quit it first"; exit 1;; \
		esac; \
	done
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	swift build --package-path "$(ROOT)" -c release --product $(CLI)
	mkdir -p "$(BIN_DIR)"
	rm -f "$(BIN_DIR)/$(CLI)"
	cp "$$(swift build --package-path "$(ROOT)" -c release --show-bin-path)/$(CLI)" "$(BIN_DIR)/$(CLI)"
	rm -f "$(BIN_DIR)/$(OLD_CLI)"
	ln -s "$(CLI)" "$(BIN_DIR)/$(OLD_CLI)"
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME).app and $(BIN_DIR)/$(CLI) ($(BIN_DIR)/$(OLD_CLI) is a link to it)"
	@case ":$$PATH:" in \
		*":$(BIN_DIR):"*) ;; \
		*) echo "$(BIN_DIR) is not on your PATH; add it, e.g.: echo 'export PATH=\"$(BIN_DIR):\$$PATH\"' >> ~/.zprofile" ;; \
	esac

test: root
	swift test --package-path "$(ROOT)"

# Draws the icon at every size iconutil wants (Resources/Icon/MakeIcon.swift compiled with the glyph's shape,
# Sources/CleanClaudeApp/BonsaiGlyph.swift) and writes Resources/AppIcon.icns. Commit the result.
icon: root
	@set -e; \
	work="$(ROOT)/build/icon"; \
	rm -rf "$$work"; \
	mkdir -p "$$work"; \
	swiftc -swift-version 6 -parse-as-library -O -o "$$work/make-icon" \
		"$(ROOT)/Resources/Icon/MakeIcon.swift" "$(ROOT)/Sources/CleanClaudeApp/BonsaiGlyph.swift"; \
	"$$work/make-icon" "$$work/AppIcon.iconset"; \
	iconutil -c icns -o "$(ICNS)" "$$work/AppIcon.iconset"; \
	echo "Wrote $(ICNS)"

# The app and the CLI built for both architectures: build/$(APP_NAME).app and build/cli/$(CLI), ad-hoc signed.
universal: root version-check
	$(UNIVERSAL_BUILD) --product $(APP_PRODUCT)
	$(UNIVERSAL_BUILD) --product $(CLI)
	@set -e; \
	has_archs() { \
		got="$$(lipo -archs "$$1")"; \
		for want in $(ARCHS); do \
			case " $$got " in *" $$want "*) ;; *) echo "error: $$1 has no $$want slice (it has: $$got)"; exit 1;; esac; \
		done; \
		echo "$$1: $$got"; \
	}; \
	bin="$$($(UNIVERSAL_BUILD) --show-bin-path)"; \
	$(bundle_app); \
	has_archs "$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"; \
	rm -rf "$(ROOT)/build/cli"; \
	mkdir -p "$(ROOT)/build/cli"; \
	cp "$$bin/$(CLI)" "$(UNIVERSAL_CLI)"; \
	$(CODESIGN) "$(UNIVERSAL_CLI)"; \
	has_archs "$(UNIVERSAL_CLI)"

# The disk image people drag the app out of: the app, a link to /Applications and the notices. hdiutil sometimes fails
# with "Resource busy" on CI runners, so it gets three tries.
dmg: universal
	@set -e; \
	stage="$(ROOT)/build/dmg"; \
	rm -rf "$$stage"; \
	mkdir -p "$$stage" "$(DIST)"; \
	ditto "$(BUNDLE)" "$$stage/$(APP_NAME).app"; \
	ln -s /Applications "$$stage/Applications"; \
	cp "$(NOTICES)" "$$stage/THIRD_PARTY_NOTICES"; \
	rm -f "$(DMG)"; \
	for try in 1 2 3; do \
		hdiutil create -volname "$(APP_NAME)" -srcfolder "$$stage" -ov -format UDZO "$(DMG)" && break; \
		test $$try -lt 3 || exit 1; \
		echo "hdiutil failed; trying again in 5 seconds"; \
		sleep 5; \
	done; \
	hdiutil verify -quiet "$(DMG)"; \
	rm -rf "$$stage"

# The CLI and THIRD_PARTY_NOTICES, side by side at the top of the zip.
cli-zip: universal
	@set -e; \
	mkdir -p "$(DIST)"; \
	rm -f "$(CLI_ZIP)"; \
	cp "$(NOTICES)" "$(ROOT)/build/cli/THIRD_PARTY_NOTICES"; \
	cd "$(ROOT)/build/cli" && zip -q -X "$(CLI_ZIP)" "$(CLI)" THIRD_PARTY_NOTICES

# Names the files by their bare names, so `shasum -a 256 -c SHA256SUMS` works from inside dist/.
checksums: dmg cli-zip
	@set -e; \
	cd "$(DIST)"; \
	rm -f SHA256SUMS; \
	shasum -a 256 "$(notdir $(DMG))" "$(notdir $(CLI_ZIP))" > SHA256SUMS; \
	cat SHA256SUMS

# Everything a release uploads: dist/$(APP_NAME)-<version>.dmg, dist/$(CLI)-<version>-macos.zip, dist/SHA256SUMS.
dist: checksums
	@echo "Built $(VERSION) in $(DIST)"

clean: root
	rm -rf "$(ROOT)/build" "$(ROOT)/dist"
	swift package --package-path "$(ROOT)" clean
