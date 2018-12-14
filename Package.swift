// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Attabench",
    products: [
        .library(name: "BenchmarkModel", targets: ["BenchmarkModel"]),
        .library(name: "BenchmarkRunner", targets: ["BenchmarkRunner"]),
        .library(name: "BenchmarkCharts", targets: ["BenchmarkCharts"]),
        .executable(name: "attachart", targets: ["attachart"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/Benchmarking", .branch("master")),
        .package(url: "https://github.com/attaswift/BigInt", from: "3.0.0"),
        .package(url: "https://github.com/attaswift/SipHash", from: "1.2.0"),
        .package(url: "https://github.com/attaswift/GlueKit", from: "0.2.0"),
        .package(url: "https://github.com/attaswift/OptionParser", from: "1.0.0"),
    ],
    targets: [
        .target(name: "BenchmarkModel", dependencies: ["BigInt", "GlueKit"], path: "BenchmarkModel"),
        .target(name: "BenchmarkRunner", dependencies: ["Benchmarking", "BenchmarkModel"], path: "BenchmarkRunner"),
        .target(name: "BenchmarkCharts", dependencies: ["BenchmarkModel"], path: "BenchmarkCharts"),
        .target(name: "attachart", dependencies: ["BenchmarkModel", "BenchmarkCharts", "Benchmarking", "OptionParser"], path: "attachart"),
    ],
    swiftLanguageVersions: [4]
)
