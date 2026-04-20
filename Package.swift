// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kobaamd",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "kobaamd",
            targets: ["kobaamd"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", .upToNextMajor(from: "0.4.0"))
    ],
    targets: [
        .executableTarget(
            name: "kobaamd",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources",
            swiftSettings: [
                // Allow @testable import kobaamd in test targets
                .unsafeFlags(["-enable-testing"])
            ]
        ),
        .testTarget(
            name: "kobaamdTests",
            dependencies: [
                "kobaamd",
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Tests"
        )
    ]
)
