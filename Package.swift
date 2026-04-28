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
        .package(url: "https://github.com/apple/swift-markdown.git", .upToNextMajor(from: "0.4.0")),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "kobaamd",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
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
            path: "Tests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
