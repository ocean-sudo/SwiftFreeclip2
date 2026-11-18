# Repository Guidelines

## Project Structure & Module Organization

`Package.swift` defines the `FreeClip` executable, its macOS 13 minimum, and its `IOBluetooth` framework dependency. Application code lives in `Sources/FreeClip/FreeClip.swift`: `Controller` handles paired-device discovery, RFCOMM communication, and battery frames; `FreeClipApp` defines the SwiftUI menu-bar interface. SwiftPM places build artifacts in `.build/`. There are currently no separate test or asset directories.

## Build, Test, and Development Commands

- `swift build` compiles the executable using Swift 6 tooling.
- `swift run FreeClip` builds and launches the menu-bar app on macOS.
- `swift test` runs SwiftPM tests after a test target has been added; none is currently defined.
- `swift package clean` removes SwiftPM build artifacts.

For device testing, pair a FreeClip device in macOS settings first, then use the app's discovery and refresh controls.

## Coding Style & Naming Conventions

Follow the existing Swift style: four-space indentation, `UpperCamelCase` for types, and `lowerCamelCase` for properties and methods. Keep UI state updates on the main actor and preserve the explicit handoff from Bluetooth delegate callbacks. Use descriptive names for protocol fields and keep user-facing status text consistent with the existing Chinese interface. No formatter or linter is configured.

## Testing Guidelines

When adding automated tests, create a SwiftPM test target in `Package.swift` and place tests under `Tests/FreeClipTests/`, using descriptive test names. Prioritize frame parsing, CRC validation, and malformed or partial input. Verify Bluetooth changes on paired hardware as well; automated tests cannot establish actual device compatibility. No coverage threshold is currently specified.

## Commits & Pull Requests

No Git history is available in this checkout, so an existing commit convention cannot be established. Use concise, imperative commit subjects describing the change. Pull requests should explain the behavior and validation performed, link related issues when available, and include screenshots for visible interface changes. Note the macOS version and device used for Bluetooth verification.
