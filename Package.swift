// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Zendish",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZendishCore", targets: ["ZendishCore"]),
    ],
    targets: [
        .target(name: "ZendishCore"),
        .testTarget(
            name: "ZendishCoreTests",
            dependencies: ["ZendishCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
