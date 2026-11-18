#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

swiftc \
    "$ROOT/Sources/FreeClip/Protocol/BatteryProtocol.swift" \
    "$ROOT/Sources/FreeClip/Protocol/DeviceState.swift" \
    "$ROOT/Tools/ProtocolSmoke.swift" \
    -o "$TEMP_DIR/protocol-smoke"
"$TEMP_DIR/protocol-smoke"
