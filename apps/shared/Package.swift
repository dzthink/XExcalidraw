// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExcalidrawShared",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ExcalidrawShared", targets: ["ExcalidrawShared"])
    ],
    targets: [
        .target(
            name: "ExcalidrawShared"
        ),
        .testTarget(
            name: "ExcalidrawSharedTests",
            dependencies: ["ExcalidrawShared"]
        )
    ]
)
