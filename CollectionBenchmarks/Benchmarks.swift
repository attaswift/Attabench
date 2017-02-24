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

func demoBenchmark() -> BenchmarkSuiteProtocol {
    let suite = BenchmarkSuite(title: "Demo", inputGenerator: { (inputGenerator($0), randomArrayGenerator($0)) })
    suite.descriptiveTitle = "Foo"
    suite.descriptiveAmortizedTitle = "Amortized Foo"

    suite.addJob(title: "Array.contains") { input, lookups in
        return { timer in
            for i in 0 ..< lookups.count {
                guard input.contains(i) else { fatalError() }
            }
        }
    }
    suite.addJob(title: "Array.sort") { input, lookups in
        return { timer in
            let array = input.sorted()
            noop(array)
        }
    }
    suite.addJob(title: "Array.binarySearch") { input, lookups in
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
    suite.addJob(title: "Array.sort+binarySearch") { input, lookups in
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

    suite.addJob(title: "Set.init") { input, lookups in
        return { timer in
            let set = Set(input)
            noop(set)
        }
    }

    suite.addJob(title: "Set.init+capacity") { input, lookups in
        return { timer in
            var set = Set<Int>(minimumCapacity: input.count)
            for value in input { set.insert(value) }
            noop(set)
        }
    }

    suite.addJob(title: "Set.contains") { input, lookups in
        let set = Set(input)
        return { timer in
            for i in lookups {
                guard set.contains(i) else { fatalError() }
            }
        }
    }
    suite.addJob(title: "Set.init+contains") { input, lookups in
        return { timer in
            let set = Set(input)
            for i in lookups {
                guard set.contains(i) else { fatalError() }
            }
        }
    }

    return suite
}

func foreachBenchmark() -> BenchmarkSuite<[Value]> {
    let suite = BenchmarkSuite<[Value]>(title: "ForEach", inputGenerator: inputGenerator)
    suite.descriptiveTitle = "Iteration using “forEach”"
    suite.descriptiveAmortizedTitle = "A single iteration of “forEach”"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to suite: BenchmarkSuite<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addJob(title: title) { input in
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

    suite.addJob(title: "SortedArray") { input in
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

    add("NSOrderedSet", for: MyOrderedSet<Value>.self, to: suite)

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree0/\(order)", to: suite) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: suite) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: suite) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addJob(title: "IntBTree/1024-16, inlined") { input in
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

    suite.addJob(title: "Array") { input in
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

    return suite
}

func indexingBenchmark() -> BenchmarkSuite<[Value]> {
    let suite = BenchmarkSuite<[Value]>(title: "Indexing", inputGenerator: inputGenerator)
    suite.descriptiveTitle = "Iteration using indexing"
    suite.descriptiveAmortizedTitle = "A single iteration step with indexing"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to suite: BenchmarkSuite<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addJob(title: title) { input in
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

    suite.addJob(title: "SortedArray") { input in
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

    add("NSOrderedSet", for: MyOrderedSet<Value>.self, to: suite)

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree0/\(order)", to: suite) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: suite) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: suite) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addJob(title: "IntBTree/1024-16, inlined") { input in
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

    suite.addJob(title: "Array") { input in
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
    
    return suite
}

func containsBenchmark() -> BenchmarkSuite<([Value], [Value])> {
    let suite = BenchmarkSuite<([Value], [Value])>(title: "Contains", inputGenerator: { (inputGenerator($0), randomArrayGenerator($0)) })
    suite.descriptiveTitle = "Looking up all members in random order"
    suite.descriptiveAmortizedTitle = "Looking up one random member"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to suite: BenchmarkSuite<([Value], [Value])>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addJob(title: title) { (input, lookups) in
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

    suite.addJob(title: "SortedArray") { (input, lookups) in
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

    add("NSOrderedSet", for: MyOrderedSet<Value>.self, to: suite)

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree0/\(order)", to: suite) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: suite) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: suite) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addJob(title: "Array") { (input, lookups) in
        if input.count > 100_000 { return nil }
        let array = input.sorted()
        return { timer in
            for element in lookups {
                guard array.contains(element) else { fatalError() }
            }
        }
    }
    
    return suite
}

func insertionBenchmark() -> BenchmarkSuite<[Value]> {
    let suite = BenchmarkSuite<[Value]>(title: "Insertion", inputGenerator: inputGenerator)
    suite.descriptiveTitle = "Construction by random insertions"
    suite.descriptiveAmortizedTitle = "Cost of one random insertion"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, maxSize: Int? = nil, to suite: BenchmarkSuite<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addJob(title: title) { input in
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

    add("SortedArray", for: SortedArray<Value>.self, /*maxSize: 65536,*/ to: suite)
    add("NSOrderedSet", for: MyOrderedSet<Value>.self, /*maxSize: 65536,*/ to: suite)
    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree0/\(order)", to: suite) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: suite) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: suite) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addJob(title: "Array.sort") { input in
        return { timer in
            var array = input
            array.sort()
        }
    }

    return suite
}

func cowBenchmark(iterations: Int = 10, maxScale: Int = 15, random: Bool = true) -> BenchmarkSuite<[Value]> {
    let suite = BenchmarkSuite<[Value]>(title: "SharedInsertion", inputGenerator: inputGenerator)
    suite.descriptiveTitle = "Random insertions into shared storage"
    suite.descriptiveAmortizedTitle = "One random insertion into shared storage"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, maxCount: Int? = nil, to suite: BenchmarkSuite<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addJob(title: title) { input in
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

    add("SortedArray", for: SortedArray<Value>.self, maxCount: 130_000, to: suite)
    add("NSOrderedSet", for: MyOrderedSet<Value>.self, maxCount: 2048, to: suite)
    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree0/\(order)", to: suite) { BTree0<Value>(order: order) }
    }
    for order in orders {
        add("BTree1/\(order)", to: suite) { BTree1<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("IntBTree/\(order)-\(internalOrder)", to: suite) { IntBTree(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addJob(title: "Array.sort") { input in
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

    return suite
}

func btreeIterationBenchmark() -> BenchmarkSuiteProtocol {
    let suite = BenchmarkSuite<[Value]>(title: "BTreeIteration", inputGenerator: inputGenerator)
    suite.descriptiveTitle = "Iterating over all elements"
    suite.descriptiveAmortizedTitle = "A single iteration step"

    suite.addJob(title: "BTree3.Indexing") { input in
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

    suite.addJob(title: "BTree3.for-in") { input in
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

    suite.addJob(title: "BTree3.forEach") { input in
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

    suite.addJob(title: "BTree3.contains") { input in
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

    suite.addJob(title: "IntBTree.Indexing") { input in
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

    suite.addJob(title: "IntBTree.for-in") { input in
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

    suite.addJob(title: "IntBTree.forEach") { input in
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

    suite.addJob(title: "IntBTree.contains") { input in
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

    suite.addJob(title: "Array.for-in") { input in
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

    suite.addJob(title: "Array.forEach") { input in
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

    return suite
}

public func generateBenchmarks() -> [BenchmarkSuiteProtocol] {
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
