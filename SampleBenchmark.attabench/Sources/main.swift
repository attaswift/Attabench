// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Benchmarking

let benchmark = Benchmark<([Int], [Int])>(title: "Sample")
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

benchmark.addTask(title: "SortedArray.binarySearch") { (input, lookups) in
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

benchmark.start()

