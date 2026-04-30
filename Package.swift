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
        // Library target: all sources except @main entry point
        .target(
            name: "kobaamdLib",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            exclude: ["kobaamdApp"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-testing"])
            ]
        ),
        // Main executable: just the @main entry point
        .executableTarget(
            name: "kobaamd",
            dependencies: ["kobaamdLib"],
            path: "Sources/kobaamdApp"
        ),
        // Snapshot test runner executable
        .executableTarget(
            name: "snapshot-runner",
            dependencies: ["kobaamdLib"],
            path: "Tools"
        ),
        .testTarget(
            name: "kobaamdTests",
            dependencies: [
                "kobaamdLib",
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Tests",
            exclude: ["kobaamdTests/__Snapshots__"],
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
