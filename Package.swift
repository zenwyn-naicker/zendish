// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Zendish",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Zendish", targets: ["Zendish"]),
        .library(name: "ZendishCore", targets: ["ZendishCore"]),
    ],
    targets: [
        .target(name: "ZendishCore"),
        .target(name: "ZendishUI", dependencies: ["ZendishCore"]),
        .executableTarget(name: "Zendish", dependencies: ["ZendishUI"]),
        .testTarget(
            name: "ZendishCoreTests",
            dependencies: ["ZendishCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ZendishUITests", dependencies: ["ZendishUI"]),
    ]
)
