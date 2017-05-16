//
//  IndexingBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

func indexingBenchmark() -> Benchmark<[Int]> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

    let benchmark = Benchmark<[Int]>(title: "Indexing", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Iteration using indexing"
    benchmark.descriptiveAmortizedTitle = "A single iteration step with indexing"

    func add<T: SortedSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<[Int]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
        benchmark.addTask(title: title) { input in
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

    benchmark.addTask(title: "SortedArray") { input in
        let set = SortedArray<Int>(sortedElements: 0 ..< input.count) // Cheating
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

    add("OrderedSet", for: OrderedSet<Int>.self, to: benchmark)

    add("RedBlackTree", for: RedBlackTree<Int>.self, to: benchmark)

    //add("BinaryTree", for: BinaryTree<Int>.self, to: benchmark)
    add("RedBlackTree2", for: RedBlackTree2<Int>.self, to: benchmark)

    for order in orders {
        add("BTree/\(order)", to: benchmark) { BTree<Int>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: benchmark) { BTree2<Int>(order: order) }
    }
    for order in orders {
        add("BTree3/\(order)", to: benchmark) { BTree3<Int>(order: order) }
    }
    for order in orders {
        add("BTree4/\(order)-16", to: benchmark) { BTree4<Int>(order: order) }
    }
//    for order in orders {
//        for internalOrder in internalOrders {
//            add("IntBTree/\(order)-\(internalOrder)", to: benchmark) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
//        }
//    }
//
//    benchmark.addTask(title: "IntBTree/1024-16, inlined") { input in
//        var set = IntBTree(leafOrder: 1024, internalOrder: 16)
//        for value in input {
//            set.insert(value)
//        }
//        return { timer in
//            var i = 0
//            var index = set.startIndex
//            let end = set.endIndex
//            while index != end {
//                guard set[index] == i else { fatalError("Expected \(i), got \(set[index])") }
//                i += 1
//                set.formIndex(after: &index)
//            }
//            guard i == input.count else { fatalError() }
//        }
//    }

    benchmark.addTask(title: "Array") { input in
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
