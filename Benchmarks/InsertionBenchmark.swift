//
//  InsertionBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

func insertionBenchmark() -> Benchmark<[Int]> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

    let benchmark = Benchmark<[Int]>(title: "Insertion")
    benchmark.descriptiveTitle = "Construction by random insertions"
    benchmark.descriptiveAmortizedTitle = "Cost of one random insertion"

    func add<T: SortedSet>(_ title: String, for type: T.Type = T.self, maxSize: Int? = nil, to benchmark: Benchmark<[Int]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
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

    add("SortedArray.insert", for: SortedArray<Int>.self, /*maxSize: 65536,*/ to: benchmark)
    add("OrderedSet.insert", for: OrderedSet<Int>.self, /*maxSize: 65536,*/ to: benchmark)
    add("RedBlackTree.insert", for: RedBlackTree<Int>.self, to: benchmark)
    //add("BinaryTree", for: BinaryTree<Int>.self, to: benchmark)
    add("RedBlackTree2.insert", for: RedBlackTree2<Int>.self, to: benchmark)

    for order in orders {
        add("BTree/\(order).insert", to: benchmark) { BTree<Int>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order).insert", to: benchmark) { BTree2<Int>(order: order) }
    }
    for order in orders {
        add("BTree3/\(order).insert", to: benchmark) { BTree3<Int>(order: order) }
    }
    for order in orders {
        add("BTree4/\(order)-16.insert", to: benchmark) { BTree4<Int>(order: order) }
    }
//    for order in orders {
//        for internalOrder in internalOrders {
//            add("IntBTree/\(order)-\(internalOrder).insert", to: benchmark) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
//        }
//    }

    benchmark.addTask(title: "Array.sort") { input in
        return { timer in
            var array = input
            array.sort()
        }
    }
    
    return benchmark
}

