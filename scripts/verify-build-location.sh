#!/bin/zsh

set -euo pipefail

canonical_root="${SRCROOT:A}/.build/XcodeDerivedData/Build/Products"
expected_directory="$canonical_root/$CONFIGURATION"
actual_directory="${TARGET_BUILD_DIR:A}"

if [[ "$actual_directory" != "$expected_directory" ]]; then
    unexpected_product="$actual_directory/$FULL_PRODUCT_NAME"
    case "$FULL_PRODUCT_NAME" in
        "LockTune.app"|"LockTune Debug.app") ;;
        *)
            print -u2 "error: Refusing to clean unexpected product name: $FULL_PRODUCT_NAME"
            exit 1
            ;;
    esac
    if [[ "$actual_directory" == /* && "$actual_directory" != / && -d "$unexpected_product" ]]; then
        disposable_directory=false
        case "$actual_directory" in
            "${SRCROOT:A}/.build/"*|"${HOME:A}/Library/Developer/Xcode/DerivedData/"*|/private/tmp/*|/tmp/*)
                disposable_directory=true
                ;;
        esac
        payload_file=$(find "$unexpected_product" \( -type f -o -type l \) -print -quit)
        if [[ "$disposable_directory" == true || -z "$payload_file" ]]; then
            /bin/rm -rf -- "$unexpected_product"
        else
            print -u2 "error: Refusing to remove a populated app outside disposable build directories: $unexpected_product"
        fi
    fi
    print -u2 "error: LockTune app builds must use $expected_directory"
    print -u2 "error: Run scripts/build-app.sh $CONFIGURATION instead of creating another DerivedData copy."
    exit 1
fi
