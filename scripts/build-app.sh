#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
configuration="${1:-Debug}"
if (( $# > 0 )); then
    shift
fi

case "$configuration" in
    Debug|Release) ;;
    *)
        print -u2 "Usage: scripts/build-app.sh [Debug|Release] [xcodebuild-setting ...]"
        exit 64
        ;;
esac

exec xcodebuild \
    -project "$repo_root/LockTune.xcodeproj" \
    -scheme LockTune \
    -configuration "$configuration" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$repo_root/.build/XcodeDerivedData" \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
    "$@" \
    build
