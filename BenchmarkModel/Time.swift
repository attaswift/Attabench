// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
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

public struct Time: CustomStringConvertible, LosslessStringConvertible, ExpressibleByFloatLiteral, Comparable, Codable {
    var picoseconds: BigInt

    public init(floatLiteral value: Double) {
        self.init(value)
    }

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
        guard let picoseconds = BigInt(try container.decode(String.self), radix: 10) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid big integer value")
        }
        self.picoseconds = picoseconds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(self.picoseconds, radix: 10))
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

    private static let scaleFromSuffix: [String: Time] = [
        "": .second,
        "s": .second,
        "ms": .millisecond,
        "µs": .microsecond,
        "us": .microsecond,
        "ns": .nanosecond,
        "ps": .picosecond
    ]
    private static let floatingPointCharacterSet = CharacterSet(charactersIn: "+-0123456789.e")

    public init?(_ description: String) {
        var description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        description = description.lowercased()
        if let i = description.rangeOfCharacter(from: Time.floatingPointCharacterSet.inverted) {
            let number = description.prefix(upTo: i.lowerBound)
            let suffix = description.suffix(from: i.lowerBound)
            guard let value = Double(number) else { return nil }
            guard let scale = Time.scaleFromSuffix[String(suffix)] else { return nil }
            self = Time(value * scale.seconds)
        }
        else {
            guard let value = Double(description) else { return nil }
            self = Time(value)
        }
    }
    
    public var description: String {
        if self == .zero { return "0" }
        if self < .nanosecond { return "\(picoseconds)ps" }
        if self < .microsecond { return String(format: "%.3gns", Double(picoseconds) / 1e3) }
        if self < .millisecond { return String(format: "%.3gµs", Double(picoseconds) / 1e6) }
        if self < .second { return String(format: "%.3gms", Double(picoseconds) / 1e9) }
        if self.seconds < 1000 { return String(format: "%.3gs", seconds) }
        return String(format: "%gs", seconds.rounded())
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
public func *<I: BinaryInteger>(left: I, right: Time) -> Time {
    return Time(picoseconds: BigInt(left) * right.picoseconds)
}
public func /<I: BinaryInteger>(left: Time, right: I) -> Time {
    return Time(picoseconds: left.picoseconds / BigInt(right))
}
public func *(left: Time, right: Time) -> TimeSquared {
    return TimeSquared(value: left.picoseconds * right.picoseconds)
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
        guard let value = BigInt(try container.decode(String.self), radix: 10) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid big integer value")
        }
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(self.value, radix: 10))
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
