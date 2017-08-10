//
//  Shuffle.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-18.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation

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
            withUnsafeMutableBytes(of: &random) { buffer in
                arc4random_buf(buffer.baseAddress, buffer.count)
            }
            random >>= limit.leadingZeroBitCount
        } while random >= limit
        return random
    }
}

extension Array {
    public mutating func shuffle() {
        for i in 0 ..< count {
            let j = i + Int.random(below: self.count - i)
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
