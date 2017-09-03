// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Attabench",
    products: [
        .library(name: "Benchmarking", targets: ["Benchmarking", "BenchmarkIPC"]),
        .library(name: "BenchmarkResults", targets: ["BenchmarkResults"]),
        .library(name: "BenchmarkRunner", targets: ["BenchmarkRunner", "BenchmarkIPC"]),
        .library(name: "BenchmarkCharts", targets: ["BenchmarkCharts"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/OptionParser", .branch("master")),
        .package(url: "https://github.com/lorentey/BigInt", .branch("swift4")),
        .package(url: "https://github.com/lorentey/SipHash", .branch("swift4")),
    ],
    targets: [
        .target(name: "BenchmarkIPC", path: "BenchmarkIPC"),
        .target(name: "Benchmarking", dependencies: ["OptionParser", "BenchmarkIPC"], path: "Benchmarking"),
        .target(name: "BenchmarkResults", dependencies: ["BigInt"], path: "BenchmarkResults"),
        .target(name: "BenchmarkRunner", dependencies: ["BenchmarkIPC", "BenchmarkResults"], path: "BenchmarkRunner"),
        .target(name: "BenchmarkCharts", dependencies: ["BenchmarkResults"], path: "BenchmarkCharts"),
    ],
    swiftLanguageVersions: [4]
)
