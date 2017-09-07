// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import GlueKit

public final class Task: Codable, Hashable {
    public typealias Bounds = BenchmarkModel.Bounds
    public typealias Band = TimeSample.Band

    public let name: String
    public internal(set) var samples: [Int: TimeSample] = [:]
    public let checked: BoolVariable = true
    public let isRunnable: BoolVariable = false // transient
    public let sampleCount: IntVariable = 0 // transient

    enum CodingKey: String, Swift.CodingKey {
        case name
        case samples
        case checked
    }

    public let newMeasurements = Signal<(size: Int, time: Time)>()

    public init(name: String) {
        self.name = name
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKey.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.samples = try container.decode([Int: TimeSample].self, forKey: .samples)
        self.sampleCount.value = self.samples.values.reduce(0) { $0 + $1.count }
        if let checked = try container.decodeIfPresent(Bool.self, forKey: .checked) {
            self.checked.value = checked
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKey.self)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.samples, forKey: .samples)
        try container.encode(self.checked.value, forKey: .checked)
    }

    public func addMeasurement(_ time: Time, forSize size: Int) {
        samples.value(for: size, default: TimeSample()).addMeasurement(time)
        newMeasurements.send((size, time))
        self.sampleCount.value += 1
    }

    public func bounds(for band: Band, amortized: Bool) -> (size: Bounds<Int>, time: Bounds<Time>) {
        var sizeBounds = Bounds<Int>()
        var timeBounds = Bounds<Time>()
        for (size, sample) in samples {
            guard let t = sample[band] else { continue }
            let time = amortized ? t / size : t
            sizeBounds.insert(size)
            timeBounds.insert(time)
        }
        return (sizeBounds, timeBounds)
    }

    public var hashValue: Int {
        return name.hashValue
    }

    public static func ==(left: Task, right: Task) -> Bool {
        return left.name == right.name
    }
    
    public func deleteResults(in range: ClosedRange<Int>? = nil) {
        if let range = range {
            samples = samples.filter { !range.contains($0.key) }
            sampleCount.value = samples.values.reduce(0) { $0 + $1.count }
        }
        else {
            samples = [:]
            sampleCount.value = 0
        }
    }

}
