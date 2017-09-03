//
//  Results.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation


public final class TaskResults: Codable {
    public typealias Bounds = BenchmarkResults.Bounds
    public typealias Band = TimeSample.Band

    public private(set) var samples: [Int: TimeSample] = [:]

    public init() {}

    public func addMeasurement(_ time: Time, forSize size: Int) {
        samples.value(for: size, default: TimeSample()).addMeasurement(time)
    }

    public func bounds(for band: Band, amortized: Bool) -> Bounds? {
        var bounds: Bounds? = nil
        for (size, sample) in samples {
            guard let time = sample[band] else { continue }
            let t = amortized ? time.seconds / TimeInterval(size) : time.seconds
            let b = Bounds(size: size, time: t)
            bounds = bounds?.union(with: b) ?? b
        }
        return bounds
    }
}
