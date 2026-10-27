// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TamaDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tama", targets: ["TamaDesktop"])
    ],
    dependencies: [
        // By version now that its own dependencies are tagged: 0.3.7 names
        // `wisent-components` as `exact: "0.9.1"`, the requirement this file
        // names below, and `wisent-errors` as `exact: "1.1.0"`, which yields
        // to the revision this file names (1.1.0 is its ancestor). 0.3.6
        // cannot build against that catalogue: its classifier misses `.refused`.
        .package(
            url: "https://github.com/wisent-ai/wisent-desktop-auth.git",
            exact: "0.3.7"
        ),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        .package(url: "https://github.com/wisent-ai/echo.git", exact: "0.3.0"),
        // By version: `wisent-components` 0.9.1 declares no dependencies, so a
        // version requirement is legal, and every consumer in one resolution —
        // this file and `wisent-desktop-auth` — has to name the same one.
        .package(
            url: "https://github.com/wisent-ai/wisent-components.git",
            exact: "0.9.1"
        ),
        // By revision: the reporter's settlement callback (a report says when
        // it has settled and why it did not land) is published on `main` and
        // in no tag yet. A root revision requirement overrides the version
        // requirement `wisent-desktop-auth` names; two revisions would refuse.
        .package(
            url: "https://github.com/wisent-ai/wisent-errors.git",
            revision: "0a2fb881a6bb74d97c6a1f901638dd53a964a43d"
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
        // The review answer and its failures, decoded and kept by the real
        // client against the declared backend, and a refused cleanup counted
        // in the real failure intake: tests/review-diagnostics.
        .testTarget(
            name: "TamaDesktopReviewDiagnosticsTests",
            dependencies: [
                "TamaDesktop",
                .product(name: "WisentAuth", package: "wisent-desktop-auth"),
                .product(name: "WisentErrors", package: "wisent-errors"),
            ],
            path: "tests/review-diagnostics"
        ),
    ]
)
