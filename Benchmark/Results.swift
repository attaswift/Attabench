//
//  Results.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools

class BenchmarkSample {
    internal private(set) var measurements: [TimeInterval] = []
    internal private(set) var sum: Double = 0
    internal private(set) var sumSquared: Double = 0

    func addMeasurement(_ elapsedTime: TimeInterval) {
        self.measurements.append(elapsedTime)
        sum += elapsedTime
        sumSquared += elapsedTime * elapsedTime
    }

    var minimum: TimeInterval {
        switch measurements.count {
        case 0: return 0
        case 1: return measurements[0]
        case 2:
            return measurements.min()!
        default:
            return measurements.dropFirst().min()!
        }
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
        return sum / Double(measurements.count)
    }
}

class BenchmarkSamples {
    var samples: [Int: BenchmarkSample] = [:]

    init() {}

    init?(from plist: Any) {
        guard let dict = plist as? [String: [Double]] else { return nil }
        for (size, measurements) in dict {
            guard let size = Int(size, radix: 10) else { return nil }
            let sample = BenchmarkSample()
            for m in measurements { sample.addMeasurement(m) }
            samples[size] = sample
        }
    }

    func encode() -> Any {
        var dict: [String: [Double]] = [:]
        for (size, sample) in samples {
            dict["\(size)"] = sample.measurements
        }
        return dict
    }

    func addMeasurement(_ elapsedTime: TimeInterval, forSize size: Int) {
        let sample = samples[size] ?? BenchmarkSample()
        sample.addMeasurement(elapsedTime)
        samples[size] = sample
    }
}

class BenchmarkSuiteResults {
    var samplesByBenchmark: [String: BenchmarkSamples] = [:]

    init() {
    }

    init?(from plist: Any) {
        guard let dict = plist as? [String: Any] else { return nil }
        for (title, samples) in dict {
            guard let s = BenchmarkSamples(from: samples) else { return nil }
            self.samplesByBenchmark[title] = s
        }
    }

    func encode() -> Any {
        var dict: [String: Any] = [:]
        for (title, samples) in samplesByBenchmark {
            dict[title] = samples.encode()
        }
        return dict
    }

    func samples(for benchmark: String) -> BenchmarkSamples {
        if let samples = samplesByBenchmark[benchmark] { return samples }
        let samples = BenchmarkSamples()
        samplesByBenchmark[benchmark] = samples
        return samples
    }

    func addMeasurement(_ benchmark: String, _ size: Int, _ time: TimeInterval) {
        samples(for: benchmark).addMeasurement(time, forSize: size)
    }
}

