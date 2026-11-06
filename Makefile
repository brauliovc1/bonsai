APP_NAME = Clean Claude
BUNDLE = build/$(APP_NAME).app
EXECUTABLE = CleanClaude
APP_PRODUCT = CleanClaudeApp
CLI = clean-claude
INSTALL_DIR = /Applications
BIN_DIR = $(HOME)/.local/bin

.PHONY: app run install test clean

# Release build of the app, wrapped in an ad-hoc signed bundle.
app:
	swift build -c release --product $(APP_PRODUCT)
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build -c release --show-bin-path)/$(APP_PRODUCT)" "$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(BUNDLE)"

# Runs the bundle's binary directly (not `open`), so CLEAN_CLAUDE_SETTINGS_DIR and
# CLEAN_CLAUDE_SCAN_ROOTS reach it during development.
run: app
	"$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"

# Replaces the installed app and puts the CLI in ~/.local/bin. No sudo.
install: app
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	swift build -c release --product $(CLI)
	mkdir -p "$(BIN_DIR)"
	cp "$$(swift build -c release --show-bin-path)/$(CLI)" "$(BIN_DIR)/$(CLI)"
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME).app and $(BIN_DIR)/$(CLI)"
	@case ":$$PATH:" in \
		*":$(BIN_DIR):"*) ;; \
		*) echo "$(BIN_DIR) is not on your PATH; add it, e.g.: echo 'export PATH=\"$(BIN_DIR):\$$PATH\"' >> ~/.zprofile" ;; \
	esac

test:
	swift test

clean:
	rm -rf build
	swift package clean
