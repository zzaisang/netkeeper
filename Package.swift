// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NetKeeper",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "NetKeeper", linkerSettings: [.linkedFramework("CoreWLAN")]),
        .testTarget(name: "NetKeeperTests", dependencies: ["NetKeeper"]),
    ],
    swiftLanguageModes: [.v5]
)
