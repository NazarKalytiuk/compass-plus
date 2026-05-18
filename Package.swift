// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MongoCompass",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/MongoKitten.git", from: "7.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "MongoCompass",
            dependencies: [
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MongoCompass"
        )
    ]
)
