//
//  Benchmarks.swift
//  dotSwift
//
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

typealias Value = Int

let orders = [1024] //[8, 16, 32, 64, 128, 256, 512, 768, 1024, 1500, 2048]
let internalOrders = [16] //[5, 8, 16, 32, 64, 128]

private protocol TestableSet: OrderedSet {
    func validate()
    func printInfo()
}
extension TestableSet {
    func validate() {}
    func printInfo() {}
}

extension MyOrderedSet: TestableSet {}
extension SortedArray: TestableSet {}
extension AlgebraicTree: TestableSet {}
extension BinaryTree: TestableSet {}
extension COWTree: TestableSet {
    func printInfo() {
        //print("COWTree - size: \(count) - depth: \(depth)")
    }
}
extension BTree0: TestableSet {}
extension BTree1: TestableSet {}
extension BTree2: TestableSet {
    func printInfo() {
        //print("BTree2/\(order) - size: \(count) - depth: \(depth)")
    }
}
extension BTree3: TestableSet {
    func printInfo() {
        //print("BTree3/\(leafOrder)-\(internalOrder) - size: \(count) - depth: \(depth)")
    }
}
extension IntBTree: TestableSet {}

func randomArrayGenerator(_ size: Int) -> [Value] {
    var values: [Value] = Array(0 ..< size)
    values.shuffle()
    return values
}

func perfectlyBalancedArrayGenerator(_ size: Int) -> [Value] {
    var values: [Value] = Array(repeating: -1, count: size)
    func fill(start: Int, offset: Int, scale: Int) {
        let half = (1 << scale) - 1
        values[start] = offset + half
        if scale > 0 {
            fill(start: 2 * start + 1, offset: offset, scale: scale - 1)
            fill(start: 2 * start + 2, offset: offset + half + 1, scale: scale - 1)
        }
    }

    var scale = 0
    var mask = 1
    while (size & ~mask) != 0 {
        scale += 1
        mask <<= 1
        mask |= 1
    }
    fill(start: 0, offset: 0, scale: scale)
    return values
}

let randomInputs = true
let inputGenerator = randomInputs ? randomArrayGenerator : perfectlyBalancedArrayGenerator

@_semantics("optimize.sil.never")
@inline(never)
func noop<T>(_ value: T) {
    _fixLifetime(value)
}

func demoBenchmark() -> BenchmarkProtocol {
    let benchmark = Benchmark(title: "Demo", inputGenerator: { (inputGenerator($0), randomArrayGenerator($0)) })
    benchmark.descriptiveTitle = "Time spent on all elements"
    benchmark.descriptiveAmortizedTitle = "Average time spent on a single element"

    benchmark.addJob(title: "Array.contains") { input, lookups in
        return { timer in
            for i in 0 ..< lookups.count {
                guard input.contains(i) else { fatalError() }
            }
        }
    }
    benchmark.addJob(title: "Array.sort") { input, lookups in
        return { timer in
            let array = input.sorted()
            noop(array)
        }
    }
    benchmark.addJob(title: "Array.binarySearch") { input, lookups in
        let array = input.sorted()
        return { timer in
            for value in 0 ..< lookups.count {
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
    benchmark.addJob(title: "Array.sort+binarySearch") { input, lookups in
        return { timer in
            let array = input.sorted()
            for value in 0 ..< lookups.count {
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

    benchmark.addJob(title: "Set.init") { input, lookups in
        return { timer in
            let set = Set(input)
            noop(set)
        }
    }

    benchmark.addJob(title: "Set.init+capacity") { input, lookups in
        return { timer in
            var set = Set<Int>(minimumCapacity: input.count)
            for value in input { set.insert(value) }
            noop(set)
        }
    }

    benchmark.addJob(title: "Set.contains") { input, lookups in
        let set = Set(input)
        return { timer in
            for i in lookups {
                guard set.contains(i) else { fatalError() }
            }
        }
    }
    benchmark.addJob(title: "Set.init+contains") { input, lookups in
        return { timer in
            let set = Set(input)
            for i in lookups {
                guard set.contains(i) else { fatalError() }
            }
        }
    }

    return benchmark
}

func foreachBenchmark() -> Benchmark<[Value]> {
    let benchmark = Benchmark<[Value]>(title: "ForEach", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Iteration using “forEach”"
    benchmark.descriptiveAmortizedTitle = "A single iteration of “forEach”"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
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
        var set = SortedArray<Value>()
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

    add("NSOrderedSet", for: MyOrderedSet<Value>.self, to: benchmark)

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: benchmark)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: benchmark)
    add("COWTree", for: COWTree<Value>.self, to: benchmark)

    for order in orders {
        add("BTree0/\(order)", to: benchmark) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: benchmark) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: benchmark) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: benchmark) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
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

func indexingBenchmark() -> Benchmark<[Value]> {
    let benchmark = Benchmark<[Value]>(title: "Indexing", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Iteration using indexing"
    benchmark.descriptiveAmortizedTitle = "A single iteration step with indexing"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
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
        var set = SortedArray<Value>()
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

    add("NSOrderedSet", for: MyOrderedSet<Value>.self, to: benchmark)

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: benchmark)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: benchmark)
    add("COWTree", for: COWTree<Value>.self, to: benchmark)

    for order in orders {
        add("BTree0/\(order)", to: benchmark) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: benchmark) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: benchmark) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: benchmark) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
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

func containsBenchmark() -> Benchmark<([Value], [Value])> {
    let benchmark = Benchmark<([Value], [Value])>(title: "Contains", inputGenerator: { (inputGenerator($0), randomArrayGenerator($0)) })
    benchmark.descriptiveTitle = "Looking up all members in random order"
    benchmark.descriptiveAmortizedTitle = "Looking up one random member"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to benchmark: Benchmark<([Value], [Value])>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        benchmark.addJob(title: title) { (input, lookups) in
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

    benchmark.addJob(title: "SortedArray") { (input, lookups) in
        var set = SortedArray<Value>()
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

    add("NSOrderedSet", for: MyOrderedSet<Value>.self, to: benchmark)

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: benchmark)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: benchmark)
    add("COWTree", for: COWTree<Value>.self, to: benchmark)

    for order in orders {
        add("BTree0/\(order)", to: benchmark) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: benchmark) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: benchmark) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: benchmark) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: benchmark) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    benchmark.addJob(title: "Array") { (input, lookups) in
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

func insertionBenchmark() -> Benchmark<[Value]> {
    let benchmark = Benchmark<[Value]>(title: "Insertion", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Construction by random insertions"
    benchmark.descriptiveAmortizedTitle = "Cost of one random insertion"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, maxSize: Int? = nil, to benchmark: Benchmark<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        benchmark.addJob(title: title) { input in
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

    add("SortedArray", for: SortedArray<Value>.self, /*maxSize: 65536,*/ to: benchmark)
    add("NSOrderedSet", for: MyOrderedSet<Value>.self, /*maxSize: 65536,*/ to: benchmark)
    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: benchmark)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: benchmark)
    add("COWTree", for: COWTree<Value>.self, to: benchmark)

    for order in orders {
        add("BTree0/\(order)", to: benchmark) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: benchmark) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: benchmark) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: benchmark) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: benchmark) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    benchmark.addJob(title: "Array.sort") { input in
        return { timer in
            var array = input
            array.sort()
        }
    }

    return benchmark
}

