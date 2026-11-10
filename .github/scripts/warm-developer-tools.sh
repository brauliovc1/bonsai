#!/bin/bash
# Runs each developer tool lookup once before the build and prints how long it took, so a slow runner shows up
# here and not as timeouts in the tests.
#
# /usr/bin/git and /usr/bin/make are xcrun shims: on a cold runner each call first runs `xcodebuild -find`, and
# xcrun caches the answer per SDKROOT and developer folder. `swift test` gives the tests
# SDKROOT=$(xcrun --sdk macosx --show-sdk-path), so the shims are also run once with that. Fails at the end if
# any command failed.
set -euo pipefail

now() {
    perl -MTime::HiRes=time -e 'printf "%.3f", time'
}

failed=0

# Prints the seconds, the command and the first line of its output.
step() {
    local start output status=0
    start="$(now)"
    output="$("$@" 2>&1)" || status=$?
    perl -e 'printf "%7.2fs  %s\n", $ARGV[0] - $ARGV[1], $ARGV[2]' "$(now)" "$start" "$*"
    echo "          ${output%%$'\n'*}"
    if [ "$status" -ne 0 ]; then
        echo "          exit $status" >&2
        failed=1
    fi
}

step xcrun --find git
step /usr/bin/git --version
step xcrun --find swift
step xcrun --show-sdk-path
step /usr/bin/make --version

sdk="$(xcrun --sdk macosx --show-sdk-path)"
echo "As the tests run them, with SDKROOT=$sdk:"
step env SDKROOT="$sdk" xcrun --find git
step env SDKROOT="$sdk" /usr/bin/git --version
step env SDKROOT="$sdk" /usr/bin/make --version

exit "$failed"
