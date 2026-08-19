// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeamsLight",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TeamsLight", targets: ["TeamsLight"])],
    targets: [
        .executableTarget(name: "TeamsLight", path: "Sources"),
        .testTarget(name: "TeamsLightTests", dependencies: ["TeamsLight"], path: "Tests")
    ]
)
