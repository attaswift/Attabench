//
//  Shuffle.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-18.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation

extension Array {
    mutating func shuffle() {
        for i in 0 ..< count {
            let j = Int(arc4random_uniform(UInt32(count)))
            if i != j {
                swap(&self[i], &self[j])
            }
        }
    }
}
