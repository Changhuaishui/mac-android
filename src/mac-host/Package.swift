// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacHost",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "machost", targets: ["MacHost"])
    ],
    targets: [
        .executableTarget(
            name: "MacHost",
            path: "Sources/MacHost"
        )
    ]
)
