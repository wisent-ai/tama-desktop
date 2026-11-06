// swift-tools-version: 6.0
import PackageDescription

// Match the desktop package's Swift and macOS baseline without its app graph.
let package = Package(
    name: "TamaDesktopEmergencySwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .testTarget(
            name: "TamaDesktopEmergencySwitchTests",
            path: ".",
            sources: ["EmergencySwitchTests.swift"]
        )
    ]
)
