// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TamaDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tama", targets: ["TamaDesktop"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/wisent-ai/wisent-desktop-auth.git",
            revision: "b47177c97fe93b44ec72c74dedde23f3e1abb090"
        ),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        .package(url: "https://github.com/wisent-ai/echo.git", exact: "0.1.2"),
        .package(
            url: "https://github.com/wisent-ai/wisent-components.git",
            revision: "e52cdda9036b8d44c7ebf51626fcde606e6859b6"
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
