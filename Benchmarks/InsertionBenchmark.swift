//
//  InsertionBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools

func insertionBenchmark() -> Benchmark<[Int]> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

    let benchmark = Benchmark<[Int]>(title: "Insertion", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Construction by random insertions"
    benchmark.descriptiveAmortizedTitle = "Cost of one random insertion"

    func add<T: OrderedSet>(_ title: String, for type: T.Type = T.self, maxSize: Int? = nil, to benchmark: Benchmark<[Int]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
        benchmark.addTask(title: title) { input in
            if let maxSize = maxSize, input.count > maxSize { return nil }
            var first = true
            return { timer in
                var set = initializer()
                timer.measure {
                    for value in input {
                        set.insert(value)
                    }
                }

                if first {
                    var i = 0
                    set.forEach { value in
                        guard value == i else { fatalError() }
                        i += 1
                    }
                    set.validate()
                    first = false
                }
            }
        }
    }

    add("SortedArray", for: SortedArray<Int>.self, /*maxSize: 65536,*/ to: benchmark)
    add("NSOrderedSet", for: MyOrderedSet<Int>.self, /*maxSize: 65536,*/ to: benchmark)
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
        return { timer in
            var array = input
            array.sort()
        }
    }
    
    return benchmark
}

