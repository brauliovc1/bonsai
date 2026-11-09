# Bonsai's Homebrew cask (PLAN §10.4). It belongs in the tap brauliovc1/homebrew-tap, made at the first release:
# copy this file to Casks/bonsai.rb there, and set version and sha256 from that release's SHA256SUMS.
cask "bonsai" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/brauliovc1/bonsai/releases/download/v#{version}/Bonsai-#{version}.dmg"
  name "Bonsai"
  desc "Menu bar app that finds and safely removes git worktrees and dev caches"
  homepage "https://github.com/brauliovc1/bonsai"

  depends_on macos: :sonoma

  app "Bonsai.app"

  # Bonsai isn't signed by Apple yet (no Developer ID, not notarized), so macOS would refuse to open the
  # downloaded app. This clears the download (quarantine) flag on the installed app only, which turns off that
  # one macOS check for Bonsai. Remove it once releases are signed and notarized.
  postflight_steps do
    run "/usr/bin/xattr", args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Bonsai.app"],
                          writable_paths: ["Bonsai.app"],
                          writable_base:  :appdir
  end

  zap trash: [
    "~/Library/Application Support/Bonsai",
    "~/Library/Application Support/clean-claude",
    "~/Library/Preferences/io.github.brauliovc1.bonsai.plist",
  ]
end
