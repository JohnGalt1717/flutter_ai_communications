// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_ai_communications_macos",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "flutter-ai-communications-macos", targets: ["flutter_ai_communications_macos"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "flutter_ai_communications_macos",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        )
    ]
)
