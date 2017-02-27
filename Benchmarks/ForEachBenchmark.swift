//
//  ForEachBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools


func foreachBenchmark() -> Benchmark<[Int]> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

    let benchmark = Benchmark<[Int]>(title: "ForEach", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Iteration using “forEach”"
    benchmark.descriptiveAmortizedTitle = "A single iteration of “forEach”"

    func add<T: OrderedSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<[Int]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
        benchmark.addJob(title: title) { input in
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

    benchmark.addJob(title: "SortedArray") { input in
        var set = SortedArray<Int>()
        for value in 0 ..< input.count { // Cheating
            set.append(value)
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
            set.forEach { element in
                guard element == i else { fatalError() }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    benchmark.addJob(title: "Array") { input in
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
