//
//  Benchmarks.swift
//  dotSwift
//
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

func randomArrayGenerator(_ size: Int) -> [Int] {
    var values: [Int] = Array(0 ..< size)
    values.shuffle()
    return values
}

func perfectlyBalancedArrayGenerator(_ size: Int) -> [Int] {
    var values: [Int] = Array(repeating: -1, count: size)
    func fill(start: Int, offset: Int, scale: Int) {
        let half = (1 << scale) - 1
        values[start] = offset + half
        if scale > 0 {
            fill(start: 2 * start + 1, offset: offset, scale: scale - 1)
            fill(start: 2 * start + 2, offset: offset + half + 1, scale: scale - 1)
        }
    }

    var scale = 0
    var mask = 1
    while (size & ~mask) != 0 {
        scale += 1
        mask <<= 1
        mask |= 1
    }
    fill(start: 0, offset: 0, scale: scale)
    return values
}

private let randomInputs = true
let inputGenerator = randomInputs ? randomArrayGenerator : perfectlyBalancedArrayGenerator

public func generateBenchmarks() -> [BenchmarkProtocol] {
    return [
        exampleBenchmark(),
        foreachBenchmark(),
        indexingBenchmark(),
        containsBenchmark(),
        insertionBenchmark(),
        sharedInsertionBenchmark(),
        iterationBenchmark(),
    ]
}
