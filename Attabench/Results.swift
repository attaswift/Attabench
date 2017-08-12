//
//  Results.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools
import BigInt

private let picosecondsPerSecond = 1e12

extension BigUInt {
    func dividingWithRounding<I: BinaryInteger>(by divisor: I) -> BigUInt {
        let (q, r) = self.quotientAndRemainder(dividingBy: BigUInt(divisor))
        if r > divisor / 2 { return q + 1 }
        if r == divisor / 2 { return q & 1 == 0 ? q : q + 1 }
        return q
    }
}

struct Time: CustomStringConvertible, Comparable, Codable {
    var picoseconds: BigUInt

    init() { self.picoseconds = 0 }
    init(picoseconds: BigUInt) {
        self.picoseconds = picoseconds
    }
    init(_ timeInterval: TimeInterval) {
        self.picoseconds = BigUInt(timeInterval * picosecondsPerSecond)
    }
    init(orderOfMagnitude order: Int) {
        if order < -12 { self.picoseconds = 0; return }
        self.picoseconds = BigUInt(10).power(order + 12)
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.picoseconds = try container.decode(BigUInt.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.picoseconds)
    }

    var seconds: TimeInterval {
        return TimeInterval(picoseconds) / picosecondsPerSecond
    }

    static let second = Time(picoseconds: BigUInt(1e12))
    static let millisecond = Time(picoseconds: BigUInt(1e9))
    static let microsecond = Time(picoseconds: BigUInt(1e6))
    static let nanosecond = Time(picoseconds: BigUInt(1e3))
    static let picosecond = Time(picoseconds: 1)
    static let zero = Time(picoseconds: 0)

    var description: String {
        if self < Time.nanosecond { return "\(picoseconds)ps" }
        if self < Time.microsecond { return String(format: "%.3gns", Double(picoseconds) / 1e3) }
        if self < Time.millisecond { return String(format: "%.3gµs", Double(picoseconds) / 1e6) }
        if self < Time.second { return String(format: "%.3gms", Double(picoseconds) / 1e9) }
        return String(format: "%.3gs", seconds)
    }

    static func ==(left: Time, right: Time) -> Bool {
        return left.picoseconds == right.picoseconds
    }
    static func <(left: Time, right: Time) -> Bool {
        return left.picoseconds < right.picoseconds
    }

    func dividingWithRounding<I: BinaryInteger>(by divisor: I) -> Time {
        return Time(picoseconds: picoseconds.dividingWithRounding(by: divisor))
    }

    func squared() -> TimeSquared {
        return self * self
    }
}

func +(left: Time, right: Time) -> Time {
    return Time(picoseconds: left.picoseconds + right.picoseconds)
}
func +=(left: inout Time, right: Time) {
    left.picoseconds += right.picoseconds
}
func -(left: Time, right: Time) -> Time {
    return Time(picoseconds: left.picoseconds - right.picoseconds)
}
func -=(left: inout Time, right: Time) {
    left.picoseconds -= right.picoseconds
}
func *(left: Time, right: Time) -> TimeSquared {
    return TimeSquared(value: left.picoseconds * right.picoseconds)
}
func *<I: BinaryInteger>(left: I, right: Time) -> Time {
    return Time(picoseconds: BigUInt(left) * right.picoseconds)
}
func *<I: BinaryInteger>(left: I, right: TimeSquared) -> TimeSquared {
    return TimeSquared(value: BigUInt(left) * right.value)
}
func +(left: TimeSquared, right: TimeSquared) -> TimeSquared {
    return TimeSquared(value: left.value + right.value)
}
func +=(left: inout TimeSquared, right: TimeSquared) {
    left.value += right.value
}
func -(left: TimeSquared, right: TimeSquared) -> TimeSquared {
    return TimeSquared(value: left.value - right.value)
}
func -=(left: inout TimeSquared, right: TimeSquared) {
    left.value -= right.value
}

struct TimeSquared: Comparable, Codable {
    var value: BigUInt // picoseconds^2

    init() { self.value = 0 }

    init(value: BigUInt) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(BigUInt.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }

    func squareRoot() -> Time {
        return Time(picoseconds: value.squareRoot())
    }

    func dividingWithRounding<I: BinaryInteger>(by divisor: I) -> TimeSquared {
        return TimeSquared(value: value.dividingWithRounding(by: divisor))
    }

    static func ==(left: TimeSquared, right: TimeSquared) -> Bool {
        return left.value == right.value
    }
    static func <(left: TimeSquared, right: TimeSquared) -> Bool {
        return left.value < right.value
    }
}

final class TaskSample: Codable {
    internal private(set) var minimum: Time? = nil
    internal private(set) var maximum: Time? = nil
    internal private(set) var count: Int = 0
    internal private(set) var sum = Time()
    internal private(set) var sumSquared = TimeSquared()

    init() {}

    enum Key: CodingKey {
        case minimum
        case maximum
        case count
        case sum
        case sumSquared
    }
    
    init(from decoder: Decoder) throws {
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
            sum = Time()
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
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(minimum, forKey: .minimum)
        try container.encode(maximum, forKey: .maximum)
        try container.encode(count, forKey: .count)
        try container.encode(sum, forKey: .sum)
        try container.encode(sumSquared, forKey: .sumSquared)
    }

    func addMeasurement(_ elapsedTime: Time) {
        minimum = Swift.min(elapsedTime, minimum ?? elapsedTime)
        maximum = Swift.max(elapsedTime, maximum ?? .zero)
        sum += elapsedTime
        sumSquared += elapsedTime.squared()
        count += 1
    }

    func addMeasurement(_ elapsedTime: TimeInterval) {
        addMeasurement(Time(elapsedTime))
    }

    var average: Time? {
        if count == 0 { return nil }
        return sum.dividingWithRounding(by: count)
    }

    var standardDeviation: Time? {
        if count < 2 { return nil }
        let c = BigUInt(count)
        let s2 = (c * sumSquared - sum.squared()).dividingWithRounding(by: c * (c - 1))
        return s2.squareRoot()
    }
}

final class TaskResults: Codable {
    var samplesBySize: [Int: TaskSample] = [:]

    init() {}

    init?(from plist: Any) {
        guard let dict = plist as? [String: Double] else { return nil }
        for (size, measurement) in dict {
            guard let size = Int(size, radix: 10) else { return nil }
            let sample = TaskSample()
            sample.addMeasurement(measurement)
            samplesBySize[size] = sample
        }
    }

    func encode() -> Any {
        var dict: [String: Double] = [:]
        for (size, sample) in samplesBySize {
            dict["\(size)"] = sample.minimum?.seconds
        }
        return dict
    }
    
    enum Keys: CodingKey {
        case samples
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        self.samplesBySize = try container.decode([Int: TaskSample].self, forKey: .samples)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(samplesBySize, forKey: .samples)
    }

    func addMeasurement(_ elapsedTime: TimeInterval, forSize size: Int) {
        let sample = samplesBySize[size] ?? TaskSample()
        sample.addMeasurement(elapsedTime)
        samplesBySize[size] = sample
    }
}

