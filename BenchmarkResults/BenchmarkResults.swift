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

public final class BenchmarkResults: Codable {
    /// URL of the .attabench document.
    public var source: URL? = nil

    public private(set) var results: [String: TaskResults] = [:]

    enum Key: String, CodingKey {
        case source
        case results
    }

    public init(source: URL? = nil) {
        precondition(source?.isFileURL != false)
        self.source = source
    }

    public func addMeasurement(_ time: Time, forTask task: String, size: Int) {
        results.value(for: task, default: TaskResults()).addMeasurement(time, forSize: size)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if let bookmarkData = try container.decodeIfPresent(Data.self, forKey: .source) {
            var stale = false
            if let source = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                self.source = source
            }
        }
        self.results = try container.decode([String: TaskResults].self, forKey: .results)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        if let source = self.source {
            try container.encode(source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: .source)
        }
        try container.encode(results, forKey: .results)
    }

    public typealias Band = TimeSample.Band
    public struct Bounds {
        public var sizes: ClosedRange<Int>
        public var times: ClosedRange<TimeInterval>

        public init(sizes: ClosedRange<Int>, times: ClosedRange<TimeInterval>) {
            self.sizes = sizes
            self.times = times
        }
        public init(size: Int, time: TimeInterval) {
            self.sizes = size ... size
            self.times = time ... time
        }

        public func union(with other: Bounds) -> Bounds {
            return Bounds(sizes: sizes.union(with: other.sizes),
                          times: times.union(with: other.times))
        }
    }


    public func bounds(for band: Band, tasks: [String]? = nil, amortized: Bool) -> Bounds? {
        var bounds: Bounds? = nil
        for task in tasks ?? Array(results.keys) {
            guard let r = results[task] else { continue }
            guard let b = r.bounds(for: band, amortized: amortized) else { continue }
            bounds = bounds?.union(with: b) ?? b
        }
        return bounds
    }
}

extension ClosedRange {
    func union(with other: ClosedRange) -> ClosedRange {
        return min(self.lowerBound, other.lowerBound) ... max(self.upperBound, other.upperBound)
    }
}

