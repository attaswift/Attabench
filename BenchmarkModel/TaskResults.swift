//
//  Results.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation


@objc public final class TaskResults: NSObject, Codable {

    let samples: [Int: TimeSample] = [:]

    public override init() {
        super.init()
    }

}
