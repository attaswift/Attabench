// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import BigInt

private let picosecondsPerSecond = 1e12

extension BigInt {
    func dividingWithRounding<I: BinaryInteger>(by divisor: I) -> BigInt {
        let (q, r) = self.quotientAndRemainder(dividingBy: BigInt(divisor))
        if r > divisor / 2 { return q + 1 }
        if r == divisor / 2 { return q & 1 == 0 ? q : q + 1 }
        return q
    }
}

public struct Time: CustomStringConvertible, Comparable, Codable {
    var picoseconds: BigInt

    public init() { self.picoseconds = 0 }
    public init(picoseconds: BigInt) {
        self.picoseconds = picoseconds
    }
    public init(_ timeInterval: TimeInterval) {
        self.picoseconds = BigInt(timeInterval * picosecondsPerSecond)
    }
    public init(orderOfMagnitude order: Int) {
        if order < -12 { self.picoseconds = 0; return }
        self.picoseconds = BigInt(10).power(order + 12)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.picoseconds = try container.decode(BigInt.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.picoseconds)
    }

    public var seconds: TimeInterval {
        return TimeInterval(picoseconds) / picosecondsPerSecond
    }

    public static let second = Time(picoseconds: BigInt(1e12))
    public static let millisecond = Time(picoseconds: BigInt(1e9))
    public static let microsecond = Time(picoseconds: BigInt(1e6))
    public static let nanosecond = Time(picoseconds: BigInt(1e3))
    public static let picosecond = Time(picoseconds: 1)
    public static let zero = Time(picoseconds: 0)

    public var description: String {
        if self < Time.nanosecond { return "\(picoseconds)ps" }
        if self < Time.microsecond { return String(format: "%.3gns", Double(picoseconds) / 1e3) }
        if self < Time.millisecond { return String(format: "%.3gµs", Double(picoseconds) / 1e6) }
        if self < Time.second { return String(format: "%.3gms", Double(picoseconds) / 1e9) }
        return String(format: "%.3gs", seconds)
    }

    public static func ==(left: Time, right: Time) -> Bool {
        return left.picoseconds == right.picoseconds
    }
    public static func <(left: Time, right: Time) -> Bool {
        return left.picoseconds < right.picoseconds
    }

    public func dividingWithRounding<I: BinaryInteger>(by divisor: I) -> Time {
        return Time(picoseconds: picoseconds.dividingWithRounding(by: divisor))
    }

    public func squared() -> TimeSquared {
        return self * self
    }
}

public func +(left: Time, right: Time) -> Time {
    return Time(picoseconds: left.picoseconds + right.picoseconds)
}
public func +=(left: inout Time, right: Time) {
    left.picoseconds += right.picoseconds
}
public func -(left: Time, right: Time) -> Time {
    return Time(picoseconds: left.picoseconds - right.picoseconds)
}
public func -=(left: inout Time, right: Time) {
    left.picoseconds -= right.picoseconds
}
public func *(left: Time, right: Time) -> TimeSquared {
    return TimeSquared(value: left.picoseconds * right.picoseconds)
}
public func *<I: BinaryInteger>(left: I, right: Time) -> Time {
    return Time(picoseconds: BigInt(left) * right.picoseconds)
}
public func *<I: BinaryInteger>(left: I, right: TimeSquared) -> TimeSquared {
    return TimeSquared(value: BigInt(left) * right.value)
}
public func +(left: TimeSquared, right: TimeSquared) -> TimeSquared {
    return TimeSquared(value: left.value + right.value)
}
public func +=(left: inout TimeSquared, right: TimeSquared) {
    left.value += right.value
}
public func -(left: TimeSquared, right: TimeSquared) -> TimeSquared {
    return TimeSquared(value: left.value - right.value)
}
public func -=(left: inout TimeSquared, right: TimeSquared) {
    left.value -= right.value
}

public struct TimeSquared: Comparable, Codable {
    var value: BigInt // picoseconds^2

    public init() { self.value = 0 }

    init(value: BigInt) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(BigInt.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }

    public func squareRoot() -> Time {
        return Time(picoseconds: value.squareRoot())
    }

    public func dividingWithRounding<I: BinaryInteger>(by divisor: I) -> TimeSquared {
        return TimeSquared(value: value.dividingWithRounding(by: divisor))
    }

    public static func ==(left: TimeSquared, right: TimeSquared) -> Bool {
        return left.value == right.value
    }
    public static func <(left: TimeSquared, right: TimeSquared) -> Bool {
        return left.value < right.value
    }
}
