// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TamaDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tama", targets: ["TamaDesktop"]),
    ],
    dependencies: [
        .package(url: "https://github.com/wisent-ai/wisent-desktop-auth.git", revision: "5ef1631"),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.1.0"),
        .package(url: "https://github.com/wisent-ai/echo.git", exact: "0.1.2"),
        .package(
            url: "https://github.com/wisent-ai/wisent-components.git",
            revision: "528a955"
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
