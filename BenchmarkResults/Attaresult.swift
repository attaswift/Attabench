// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

extension Dictionary where Value: AnyObject {
    mutating func value(for key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        if let value = self[key] { return value }
        let value = defaultValue()
        self[key] = value
        return value
    }
}

@objc public class Attaresult: NSObject, Codable {
    /// URL of the .attabench document.
    @objc dynamic public var benchmarkURL: URL? = nil

    @objc dynamic public var taskNames: [String] = []

    @objc dynamic public private(set) var results: [String: TaskResults] = [:]
    @objc dynamic public var iterations: Int = 3
    @objc dynamic public var minimumDuration: Double = 0.01
    @objc dynamic public var maximumDuration: Double = 10

    public let largestPossibleSizeScale: Int = 32

    @objc dynamic public var minimumSizeScale: Int = 0
    @objc dynamic public var maximumSizeScale: Int = 20
    @objc dynamic public var sizeSubdivisions: Int = 8

    public var selectedSizes: Set<Int> {
        let a = min(largestPossibleSizeScale, max(0, min(minimumSizeScale, maximumSizeScale)))
        let b = min(largestPossibleSizeScale, max(0, max(minimumSizeScale, maximumSizeScale)))
        var sizes: Set<Int> = []
        for i in sizeSubdivisions * a ... sizeSubdivisions * b {
            let size = exp2(Double(i) / Double(sizeSubdivisions))
            sizes.insert(Int(size))
        }
        return sizes
    }

    public var selectedSizeRange: ClosedRange<Int> {
        return (1 << minimumSizeScale) ... (1 << maximumSizeScale)
    }

    public var benchmarkDisplayName: String {
        guard let url = benchmarkURL else { return "Benchmark" }
        return FileManager().displayName(atPath: url.path)
    }

    enum CodingKeys: String, CodingKey {
        case source
        case taskNames
        case results
        case iterations
        case minimumDuration
        case maximumDuration
        case minimumSizeScale
        case maximumSizeScale
        case sizeSubdivisions
    }

    public override init() {
        super.init()
    }

    public init(iterations: Int = 3,
                minimumDuration: Double = 0.01,
                maximumDuration: Double = 10) {
        self.iterations = iterations
        self.minimumDuration = minimumDuration
        self.maximumDuration = maximumDuration
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let bookmarkData = try container.decodeIfPresent(Data.self, forKey: .source) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                self.benchmarkURL = url
            }
        }
        self.taskNames = try container.decode([String].self, forKey: .taskNames)
        self.results = try container.decode([String: TaskResults].self, forKey: .results)

        if let v = try container.decodeIfPresent(Int.self, forKey: .iterations) {
            self.iterations = v
        }
        if let v = try container.decodeIfPresent(Double.self, forKey: .minimumDuration) {
            self.minimumDuration = v
        }
        if let v = try container.decodeIfPresent(Double.self, forKey: .maximumDuration) {
            self.maximumDuration = v
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .minimumSizeScale) {
            self.minimumSizeScale = v
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .maximumSizeScale) {
            self.maximumSizeScale = v
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .sizeSubdivisions) {
            self.sizeSubdivisions = v
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let url = self.benchmarkURL {
            try container.encode(url.bookmarkData(options: .suitableForBookmarkFile), forKey: .source)
        }
        try container.encode(self.taskNames, forKey: .taskNames)
        try container.encode(self.results, forKey: .results)
        try container.encode(self.iterations, forKey: .iterations)
        try container.encode(self.minimumDuration, forKey: .minimumDuration)
        try container.encode(self.maximumDuration, forKey: .maximumDuration)
        try container.encode(self.minimumSizeScale, forKey: .minimumSizeScale)
        try container.encode(self.maximumSizeScale, forKey: .maximumSizeScale)
        try container.encode(self.sizeSubdivisions, forKey: .sizeSubdivisions)
    }

    public func addMeasurement(_ time: Time, forTask task: String, size: Int) {
        results.value(for: task, default: TaskResults()).addMeasurement(time, forSize: size)
    }

    public typealias Band = TimeSample.Band

    public func bounds(for band: Band, tasks: [String]? = nil, amortized: Bool) -> (size: Bounds<Int>, time: Bounds<Time>) {
        var sizeBounds = Bounds<Int>()
        var timeBounds = Bounds<Time>()
        for task in tasks ?? Array(results.keys) {
            guard let r = results[task] else { continue }
            let b = r.bounds(for: band, amortized: amortized)
            sizeBounds.formUnion(with: b.size)
            timeBounds.formUnion(with: b.time)
        }
        return (sizeBounds, timeBounds)
    }
}

