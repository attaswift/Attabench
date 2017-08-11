//
//  IterationBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

func iterationBenchmark() -> BenchmarkProtocol {
    let benchmark = Benchmark<[Int]>(title: "BTreeIteration")
    benchmark.descriptiveTitle = "Iterating over all elements"
    benchmark.descriptiveAmortizedTitle = "A single iteration step"

    benchmark.addTask(title: "BTree4.indexing") { input in
        var set = BTree4<Int>(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            var i = 0
            var index = set.startIndex
            let end = set.endIndex
            while index != end {
                guard set[index] == i else { fatalError("Expected \(i), got \(set[index])") }
                i += 1
                set.formIndex(after: &index)
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addTask(title: "BTree4.for-in") { input in
        var set = BTree4<Int>(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            var i = 0
            for element in set {
                guard element == i else { fatalError("Expected \(i), got \(element)") }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addTask(title: "IntBTree.indexing") { input in
        var set = IntBTree3(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            var i = 0
            var index = set.startIndex
            let end = set.endIndex
            while index != end {
                guard set[index] == i else { fatalError("Expected \(i), got \(set[index])") }
                i += 1
                set.formIndex(after: &index)
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addTask(title: "IntBTree.for-in") { input in
        var set = IntBTree3(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            var i = 0
            for element in set {
                guard element == i else { fatalError("Expected \(i), got \(element)") }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addTask(title: "BTree4.contains") { input in
        var set = BTree4<Int>(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            for i in 0 ..< input.count {
                guard set.contains(i) else { fatalError("Expected to find \(i)") }
            }
        }
    }

    benchmark.addTask(title: "IntBTree.contains") { input in
        var set = IntBTree3(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            for i in 0 ..< input.count {
                guard set.contains(i) else { fatalError("Expected to find \(i)") }
            }
        }
    }

    benchmark.addTask(title: "BTree4.forEach") { input in
        var set = BTree4<Int>(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            var i = 0
            set.forEach { element in
                guard element == i else { fatalError("Expected \(i), got \(element)") }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addTask(title: "IntBTree.forEach") { input in
        var set = IntBTree3(order: 1024)
        for value in input {
            set.insert(value)
        }
        set.validate()

        return { timer in
            var i = 0
            set.forEach { element in
                guard element == i else { fatalError("Expected \(i), got \(element)") }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addTask(title: "Array.for-in") { input in
        var array = input
        array.sort()

        return { timer in
            var i = 0
            for element in array {
                guard element == i else { fatalError("Expected \(i), got \(element)") }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addTask(title: "Array.forEach") { input in
        var array = input
        array.sort()

        return { timer in
            var i = 0
            array.forEach { element in
                guard element == i else { fatalError("Expected \(i), got \(element)") }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }
    
    return benchmark
}
