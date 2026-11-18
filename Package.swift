// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FreeClip",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FreeClip", targets: ["FreeClip"])],
    targets: [
        .executableTarget(name: "FreeClip", linkerSettings: [.linkedFramework("IOBluetooth")]),
        .testTarget(name: "FreeClipTests", dependencies: ["FreeClip"]),
        .testTarget(
            name: "FreeClipHardwareTests",
            dependencies: ["FreeClip"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        )
    ]
)
