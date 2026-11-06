#!/bin/bash
# Makes sure the runner's Swift can build Package.swift (swift-tools-version 6.0 needs Xcode 16 or newer).
# Keeps the default Xcode when its Swift is new enough; otherwise selects the newest stable Xcode installed
# on the runner, and fails if there is none.
#
# For trying it on a Mac: DRY_RUN=1 prints the xcode-select command instead of running it,
# MIN_SWIFT_MAJOR and XCODE_APPS_DIR change what counts as too old and where Xcode_*.app are looked for.
set -euo pipefail

min_major="${MIN_SWIFT_MAJOR:-6}"
apps_dir="${XCODE_APPS_DIR:-/Applications}"

swift_major() {
    swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+)\..*/\1/p' | head -n 1
}

is_new_enough() {
    [ -n "$1" ] && [ "$1" -ge "$min_major" ]
}

major="$(swift_major || true)"
if is_new_enough "$major"; then
    echo "Swift $major is new enough (need $min_major or newer); keeping the default Xcode."
    exit 0
fi
echo "Swift ${major:-unknown} is older than $min_major; looking for a newer Xcode."

# Xcode_16.4.app sorts by 16, 4. Names with anything but digits and dots (Xcode_26_beta_1.app) are skipped.
newest=""
for app in "$apps_dir"/Xcode_*.app; do
    [ -d "$app" ] || continue
    version="${app##*/Xcode_}"
    version="${version%.app}"
    case "$version" in
        "" | *[!0-9.]*) continue ;;
    esac
    echo "found $app"
    newest="$newest$version $app"$'\n'
done
newest="$(printf '%s' "$newest" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
if [ -z "$newest" ]; then
    echo "error: no stable Xcode_<version>.app in $apps_dir" >&2
    exit 1
fi
app="${newest#* }"

echo "Selecting $app"
if [ -n "${DRY_RUN:-}" ]; then
    echo "DRY_RUN: sudo xcode-select -s $app"
    exit 0
fi
sudo xcode-select -s "$app"

major="$(swift_major || true)"
if ! is_new_enough "$major"; then
    echo "error: Swift is still ${major:-unknown} after selecting $app" >&2
    exit 1
fi
echo "Swift $major"
