// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Darwin

extension FixedWidthInteger {
    /// Return a random nonnegative value that is less than `limit`, which must be positive.
    /// Uses the `arc4` family of functions to generate random bits.
    public static func random(below limit: Self) -> Self {
        precondition(limit > 0)
        if Self.bitWidth <= UInt32.bitWidth || limit <= UInt32.max {
            return Self(arc4random_uniform(UInt32(limit)))
        }
        var random: Self = 0
        repeat {
            random = 0
            var bits = Self.bitWidth - limit.leadingZeroBitCount
            while bits > 0 {
                let r = arc4random()
                let b = Swift.min(32, bits)
                random <<= b
                random |= Self(r >> (32 - b))
                bits -= 32
            }
        } while random >= limit
        return random
    }
}

extension RandomAccessCollection where IndexDistance: FixedWidthInteger {
    public func randomElement() -> Element {
        precondition(count > 0)
        let offset = Self.IndexDistance.random(below: count)
        let index = self.index(self.startIndex, offsetBy: offset)
        return self[index]
    }
}

extension RandomAccessCollection where Self: MutableCollection, IndexDistance: FixedWidthInteger {
    public mutating func shuffle() {
        for i in indices {
            let offset = IndexDistance.random(below: self.distance(from: i, to: self.endIndex))
            let j = self.index(i, offsetBy: offset)
            if i != j {
                self.swapAt(i, j)
            }
        }
    }
}

extension Sequence {
    public func shuffled() -> [Iterator.Element] {
        var array = Array(self)
        array.shuffle()
        return array
    }
}
