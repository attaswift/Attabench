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
    var scaleRange: CountableClosedRange<Int> = 0 ... 20
    var samplesByBenchmark: [String: BenchmarkSamples] = [:]
    var selectedBenchmarks: Set<String> = [] // Empty means all

    var sizeRange: ClosedRange<Int> {
        return (1 << scaleRange.lowerBound) ... (1 << scaleRange.upperBound)
    }

    init() {
    }

    init?(from plist: Any) {
        guard let dict = plist as? [String: Any],
            let data = dict["Data"] as? [String: Any]
        else { return nil }

        if let minScale = dict["MinScale"] as? Int,
            let maxScale = dict["MaxScale"] as? Int {
            self.scaleRange = minScale ... maxScale
        }

        if let selected = dict["SelectedBenchmarks"] as? [String] {
            self.selectedBenchmarks = Set(selected)
        }

        for (title, samples) in data {
            guard let s = BenchmarkSamples(from: samples) else { return nil }
            self.samplesByBenchmark[title] = s
        }
    }

    func encode() -> Any {
        var dict: [String: Any] = [:]
        dict["MinScale"] = scaleRange.lowerBound
        dict["MaxScale"] = scaleRange.upperBound
        dict["SelectedBenchmarks"] = Array(selectedBenchmarks)
        var data: [String: Any] = [:]
        for (title, samples) in samplesByBenchmark {
            data[title] = samples.encode()
        }
        dict["Data"] = data
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

