// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OuvreCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OuvreCore", targets: ["OuvreCore"])],
    targets: [
        .target(name: "OuvreCore", path: "Sources/OuvreCore"),
        .testTarget(name: "OuvreCoreTests", dependencies: ["OuvreCore"], path: "Tests/OuvreCoreTests")
    ]
)
