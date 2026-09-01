// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TamaDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tama", targets: ["TamaDesktop"]),
    ],
    dependencies: [
        // By version now that its own dependencies are tagged: 0.4.0 names
        // `wisent-errors` as `exact: "1.0.0"` and `wisent-components` as
        // `exact: "0.8.1"`, the same two requirements this file names below.
        .package(
            url: "https://github.com/wisent-ai/wisent-desktop-auth.git",
            exact: "0.4.0"
        ),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        .package(url: "https://github.com/wisent-ai/echo.git", exact: "0.1.2"),
        // By version: `wisent-components` 0.8.1 declares no dependencies, so a
        // version requirement is legal, and every consumer in one resolution —
        // this file and `wisent-desktop-auth` — has to name the same one.
        .package(
            url: "https://github.com/wisent-ai/wisent-components.git",
            exact: "0.8.1"
        ),
        // Tag 1.0.0 is the tree this file pinned by commit before
        // `wisent-errors` was taggable; it declares no dependencies, so an
        // exact version requirement is legal for every consumer.
        .package(
            url: "https://github.com/wisent-ai/wisent-errors.git",
            exact: "1.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "TamaDesktop",
            dependencies: [
                .product(name: "WisentAuth", package: "wisent-desktop-auth"),
                .product(name: "WisentDesktopUpdate", package: "wisent-desktop-update"),
                .product(name: "WisentOnboarding", package: "echo"),
                .product(name: "WisentDesignSystem", package: "wisent-components"),
                .product(name: "WisentErrors", package: "wisent-errors"),
            ],
            path: "Sources/TamaDesktop",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TamaDesktopTests",
            dependencies: ["TamaDesktop"],
            path: "Tests/TamaDesktopTests"
        ),
    ]
)
