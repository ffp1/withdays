// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlidesFeature",
    defaultLocalization: "ja",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "SlidesFeature", targets: ["SlidesFeature"]),
    ],
    targets: [
        .target(
            name: "SlidesFeature",
            resources: [.process("Resources")],
            // The same language mode as the host app (WithDays).
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SlidesFeatureTests",
            dependencies: ["SlidesFeature"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
