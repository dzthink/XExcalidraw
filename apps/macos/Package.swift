// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XExcalidraw",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "XExcalidraw", targets: ["XExcalidrawMac"])
    ],
    dependencies: [
        .package(path: "../shared")
    ],
    targets: [
        .executableTarget(
            name: "XExcalidrawMac",
            dependencies: [
                .product(name: "ExcalidrawShared", package: "shared")
            ],
            path: "Sources/ExcalidrawMac",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ExcalidrawMacTests",
            dependencies: ["XExcalidrawMac"]
        )
    ]
)
