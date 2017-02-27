//
//  ExampleBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools

func exampleBenchmark() -> BenchmarkProtocol {
    let benchmark = Benchmark(title: "Example", inputGenerator: { (inputGenerator($0), randomArrayGenerator($0)) })
    benchmark.descriptiveTitle = "Time spent on all elements"
    benchmark.descriptiveAmortizedTitle = "Average time spent on a single element"

    benchmark.addJob(title: "Array.contains") { input, lookups in
        return { timer in
            for i in 0 ..< lookups.count {
                guard input.contains(i) else { fatalError() }
            }
        }
    }
    benchmark.addJob(title: "Array.sort") { input, lookups in
        return { timer in
            let array = input.sorted()
            noop(array)
        }
    }
    benchmark.addJob(title: "Array.binarySearch") { input, lookups in
        let array = input.sorted()
        return { timer in
            for value in 0 ..< lookups.count {
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
    benchmark.addJob(title: "Array.sort+binarySearch") { input, lookups in
        return { timer in
            let array = input.sorted()
            for value in 0 ..< lookups.count {
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

    benchmark.addJob(title: "Set.init") { input, lookups in
        return { timer in
            let set = Set(input)
            noop(set)
        }
    }

    benchmark.addJob(title: "Set.init+capacity") { input, lookups in
        return { timer in
            var set = Set<Int>(minimumCapacity: input.count)
            for value in input { set.insert(value) }
            noop(set)
        }
    }

    benchmark.addJob(title: "Set.contains") { input, lookups in
        let set = Set(input)
        return { timer in
            for i in lookups {
                guard set.contains(i) else { fatalError() }
            }
        }
    }
    benchmark.addJob(title: "Set.init+contains") { input, lookups in
        return { timer in
            let set = Set(input)
            for i in lookups {
                guard set.contains(i) else { fatalError() }
            }
        }
    }

    return benchmark
}
