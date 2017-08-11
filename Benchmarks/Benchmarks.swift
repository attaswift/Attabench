//
//  Benchmarks.swift
//  Attabench
//
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

public func generateBenchmarks() -> [BenchmarkProtocol] {
    return [
        demoBenchmark(),
        sampleBenchmark(),
        exampleBenchmark(),
        foreachBenchmark(),
        indexingBenchmark(),
        containsBenchmark(),
        insertionBenchmark(),
        sharedInsertionBenchmark(),
        iterationBenchmark(),
        sortedSetBenchmark(),
    ]
}
