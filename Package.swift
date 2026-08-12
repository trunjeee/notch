// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "notchbytrj",
    // macOS 15 for Translation.framework, which the translate tab runs on.
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "notchbytrj", targets: ["notchbytrj"])
    ],
    targets: [
        .executableTarget(
            name: "notchbytrj",
            path: "Sources/notchbytrj",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
