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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", revision: "f97df585296977d8fcaf644cbde567151d1367b8"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", revision: "f969cd3ae3f9fbd4e43205431d0ae286014c05b5")
    ],
    targets: [
        .executableTarget(
            name: "kobaamd",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
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
                .unsafeFlags(["-enable-testing"]),
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
