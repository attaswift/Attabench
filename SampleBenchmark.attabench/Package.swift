// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Benchmark",
    products: [
        .executable(name: "Benchmark", targets: ["Benchmark"])
    ],
    dependencies: [
        .package(url: "https://github.com/lorentey/Attabench", .branch("swift4"))
    ],
    targets: [
        .target(name: "Benchmark", dependencies: ["Benchmarking"], path: "Sources"),
    ],
    swiftLanguageVersions: [4]
)
