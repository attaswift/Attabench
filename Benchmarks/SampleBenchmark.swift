//
//  SampleBenchmarl.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-28.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

func sampleBenchmark() -> BenchmarkProtocol {
    let inputGenerator: (Int) -> (input: [Int], lookups: [Int]) = { size in
        return ((0 ..< size).shuffled(), (0 ..< size).shuffled())
    }
    let benchmark = Benchmark(title: "Sample", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Time spent on all elements"
    benchmark.descriptiveAmortizedTitle = "Average time spent on a single element"

    benchmark.addTask(title: "Array.contains") { (input, lookups) in
        guard input.count <= 16384 else { return nil }
        return { timer in
            for value in lookups {
                guard input.contains(value) else { fatalError() }
            }
        }
    }
    benchmark.addTask(title: "Set.contains") { (input, lookups) in
        let set = Set(input)
        return { timer in
            for value in lookups {
                guard set.contains(value) else { fatalError() }
            }
        }
    }
    benchmark.addTask(title: "Array.binarySearch") { (input, lookups) in
        let array = input.sorted()
        return { timer in
            for value in lookups {
                var i = 0
                var j = array.count
                while i < j {
                    let middle = i + (j - i) / 2
                    if value > array[middle] {
                        i = middle + 1
                    }
                    else {
                        j = middle
                    }
                }
                guard i < array.count && array[i] == value else { fatalError() }
            }
        }
    }
    return benchmark
}
