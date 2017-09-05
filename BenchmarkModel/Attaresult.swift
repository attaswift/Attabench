// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import GlueKit

extension Dictionary where Value: AnyObject {
    mutating func value(for key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        if let value = self[key] { return value }
        let value = defaultValue()
        self[key] = value
        return value
    }
}

public class Attaresult: NSObject, Codable {
    /// URL of the .attabench document.
    public let benchmarkURL: OptionalVariable<URL> = nil

    public private(set) lazy var benchmarkDisplayName: AnyObservableValue<String>
        = benchmarkURL.map { url in
            guard let url = url else { return "Benchmark" }
            return FileManager.default.displayName(atPath: url.path)
    }.buffered()

    // Data

    public let tasks: ArrayVariable<Task> = []
    private lazy var tasksByName: [String: Task] = {
        var d = [String: Task](uniqueKeysWithValues: self.tasks.value.map { ($0.name, $0) })
        self.glue.connector.connect(tasks.updates) { [unowned self] update in
            guard case let .change(change) = update else { return }
            change.forEachOld { task in self.tasksByName.removeValue(forKey: task.name) }
            change.forEachNew { task in self.tasksByName[task.name] = task }
        }
        return d
    }()

    public private(set) lazy var newMeasurements: AnySource<(size: Int, time: Time)>
        = self.tasks.map { $0.newMeasurements }.gather()


    // Run options

    public let iterations: IntVariable = 3
    public let minimumDuration: Variable<Time> = .init(0.01)
    public let maximumDuration: Variable<Time> = .init(10.0)

    public static let largestPossibleSizeScale: Int = 32
    public let minimumSizeScale: IntVariable = 0
    public let maximumSizeScale: IntVariable = 20
    public let sizeSubdivisions: IntVariable = 8

    public private(set) lazy var selectedSizes: AnyObservableValue<Set<Int>>
        = self.sizeSubdivisions.combined(self.minimumSizeScale, self.maximumSizeScale) { subs, start, end in
            let lower = min(Attaresult.largestPossibleSizeScale, max(0, min(start, end)))
            let upper = min(Attaresult.largestPossibleSizeScale, max(0, max(start, end)))
            var sizes: Set<Int> = []
            for i in subs * lower ... subs * upper {
                let size = exp2(Double(i) / Double(subs))
                sizes.insert(Int(size))
            }
            return sizes
    }

    public private(set) lazy var selectedSizeRange: AnyObservableValue<ClosedRange<Int>>
        = self.minimumSizeScale.combined(self.maximumSizeScale) { min, max in (1 << min) ... (1 << max) }

    public private(set) lazy var runOptionsTick: MergedSource<Void>
        = [iterations.tick,
           minimumDuration.tick,
           maximumDuration.tick,
           minimumSizeScale.tick,
           maximumSizeScale.tick,
           sizeSubdivisions.tick].gather()

    // Chart options

    public let amortizedTime: BoolVariable = true
    public let logarithmicSizeScale: BoolVariable = true
    public let logarithmicTimeScale: BoolVariable = true

    public let topBand: OptionalVariable<Band> = nil
    public let centerBand: OptionalVariable<Band> = .init(.average)
    public let bottomBand: OptionalVariable<Band> = nil

    public let highlightSelectedSizeRange: BoolVariable = true

    public let displaySizeRange: OptionalVariable<ClosedRange<Int>> = nil
    public let displayAllMeasuredSizes: BoolVariable = true

    public let displayTimeRange: OptionalVariable<ClosedRange<Time>> = nil
    public let displayAllMeasuredTimes: BoolVariable = true

    public let displayRefreshInterval: Variable<Time> = .init(5.0)

    public private(set) lazy var chartOptionsTick: MergedSource<Void>
     = [amortizedTime.tick,
        logarithmicSizeScale.tick,
        logarithmicTimeScale.tick,
        topBand.tick,
        centerBand.tick,
        centerBand.tick,
        bottomBand.tick,
        highlightSelectedSizeRange.tick,
        displaySizeRange.tick,
        displayAllMeasuredSizes.tick,
        displayTimeRange.tick,
        displayAllMeasuredTimes.tick,
        displayRefreshInterval.tick].gather()

