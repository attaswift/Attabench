//
//  IndexingBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools

func indexingBenchmark() -> Benchmark<[Int]> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

    let benchmark = Benchmark<[Int]>(title: "Indexing", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Iteration using indexing"
    benchmark.descriptiveAmortizedTitle = "A single iteration step with indexing"

    func add<T: OrderedSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<[Int]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
        benchmark.addJob(title: title) { input in
            var set = initializer()
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
    }

    benchmark.addJob(title: "SortedArray") { input in
        var set = SortedArray<Int>()
        for value in 0 ..< input.count { // Cheating
            set.append(value)
        }
        set.validate()

        return { timer in
            var i = 0
            var index = set.startIndex
            while index != set.endIndex {
                guard set[index] == i else { fatalError() }
                i += 1
                set.formIndex(after: &index)
            }
            guard i == input.count else { fatalError() }
        }
    }

    add("NSOrderedSet", for: MyOrderedSet<Int>.self, to: benchmark)

    add("AlgebraicTree", for: AlgebraicTree<Int>.self, to: benchmark)

    //add("BinaryTree", for: BinaryTree<Int>.self, to: benchmark)
    add("COWTree", for: COWTree<Int>.self, to: benchmark)

    for order in orders {
        add("BTree0/\(order)", to: benchmark) { BTree0<Int>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: benchmark) { BTree1<Int>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: benchmark) { BTree2<Int>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: benchmark) { BTree3<Int>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: benchmark) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    benchmark.addJob(title: "IntBTree/1024-16, inlined") { input in
        var set = IntBTree(leafOrder: 1024, internalOrder: 16)
        for value in input {
            set.insert(value)
        }
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

    benchmark.addJob(title: "Array") { input in
        let array = input.sorted()
        return { timer in
            var i = 0
            var index = array.startIndex
            while index != array.endIndex {
                guard array[index] == i else { fatalError() }
                i += 1
                array.formIndex(after: &index)
            }
            guard i == input.count else { fatalError() }
        }
    }
    
    return benchmark
}
