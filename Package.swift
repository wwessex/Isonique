// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Isonique",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Isonique", targets: ["Isonique"])],
    targets: [
        .target(name: "IsoniqueCore"),
        .executableTarget(name: "Isonique", dependencies: ["IsoniqueCore"]),
        .testTarget(name: "IsoniqueCoreTests", dependencies: ["IsoniqueCore"]),
        .testTarget(name: "IsoniqueTests", dependencies: ["Isonique", "IsoniqueCore"])
    ]
)
