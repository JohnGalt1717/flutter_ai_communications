// swift-tools-version: 6.0
// Flutter-free package so catalog policy can be tested without FlutterFramework.

import PackageDescription

let package = Package(
    name: "IosRoutePolicy",
    platforms: [
        .macOS("13.0"),
        .iOS("13.0"),
    ],
    products: [
        .library(name: "IosRoutePolicy", targets: ["IosRoutePolicy"]),
    ],
    targets: [
        .target(name: "IosRoutePolicy"),
        .testTarget(
            name: "IosRoutePolicyTests",
            dependencies: ["IosRoutePolicy"]
        ),
    ]
)