    public override init() {
        super.init()
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case taskNames
        case results

        case source
        case tasks
        case iterations
        case minimumDuration
        case maximumDuration
        case minimumSizeScale
        case maximumSizeScale
        case sizeSubdivisions

        case amortizedTime
        case logarithmicSizeScale
        case logarithmicTimeScale
        case topBand
        case centerBand
        case bottomBand
        case highlightSelectedSizeRange
        case displaySizeRangeMin
        case displaySizeRangeMax
        case displayAllMeasuredSizes
        case displayTimeRangeMin
        case displayTimeRangeMax
        case displayAllMeasuredTimes
        case displayRefreshInterval
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let url = self.benchmarkURL.value {
            try container.encode(url.bookmarkData(options: .suitableForBookmarkFile), forKey: .source)
        }
        try container.encode(self.tasks.value, forKey: .tasks)
        try container.encode(self.iterations.value, forKey: .iterations)
        try container.encode(self.minimumDuration.value.seconds, forKey: .minimumDuration)
        try container.encode(self.maximumDuration.value.seconds, forKey: .maximumDuration)
        try container.encode(self.minimumSizeScale.value, forKey: .minimumSizeScale)
        try container.encode(self.maximumSizeScale.value, forKey: .maximumSizeScale)
        try container.encode(self.sizeSubdivisions.value, forKey: .sizeSubdivisions)
        try container.encode(self.amortizedTime.value, forKey: .amortizedTime)
        try container.encode(self.logarithmicSizeScale.value, forKey: .logarithmicSizeScale)
        try container.encode(self.logarithmicTimeScale.value, forKey: .logarithmicTimeScale)
        try container.encode(self.topBand.value, forKey: .topBand)
        try container.encode(self.centerBand.value, forKey: .centerBand)
        try container.encode(self.bottomBand.value, forKey: .bottomBand)
        try container.encode(self.highlightSelectedSizeRange.value, forKey: .highlightSelectedSizeRange)
        if let range = self.displaySizeRange.value {
            try container.encode(range.lowerBound, forKey: .displaySizeRangeMin)
            try container.encode(range.upperBound, forKey: .displaySizeRangeMax)
        }
        try container.encode(self.displayAllMeasuredSizes.value, forKey: .displayAllMeasuredSizes)
        if let range = self.displayTimeRange.value {
            try container.encode(range.lowerBound, forKey: .displayTimeRangeMin)
            try container.encode(range.upperBound, forKey: .displayTimeRangeMax)
        }
        try container.encode(self.displayAllMeasuredTimes.value, forKey: .displayAllMeasuredTimes)
        try container.encode(self.displayRefreshInterval.value, forKey: .displayRefreshInterval)
    }

    public required init(from decoder: Decoder) throws {
        super.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let bookmarkData = try container.decodeIfPresent(Data.self, forKey: .source) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                self.benchmarkURL.value = url
            }
        }

        self.tasks.value = try container.decode([Task].self, forKey: .tasks)

        if let v = try container.decodeIfPresent(Int.self, forKey: .iterations) {
            self.iterations.value = v
        }
        if let v = try container.decodeIfPresent(Double.self, forKey: .minimumDuration) {
            self.minimumDuration.value = Time(v)
        }
        if let v = try container.decodeIfPresent(Double.self, forKey: .maximumDuration) {
            self.maximumDuration.value = Time(v)
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .minimumSizeScale) {
            self.minimumSizeScale.value = v
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .maximumSizeScale) {
            self.maximumSizeScale.value = v
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .sizeSubdivisions) {
            self.sizeSubdivisions.value = v
        }

        if let v = try container.decodeIfPresent(Bool.self, forKey: .amortizedTime) {
            self.amortizedTime.value = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .logarithmicSizeScale) {
            self.logarithmicSizeScale.value = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .logarithmicTimeScale) {
            self.logarithmicTimeScale.value = v
        }
        if let v = try container.decodeIfPresent(Band.self, forKey: .topBand) {
            self.topBand.value = v
        }
        if let v = try container.decodeIfPresent(Band.self, forKey: .centerBand) {
            self.centerBand.value = v
        }
        if let v = try container.decodeIfPresent(Band.self, forKey: .bottomBand) {
            self.bottomBand.value = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .highlightSelectedSizeRange) {
            self.highlightSelectedSizeRange.value = v
        }

        if let min = try container.decodeIfPresent(Int.self, forKey: .displaySizeRangeMin),
            let max = try container.decodeIfPresent(Int.self, forKey: .displaySizeRangeMax) {
            self.displaySizeRange.value = min ... max
        }
        else {
            self.displaySizeRange.value = nil
        }

        if let v = try container.decodeIfPresent(Bool.self, forKey: .displayAllMeasuredSizes) {
            self.displayAllMeasuredSizes.value = v
        }
        if let min = try container.decodeIfPresent(Time.self, forKey: .displayTimeRangeMin),
            let max = try container.decodeIfPresent(Time.self, forKey: .displayTimeRangeMax) {
            self.displayTimeRange.value = min ... max
        }
        else {
            self.displayTimeRange.value = nil
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .displayAllMeasuredTimes) {
            self.displayAllMeasuredTimes.value = v
        }
        if let v = try container.decodeIfPresent(Time.self, forKey: .displayRefreshInterval) {
            self.displayRefreshInterval.value = v
        }
    }

    // MARK: Measurements

    public func task(for name: String) -> Task {
        if let task = self.tasksByName[name] { return task }
        let task = Task(name: name)
        tasks.append(task)
        return self.tasksByName[name]!
    }

    public func addMeasurement(_ time: Time, forTask taskName: String, size: Int) {
        let task = self.task(for: taskName)
        task.addMeasurement(time, forSize: size)
    }

    public typealias Band = TimeSample.Band

    public func bounds(for band: Band, tasks: [Task]? = nil, amortized: Bool) -> (size: Bounds<Int>, time: Bounds<Time>) {
        var sizeBounds = Bounds<Int>()
        var timeBounds = Bounds<Time>()
        for task in tasks ?? self.tasks.value {
            let b = task.bounds(for: band, amortized: amortized)
            sizeBounds.formUnion(with: b.size)
            timeBounds.formUnion(with: b.time)
        }
        return (sizeBounds, timeBounds)
    }
}

