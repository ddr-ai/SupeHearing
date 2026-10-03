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
    dependencies: [],
    targets: [
        .target(
            name: "SuperHearing",
            dependencies: [],
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
