// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExcalidrawMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ExcalidrawMac", targets: ["ExcalidrawMac"])
    ],
    dependencies: [
        .package(path: "../shared")
    ],
    targets: [
        .executableTarget(
            name: "ExcalidrawMac",
            dependencies: [
                .product(name: "ExcalidrawShared", package: "shared")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ExcalidrawMacTests",
            dependencies: ["ExcalidrawMac"]
        )
    ]
)
