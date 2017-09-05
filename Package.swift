// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Attabench",
    products: [
        .library(name: "Benchmarking", targets: ["Benchmarking", "BenchmarkIPC"]),
        .library(name: "BenchmarkModel", targets: ["BenchmarkModel"]),
        .library(name: "BenchmarkRunner", targets: ["BenchmarkRunner", "BenchmarkIPC"]),
        .library(name: "BenchmarkCharts", targets: ["BenchmarkCharts"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/OptionParser", .branch("master")),
        .package(url: "https://github.com/attaswift/BigInt", .branch("swift4")),
        .package(url: "https://github.com/attaswift/SipHash", .branch("swift4")),
        .package(url: "https://github.com/attaswift/GlueKit", .branch("master")),
    ],
    targets: [
        .target(name: "BenchmarkIPC", path: "BenchmarkIPC"),
        .target(name: "Benchmarking", dependencies: ["OptionParser", "BenchmarkIPC"], path: "Benchmarking"),
        .target(name: "BenchmarkModel", dependencies: ["BigInt", "GlueKit"], path: "BenchmarkModel"),
        .target(name: "BenchmarkRunner", dependencies: ["BenchmarkIPC", "BenchmarkModel"], path: "BenchmarkRunner"),
        .target(name: "BenchmarkCharts", dependencies: ["BenchmarkModel"], path: "BenchmarkCharts"),
    ],
    swiftLanguageVersions: [4]
)
