// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TamaDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tama", targets: ["TamaDesktop"]),
    ],
    dependencies: [
        // Pinned by commit because it still names `wisent-errors` by revision;
        // the `wisent-components` requirement it carries is `exact: "0.7.1"`,
        // the same one this file names below.
        .package(
            url: "https://github.com/wisent-ai/wisent-desktop-auth.git",
            revision: "2ea0e92e1b48e6efb8d6668fc8f468fbe8f4fad4"
        ),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        .package(url: "https://github.com/wisent-ai/echo.git", exact: "0.1.2"),
        // By version: `wisent-components` 0.7.1 declares no dependencies, so a
        // version requirement is legal, and every consumer in one resolution —
        // this file and `wisent-desktop-auth` — has to name the same one.
        .package(
            url: "https://github.com/wisent-ai/wisent-components.git",
            exact: "0.7.1"
        ),
        .package(
            url: "https://github.com/wisent-ai/wisent-errors.git",
            revision: "b01a0c99766b5c6378ecdbf3921108420ba058f1"
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
