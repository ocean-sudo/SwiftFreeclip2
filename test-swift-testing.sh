#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEVELOPER_DIR="$(xcode-select -p)"
TESTING_MACROS="$DEVELOPER_DIR/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

if [[ ! -f "$TESTING_MACROS" ]]; then
    echo "Swift Testing macro plugin not found: $TESTING_MACROS" >&2
    exit 1
fi

cd "$ROOT"
exec swift test --disable-xctest \
    -Xswiftc -load-plugin-library \
    -Xswiftc "$TESTING_MACROS" \
    "$@"
