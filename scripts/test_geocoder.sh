#!/bin/sh
# Native macOS regression tests; no device or iOS SDK is needed.
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir=${1:-"$repo_dir/Sources"}
case "$source_dir" in /*) ;; *) source_dir="$PWD/$source_dir" ;; esac
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/pf-geocoder-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
mkdir -p "$test_dir/zh-Hans.lproj" "$test_dir/en.lproj"
cp "$repo_dir/Resources/zh-Hans.lproj/Localizable.strings" "$test_dir/zh-Hans.lproj/Localizable.strings"
cp "$repo_dir/Resources/en.lproj/Localizable.strings" "$test_dir/en.lproj/Localizable.strings"
clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -lsqlite3 \
    -I "$source_dir" "$repo_dir/tests/geocoder_tests.m" \
    "$source_dir/PFOfflineGeocoder.m" -o "$test_dir/geocoder-tests"
"$test_dir/geocoder-tests" "$repo_dir/Resources/GeoNamesCities.sqlite3" -AppleLanguages "(${PF_TEST_LANGUAGE:-zh-Hans})"
