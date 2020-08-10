// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "context-passing",
    products: [
        .library(
            name: "ContextPassing",
            targets: ["ContextPassing"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(
            name: "swift-baggage-context",
            url: "https://github.com/slashmo/gsoc-swift-baggage-context.git",
            from: "0.2.0"
        ),
    ],
    targets: [
        .target(
            name: "ContextPassing",
            dependencies: [
                .product(name: "Baggage", package: "swift-baggage-context"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "ContextPassingTests",
            dependencies: [
                .target(name: "ContextPassing"),
            ]
        ),
    ]
)
