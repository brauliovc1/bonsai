APP_NAME = Clean Claude
EXECUTABLE = CleanClaude
APP_PRODUCT = CleanClaudeApp
CLI = clean-claude
INSTALL_DIR = /Applications
BIN_DIR = $(HOME)/.local/bin

# The folder this Makefile is in, so `make -f <repo>/Makefile` run elsewhere never touches that folder's
# build/. Empty when it can't be worked out (a path with spaces given to -f); the `root` check then stops.
ROOT := $(shell cd -- "$(dir $(lastword $(MAKEFILE_LIST)))" 2>/dev/null && pwd -P)
BUNDLE = $(ROOT)/build/$(APP_NAME).app

# Paths that rm -rf and cp write to: never empty, never relative, and the app name never a path.
ifeq ($(strip $(APP_NAME)),)
$(error APP_NAME must not be empty)
endif
ifneq ($(findstring /,$(APP_NAME)),)
$(error APP_NAME must not contain "/" (is "$(APP_NAME)"))
endif
ifeq ($(filter /%,$(firstword $(INSTALL_DIR))),)
$(error INSTALL_DIR must be an absolute path (is "$(INSTALL_DIR)"))
endif
ifeq ($(filter /%,$(firstword $(BIN_DIR))),)
$(error BIN_DIR must be an absolute path (is "$(BIN_DIR)"))
endif

.PHONY: app run install test clean root

root:
	@test -n "$(ROOT)" && test -f "$(ROOT)/Package.swift" && test -f "$(ROOT)/Resources/Info.plist" || \
		{ echo "error: can't find the clean-claude folder; run make there, or make -C <folder>"; exit 1; }

# Release build of the app, wrapped in an ad-hoc signed bundle.
app: root
	swift build --package-path "$(ROOT)" -c release --product $(APP_PRODUCT)
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build --package-path "$(ROOT)" -c release --show-bin-path)/$(APP_PRODUCT)" "$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"
	cp "$(ROOT)/Resources/Info.plist" "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(BUNDLE)"

# Runs the bundle's binary directly (not `open`), so CLEAN_CLAUDE_SETTINGS_DIR and
# CLEAN_CLAUDE_SCAN_ROOTS reach it during development.
run: app
	"$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"

# Replaces the installed app and puts the CLI in ~/.local/bin. No sudo. Refuses while the installed copy runs.
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
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME).app and $(BIN_DIR)/$(CLI)"
	@case ":$$PATH:" in \
		*":$(BIN_DIR):"*) ;; \
		*) echo "$(BIN_DIR) is not on your PATH; add it, e.g.: echo 'export PATH=\"$(BIN_DIR):\$$PATH\"' >> ~/.zprofile" ;; \
	esac

test: root
	swift test --package-path "$(ROOT)"

clean: root
	rm -rf "$(ROOT)/build"
	swift package --package-path "$(ROOT)" clean
