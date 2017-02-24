//
//  Results.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools

class JobSample {
    internal private(set) var measurements: [TimeInterval] = []
    internal private(set) var sum: Double = 0
    internal private(set) var sumSquared: Double = 0
    internal private(set) var count: Double = 0

    func addMeasurement(_ elapsedTime: TimeInterval) {
        self.measurements.append(elapsedTime)
        if measurements.count > 100 {
            measurements.replaceSubrange(0 ..< 50, with: [measurements[0 ..< 50].min()!])
        }
        sum += elapsedTime
        sumSquared += elapsedTime * elapsedTime
        count += 1
    }

    var minimum: TimeInterval {
        return measurements.min() ?? 0
    }
    var maximum: TimeInterval {
        switch measurements.count {
        case 0: return 0
        case 1: return measurements[0]
        case 2:
            return measurements.max()!
        default:
            return measurements.dropFirst().max()!
        }
    }

    var average: TimeInterval {
        if measurements.count == 0 { return 0 }
        return sum / count
    }
}

class JobResults {
    var samplesBySize: [Int: JobSample] = [:]

    init() {}

    init?(from plist: Any) {
        guard let dict = plist as? [String: Double] else { return nil }
        for (size, measurement) in dict {
            guard let size = Int(size, radix: 10) else { return nil }
            let sample = JobSample()
            sample.addMeasurement(measurement)
            samplesBySize[size] = sample
        }
    }

    func encode() -> Any {
        var dict: [String: Double] = [:]
        for (size, sample) in samplesBySize {
            dict["\(size)"] = sample.minimum
        }
        return dict
    }

    func addMeasurement(_ elapsedTime: TimeInterval, forSize size: Int) {
        let sample = samplesBySize[size] ?? JobSample()
        sample.addMeasurement(elapsedTime)
        samplesBySize[size] = sample
    }
}

