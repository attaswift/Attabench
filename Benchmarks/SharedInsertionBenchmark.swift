//
//  SharedInsertionBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools

func sharedInsertionBenchmark(iterations: Int = 10, maxScale: Int = 15, random: Bool = true) -> Benchmark<[Int]> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

    let benchmark = Benchmark<[Int]>(title: "SharedInsertion", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Random insertions into shared storage"
    benchmark.descriptiveAmortizedTitle = "One random insertion into shared storage"

    func add<T: OrderedSet>(_ title: String, for type: T.Type = T.self, maxCount: Int? = nil, to benchmark: Benchmark<[Int]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
        benchmark.addTask(title: title) { input in
            if let maxCount = maxCount, input.count > maxCount { return nil }
            var first = true
            return { timer in
                var set = initializer()
                timer.measure {
                    #if false
                        var copy = set
                        var k = 0
                        for value in input {
                            set.insert(value)
                            print(Array(set))
                            precondition(!copy.contains(value))
                            precondition(set.contains(value))
                            copy = set

                            do {
                                var i = 0
                                let test = input.prefix(through: k).sorted()
                                set.forEach { value in
                                    guard value == test[i] else { fatalError("Expected \(test[i]), got \(value)") }
                                    i += 1
                                }
                                set.validate()
                            }
                            k += 1
                        }
                        _ = copy
                    #else
                        var copy = set
                        for value in input {
                            set.insert(value)
                            copy = set
                        }
                        _ = copy
                    #endif
                }

                if first {
                    var i = 0
                    set.forEach { value in
                        guard value == i else { fatalError("Expected \(i), got \(value)") }
                        i += 1
                    }
                    set.validate()
                    first = false
                }
            }
        }
    }

    add("SortedArray", for: SortedArray<Int>.self, maxCount: 130_000, to: benchmark)
    add("NSOrderedSet", for: MyOrderedSet<Int>.self, maxCount: 2048, to: benchmark)
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

    benchmark.addTask(title: "Array.sort") { input in
        guard input.count < 130_000 else { return nil }
        return { timer in
            var array: [Int] = []
            var copy = array
            for value in input {
                array.append(value)
                copy = array
            }
            array.sort()
            _ = copy
        }
    }
    
    return benchmark
}
