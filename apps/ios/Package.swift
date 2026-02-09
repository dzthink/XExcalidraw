// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExcalidrawIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ExcalidrawIOS", targets: ["ExcalidrawIOS"])
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
