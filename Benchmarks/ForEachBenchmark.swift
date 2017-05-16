//
//  ForEachBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools


func foreachBenchmark() -> Benchmark<[Int]> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

    let benchmark = Benchmark<[Int]>(title: "ForEach", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Iteration using “forEach”"
    benchmark.descriptiveAmortizedTitle = "A single iteration of “forEach”"

    func add<T: SortedSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<[Int]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
        benchmark.addTask(title: title) { input in
            var set = initializer()
            for value in input {
                set.insert(value)
            }
            set.validate()

            return { timer in
                var i = 0
                set.forEach { element in
                    guard element == i else { fatalError() }
                    i += 1
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
            set.forEach { element in
                guard element == i else { fatalError() }
                i += 1
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
//            set.forEach { element in
//                guard element == i else { fatalError() }
//                i += 1
//            }
//            guard i == input.count else { fatalError() }
//        }
//    }

    benchmark.addTask(title: "Array") { input in
        let array = input.sorted()
        return { timer in
            var i = 0
            for element in array {
                guard element == i else { fatalError() }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }
    
    return benchmark
}
