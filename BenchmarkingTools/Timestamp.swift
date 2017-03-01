//
//  Timestamp.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import QuartzCore

struct Timestamp {
    fileprivate let value: CFTimeInterval

    init() {
        self.value = CACurrentMediaTime()
    }
}

func -(left: Timestamp, right: Timestamp) -> TimeInterval {
    return left.value - right.value
}
