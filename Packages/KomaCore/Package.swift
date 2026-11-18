// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KomaCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "KomaCore", targets: ["KomaCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "KomaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .testTarget(
            name: "KomaCoreTests",
            dependencies: ["KomaCore"]
        )
    ]
)
