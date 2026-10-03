// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperHearing",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SuperHearing",
            targets: ["SuperHearing"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "SuperHearing",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "SuperHearing",
            exclude: [
                "Resources/Info.plist",
                "Resources/SuperHearing.entitlements",
                "Resources/ExportOptions.plist",
                "Resources/Assets.xcassets",
                "Resources/Models"
            ]
        ),
        .testTarget(
            name: "SuperHearingTests",
            dependencies: ["SuperHearing"],
            path: "SuperHearingTests"
        ),
    ]
)
