// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XExcalidraw",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .executable(name: "XExcalidraw", targets: ["ExcalidrawIOS"])
    ],
    dependencies: [
        .package(path: "../shared")
    ],
    targets: [
        .executableTarget(
            name: "ExcalidrawIOS",
            dependencies: [
                .product(name: "ExcalidrawShared", package: "shared")
            ],
            path: "Sources/ExcalidrawIOS",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ExcalidrawIOSTests",
            dependencies: ["ExcalidrawIOS"]
        )
    ]
)
