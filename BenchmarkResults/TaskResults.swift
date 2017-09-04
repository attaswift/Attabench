//
//  Results.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation


@objc public final class TaskResults: NSObject, Codable {
    public typealias Bounds = BenchmarkResults.Bounds
    public typealias Band = TimeSample.Band

    @objc dynamic public private(set) var samples: [Int: TimeSample] = [:]

    public override init() {
        super.init()
    }

    public func addMeasurement(_ time: Time, forSize size: Int) {
        samples.value(for: size, default: TimeSample()).addMeasurement(time)
    }

    public func bounds(for band: Band, amortized: Bool) -> (size: Bounds<Int>, time: Bounds<Time>) {
        var sizeBounds = Bounds<Int>()
        var timeBounds = Bounds<Time>()
        for (size, sample) in samples {
            guard let t = sample[band] else { continue }
            let time = amortized ? t / size : t
            sizeBounds.insert(size)
            timeBounds.insert(time)
        }
        return (sizeBounds, timeBounds)
    }
}
