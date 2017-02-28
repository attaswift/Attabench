//
//  ContainsBenchmark.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-27.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkingTools

func containsBenchmark() -> Benchmark<([Int], [Int])> {
    let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
    let internalOrders = [16] //[5, 8, 16, 32, 64, 128]
    
    let benchmark = Benchmark<([Int], [Int])>(title: "Contains", inputGenerator: { (inputGenerator($0), randomArrayGenerator($0)) })
    benchmark.descriptiveTitle = "Looking up all members in random order"
    benchmark.descriptiveAmortizedTitle = "Looking up one random member"

    func add<T: OrderedSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<([Int], [Int])>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Int {
        benchmark.addTask(title: title) { (input, lookups) in
            var set = initializer()
            for value in input {
                set.insert(value)
            }
            set.validate()

            return { timer in
                for element in lookups {
                    guard set.contains(element) else { fatalError() }
                }
            }
        }
    }

    benchmark.addTask(title: "SortedArray") { (input, lookups) in
        var set = SortedArray<Int>()
        for value in 0 ..< input.count { // Cheating
            set.append(value)
        }
        set.validate()

        return { timer in
            for element in lookups {
                guard set.contains(element) else { fatalError() }
            }
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

    benchmark.addTask(title: "Array") { (input, lookups) in
        if input.count > 100_000 { return nil }
        let array = input.sorted()
        return { timer in
            for element in lookups {
                guard array.contains(element) else { fatalError() }
            }
        }
    }
    
    return benchmark
}