func cowBenchmark(iterations: Int = 10, maxScale: Int = 15, random: Bool = true) -> Benchmark<[Value]> {
    let benchmark = Benchmark<[Value]>(title: "SharedInsertion", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Random insertions into shared storage"
    benchmark.descriptiveAmortizedTitle = "One random insertion into shared storage"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, maxCount: Int? = nil, to benchmark: Benchmark<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        benchmark.addJob(title: title) { input in
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
                    set.printInfo()
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

    add("SortedArray", for: SortedArray<Value>.self, maxCount: 130_000, to: benchmark)
    add("NSOrderedSet", for: MyOrderedSet<Value>.self, maxCount: 2048, to: benchmark)
    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: benchmark)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: benchmark)
    add("COWTree", for: COWTree<Value>.self, to: benchmark)

    for order in orders {
        add("BTree0/\(order)", to: benchmark) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: benchmark) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: benchmark) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: benchmark) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: benchmark) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    benchmark.addJob(title: "Array.sort") { input in
        guard input.count < 130_000 else { return nil }
        return { timer in
            var array: [Value] = []
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

func btreeIterationBenchmark() -> BenchmarkProtocol {
    let benchmark = Benchmark<[Value]>(title: "BTreeIteration", inputGenerator: inputGenerator)
    benchmark.descriptiveTitle = "Iterating over all elements"
    benchmark.descriptiveAmortizedTitle = "A single iteration step"

    benchmark.addJob(title: "BTree3.indexing") { input in
        var set = BTree3<Int>(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "BTree3.for-in") { input in
        var set = BTree3<Int>(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "IntBTree.indexing") { input in
        var set = IntBTree(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "IntBTree.for-in") { input in
        var set = IntBTree(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "BTree3.contains") { input in
        var set = BTree3<Int>(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "IntBTree.contains") { input in
        var set = IntBTree(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "BTree3.forEach") { input in
        var set = BTree3<Int>(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "IntBTree.forEach") { input in
        var set = IntBTree(leafOrder: 1024, internalOrder: 16)
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

    benchmark.addJob(title: "Array.for-in") { input in
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

    benchmark.addJob(title: "Array.forEach") { input in
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

public func generateBenchmarks() -> [BenchmarkProtocol] {
    return [
        demoBenchmark(),
        foreachBenchmark(),
        indexingBenchmark(),
        containsBenchmark(),
        insertionBenchmark(),
        cowBenchmark(),
        btreeIterationBenchmark(),
    ]
}
