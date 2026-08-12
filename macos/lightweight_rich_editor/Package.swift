// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "lightweight_rich_editor",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "lightweight-rich-editor", targets: ["lightweight_rich_editor"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "lightweight_rich_editor",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: []
        )
    ]
)
