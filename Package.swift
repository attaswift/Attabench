// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Attabench",
    products: [
        .library(name: "BenchmarkModel", targets: ["BenchmarkModel"]),
        .library(name: "BenchmarkRunner", targets: ["BenchmarkRunner"]),
        .library(name: "BenchmarkCharts", targets: ["BenchmarkCharts"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/Benchmarking", .branch("master")),
        .package(url: "https://github.com/attaswift/BigInt", .branch("swift4")),
        .package(url: "https://github.com/attaswift/SipHash", .branch("swift4")),
        .package(url: "https://github.com/attaswift/GlueKit", .branch("master")),
    ],
    targets: [
        .target(name: "BenchmarkModel", dependencies: ["BigInt", "GlueKit"], path: "BenchmarkModel"),
        .target(name: "BenchmarkRunner", dependencies: ["Benchmarking", "BenchmarkModel"], path: "BenchmarkRunner"),
        .target(name: "BenchmarkCharts", dependencies: ["BenchmarkModel"], path: "BenchmarkCharts"),
    ],
    swiftLanguageVersions: [4]
)
