// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

public struct Bounds<Value: Comparable>: Equatable {
    public var range: ClosedRange<Value>?

    var isEmpty: Bool { return range == nil }

    public init(_ range: ClosedRange<Value>? = nil) {
        self.range = range
    }
    public init(_ value: Value) {
        self.range = value...value
    }

    public static func ==(a: Bounds, b: Bounds) -> Bool {
        return a.range == b.range
    }

    public static func ~=(pattern: Bounds, value: Value) -> Bool {
        return pattern.contains(value)
    }

    public func contains(_ value: Value) -> Bool {
        guard let range = range else { return false }
        return range.contains(value)
    }

    public mutating func clamp(to limits: Bounds) {
        guard let range = self.range else { return }
        guard let limits = limits.range else { self.range = nil; return }
        self.range = range.clamped(to: limits)
    }

    public func clamped(to limits: Bounds) -> Bounds {
        var r = self
        r.clamp(to: limits)
        return r
    }

    public mutating func formUnion(with other: Bounds) {
        switch (self.range, other.range) {
        case let (a?, b?):
            self.range = min(a.lowerBound, b.lowerBound) ... max(a.upperBound, b.upperBound)
        case let (nil, b?):
            self.range = b
        default:
            break
        }
    }

    public func union(with other: Bounds) -> Bounds {
        var r = self
        r.formUnion(with: other)
        return r
    }

    public mutating func insert(_ value: Value) {
        if let range = self.range {
            self.range = min(range.lowerBound, value) ... max(range.upperBound, value)
        }
        else {
            self.range = value ... value
        }
    }

    public func inserted(_ value: Value) -> Bounds {
        var r = self
        r.insert(value)
        return r
    }
}
