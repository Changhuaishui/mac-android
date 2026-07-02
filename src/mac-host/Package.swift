// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacHost",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "machost", targets: ["MacHostCLI"]),
        .executable(name: "MacHostApp", targets: ["MacHostApp"])
    ],
    targets: [
        .target(
            name: "MacHostKit",
            path: "Sources/MacHostKit"
        ),
        .executableTarget(
            name: "MacHostCLI",
            dependencies: ["MacHostKit"],
            path: "Sources/MacHostCLI"
        ),
        .executableTarget(
            name: "MacHostApp",
            dependencies: ["MacHostKit"],
            path: "Sources/MacHostApp"
        )
    ]
)
