// swift-tools-version: 5.9

import PackageDescription

// Sibling plugin packages resolve next to this one in Flutter's generated
// Swift package (same layout as FlutterFramework).
let package = Package(
    name: "flutter_ai_communications_webrtc",
    platforms: [
        .macOS("12.3")
    ],
    products: [
        .library(name: "flutter-ai-communications-webrtc", targets: ["flutter_ai_communications_webrtc"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(name: "flutter_webrtc", path: "../flutter_webrtc"),
        .package(name: "flutter_ai_communications_macos", path: "../flutter_ai_communications_macos"),
    ],
    targets: [
        .target(
            name: "flutter_ai_communications_webrtc",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "flutter-webrtc", package: "flutter_webrtc"),
                .product(name: "WebRTC", package: "flutter_webrtc"),
                .product(name: "flutter-ai-communications-macos", package: "flutter_ai_communications_macos"),
            ]
        ),
    ]
)
