// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Attabench",
    products: [
        .library(name: "Benchmarking", targets: ["Benchmarking"]),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/OptionParser", .branch("master")),
        .package(url: "https://github.com/lorentey/BigInt", .branch("swift4")),
        .package(url: "https://github.com/lorentey/SipHash", .branch("swift4")),
    ],
    targets: [
        .target(name: "Benchmarking",
                dependencies: ["OptionParser"],
                path: "Benchmarking"),
    ],
    swiftLanguageVersions: [4]
)
