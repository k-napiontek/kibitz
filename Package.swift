// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kibitz",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "KibitzCore", targets: ["KibitzCore"])
    ],
    targets: [
        .target(name: "KibitzCore", resources: [.copy("Resources")]),
        .executableTarget(name: "KibitzApp", dependencies: ["KibitzCore"]),
        .executableTarget(name: "kibitz-check", dependencies: ["KibitzCore"]),
        .executableTarget(name: "kibitz-corpus", dependencies: ["KibitzCore"]),
        .testTarget(
            name: "KibitzCoreTests",
            dependencies: ["KibitzCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
