// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IOS16ObservationSpike",
    platforms: [.iOS(.v16), .macOS(.v14), .tvOS(.v17)],
    products: [
        .library(name: "IOS16ObservationSpike", targets: ["IOS16ObservationSpike"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-perception.git", exact: "1.6.0")
    ],
    targets: [
        .target(
            name: "IOS16ObservationSpike",
            dependencies: [
                .product(name: "Perception", package: "swift-perception")
            ]
        ),
        .testTarget(
            name: "IOS16ObservationSpikeTests",
            dependencies: ["IOS16ObservationSpike"]
        )
    ]
)
