// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Attabench",
    products: [
        .library(name: "Benchmarking", targets: ["Benchmarking"]),
    ],
    dependencies: [
        .package(url: "https://github.com/lorentey/BigInt", .branch("swift4")),
        .package(url: "https://github.com/lorentey/SipHash", .branch("swift4")),
        .package(url: "https://github.com/lorentey/BTree", .branch("5.x"))
    ],
    targets: [
        .target(name: "Benchmarking",
                dependencies: ["SipHash", "BigInt"],
                path: "Benchmarking"),
    ],
    swiftLanguageVersions: [4]
)
