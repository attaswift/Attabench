// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import BigInt

func min<C: Comparable>(_ a: C?, _ b: C?) -> C? {
    switch (a, b) {
    case let (a?, b?): return Swift.min(a, b)
    case let (a?, nil): return a
    case let (nil, b?): return b
    case (nil, nil): return nil
    }
}

func max<C: Comparable>(_ a: C?, _ b: C?) -> C? {
    switch (a, b) {
    case let (a?, b?): return Swift.max(a, b)
    case let (a?, nil): return a
    case let (nil, b?): return b
    case (nil, nil): return nil
    }
}

public final class TimeSample: Codable {
    public private(set) var minimum: Time? = nil
    public private(set) var maximum: Time? = nil
    public private(set) var count: Int = 0
    public private(set) var sum = Time(picoseconds: 0)
    public private(set) var sumSquared = TimeSquared()

    public init() {}

    enum Key: CodingKey {
        case minimum
        case maximum
        case count
        case sum
        case sumSquared
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.minimum = try container.decode(Time?.self, forKey: .minimum)
        self.maximum = try container.decode(Time?.self, forKey: .maximum)
        self.count = try container.decode(Int.self, forKey: .count)
        self.sum = try container.decode(Time.self, forKey: .sum)
        self.sumSquared = try container.decode(TimeSquared.self, forKey: .sumSquared)
        guard count >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .count, in: container,
                debugDescription: "negative count")
        }
        if count == 0 {
            minimum = nil
            maximum = nil
            count = 0
            sum = Time(picoseconds: 0)
            sumSquared = TimeSquared()
        }
        guard count == 0 || minimum != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .minimum, in: container,
                debugDescription: "minimum is nil with a nonzero count")
        }
        guard count == 0 || maximum != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .minimum, in: container,
                debugDescription: "maximum is nil with a nonzero count")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(minimum, forKey: .minimum)
        try container.encode(maximum, forKey: .maximum)
        try container.encode(count, forKey: .count)
        try container.encode(sum, forKey: .sum)
        try container.encode(sumSquared, forKey: .sumSquared)
    }

    public func addMeasurement(_ elapsedTime: Time) {
        minimum = Swift.min(elapsedTime, minimum ?? elapsedTime)
        maximum = Swift.max(elapsedTime, maximum ?? .zero)
        sum += elapsedTime
        sumSquared += elapsedTime.squared()
        count += 1
    }

    public func addSample(_ sample: TimeSample) {
        self.minimum = min(self.minimum, sample.minimum)
        self.maximum = max(self.maximum, sample.maximum)
        self.count += sample.count
        self.sum += sample.sum
        self.sumSquared += sample.sumSquared
    }

    public var average: Time? {
        if count == 0 { return nil }
        return sum.dividingWithRounding(by: count)
    }

    public var standardDeviation: Time? {
        if count < 2 { return nil }
        let c = BigInt(count)
        let s2 = (c * sumSquared - sum.squared()).dividingWithRounding(by: c * (c - 1))
        return s2.squareRoot()
    }
}
