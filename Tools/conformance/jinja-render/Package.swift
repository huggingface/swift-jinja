// swift-tools-version: 6.0

import Foundation
import PackageDescription

// The swift-jinja checkout that contains this package.
// SwiftPM names a path dependency after its directory,
// so the product reference uses the directory name.
let swiftJinja = URL(fileURLWithPath: Context.packageDirectory)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .standardizedFileURL

let package = Package(
    name: "jinja-render",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: swiftJinja.path),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "jinja-render",
            dependencies: [
                .product(name: "Jinja", package: swiftJinja.lastPathComponent),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        )
    ]
)
