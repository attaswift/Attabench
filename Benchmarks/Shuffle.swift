//
//  Shuffle.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-18.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation

extension Array {
    public mutating func shuffle() {
        for i in 0 ..< count {
            let j = Int(arc4random_uniform(UInt32(count)))
            if i != j {
                swap(&self[i], &self[j])
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
