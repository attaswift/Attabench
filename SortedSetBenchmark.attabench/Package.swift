// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Benchmark",
    products: [
        .executable(name: "Benchmark", targets: ["Benchmark"])
    ],
    dependencies: [
        .package(url: "https://github.com/lorentey/Attabench", .branch("swift4")),
        .package(url: "https://github.com/lorentey/SipHash", .branch("swift4")),
        .package(url: "https://github.com/lorentey/BTree", .branch("5.x"))
    ],
    targets: [
        .target(name: "Benchmark", dependencies: ["Benchmarking", "BTree", "SipHash"], path: "Sources"),
    ],
    swiftLanguageVersions: [4]
)
