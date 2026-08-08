// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lightweight_rich_editor",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_14)
    ],
    products: [
        .library(name: "lightweight-rich-editor", targets: ["lightweight_rich_editor"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "lightweight_rich_editor",
            path: "darwin"
        )
    ]
)
