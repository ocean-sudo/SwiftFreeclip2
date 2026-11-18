#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEVELOPER_DIR="$(xcode-select -p)"
TESTING_MACROS="$DEVELOPER_DIR/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

cd "$ROOT"
if [[ -f "$TESTING_MACROS" ]]; then
    exec swift test --disable-xctest \
        -Xswiftc -load-plugin-library \
        -Xswiftc "$TESTING_MACROS" \
        "$@"
else
    exec swift test "$@"
fi
