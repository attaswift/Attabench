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

private protocol TestableSet: Collection {
    init()
    func validate()
    func contains(_ element: Iterator.Element) -> Bool
    func forEach(_ body: (Iterator.Element) throws -> Void) rethrows
    @discardableResult
    mutating func insert(_ element: Iterator.Element) -> (inserted: Bool, memberAfterInsert: Iterator.Element)
    func printInfo(size: Int)
}

extension SortedArray: TestableSet {
    func printInfo(size: Int) {
    }
}
extension AlgebraicTree: TestableSet {
    func printInfo(size: Int) {
    }
}
extension BinaryTree: TestableSet {
    func printInfo(size: Int) {
    }
}
extension COWTree: TestableSet {
    func printInfo(size: Int) {
        //print("COWTree - size: \(size) - depth: \(depth)")
    }
}
extension BTree: TestableSet {
    func printInfo(size: Int) {
    }
}
extension BTree2: TestableSet {
    func printInfo(size: Int) {
        //print("BTree2/\(order) - size: \(size) - depth: \(depth)")
    }
}
extension BTree3: TestableSet {
    func printInfo(size: Int) {
        //print("BTree3/\(leafOrder)-\(internalOrder) - size: \(size) - depth: \(depth)")
    }
}

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

func foreachBenchmark() -> BenchmarkSuite<[Value]> {
    let suite = BenchmarkSuite<[Value]>(title: "ForEach", inputGenerator: inputGenerator)
    suite.descriptiveTitle = "Iteration using “forEach”"
    suite.descriptiveAmortizedTitle = "A single iteration of “forEach”"

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to suite: BenchmarkSuite<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addBenchmark(title: title) { input in
            var set = initializer()
            for value in input {
                set.insert(value)
            }
            set.validate()

            return { measurer in
                var i = 0
                set.forEach { element in
                    guard element == i else { fatalError() }
                    i += 1
                }
                guard i == input.count else { fatalError() }
            }
        }
    }

    suite.addBenchmark(title: "SortedArray") { input in
        var set = SortedArray<Value>()
        for value in 0 ..< input.count { // Cheating
            set.append(value)
        }
        set.validate()

        return { measurer in
            var i = 0
            set.forEach { element in
                guard element == i else { fatalError() }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    suite.addBenchmark(title: "NSOrderedSet") { input in
        //guard input.count < 300_000 else { return nil }

        let set = NSMutableOrderedSet()
        let comparator: (Any, Any) -> ComparisonResult = {
            let a = $0 as! Value
            let b = $1 as! Value
            return (a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame)
        }
        for value in input {
            let index = set.index(of: value, inSortedRange: NSRange(0 ..< set.count), options: .insertionIndex, usingComparator: comparator)
            set.insert(value, at: index)
        }

        return { measurer in
            var i = 0
            for element in set {
                guard (element as! Value) == i else { fatalError() }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }
    
    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addBenchmark(title: "Array") { input in
        let array = input.sorted()
        return { measurer in
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
        suite.addBenchmark(title: title) { input in
            var set = initializer()
            for value in input {
                set.insert(value)
            }
            set.validate()

            return { measurer in
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

    suite.addBenchmark(title: "SortedArray") { input in
        var set = SortedArray<Value>()
        for value in 0 ..< input.count { // Cheating
            set.append(value)
        }
        set.validate()

        return { measurer in
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

    suite.addBenchmark(title: "NSOrderedSet") { input in
        //guard input.count < 300_000 else { return nil }

        let set = NSMutableOrderedSet()
        let comparator: (Any, Any) -> ComparisonResult = {
            let a = $0 as! Value
            let b = $1 as! Value
            return (a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame)
        }
        for value in input {
            let index = set.index(of: value, inSortedRange: NSRange(0 ..< set.count), options: .insertionIndex, usingComparator: comparator)
            set.insert(value, at: index)
        }

        return { measurer in
            var i = 0
            let c = set.count
            while i != c {
                guard set[i] as! Value == i else { fatalError() }
                i += 1
            }
            guard i == input.count else { fatalError() }
        }
    }

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addBenchmark(title: "Array") { input in
        let array = input.sorted()
        return { measurer in
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
        suite.addBenchmark(title: title) { (input, lookups) in
            var set = initializer()
            for value in input {
                set.insert(value)
            }
            set.validate()

            return { measurer in
                for element in lookups {
                    guard set.contains(element) else { fatalError() }
                }
            }
        }
    }

    suite.addBenchmark(title: "SortedArray") { (input, lookups) in
        var set = SortedArray<Value>()
        for value in 0 ..< input.count { // Cheating
            set.append(value)
        }
        set.validate()

        return { measurer in
            for element in lookups {
                guard set.contains(element) else { fatalError() }
            }
        }
    }
    
    suite.addBenchmark(title: "NSOrderedSet") { (input, lookups) in
        let set = NSMutableOrderedSet()
        let comparator: (Any, Any) -> ComparisonResult = {
            let a = $0 as! Value
            let b = $1 as! Value
            return (a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame)
        }
        for value in input {
            let index = set.index(of: value, inSortedRange: NSRange(0 ..< set.count), options: .insertionIndex, usingComparator: comparator)
            set.insert(value, at: index)
        }

        return { measurer in
            for element in lookups {
                guard set.contains(element) else { fatalError() }
            }
        }
    }
    
    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addBenchmark(title: "Array") { (input, lookups) in
        if input.count > 100_000 { return nil }
        let array = input.sorted()
        return { measurer in
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
        suite.addBenchmark(title: title) { input in
            if let maxSize = maxSize, input.count > maxSize { return nil }
            var first = true
            return { measurer in
                var set = initializer()
                measurer.measure {
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

    add("SortedArray", for: SortedArray<Value>.self, maxSize: 100_000, to: suite)

    suite.addBenchmark(title: "NSOrderedSet") { input in
        if input.count > 100_000 { return nil }
        return { measurer in
            let set = NSMutableOrderedSet()
            let comparator: (Any, Any) -> ComparisonResult = {
                let a = $0 as! Value
                let b = $1 as! Value
                return (a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame)
            }
            for value in input {
                let index = set.index(of: value, inSortedRange: NSRange(0 ..< set.count), options: .insertionIndex, usingComparator: comparator)
                set.insert(value, at: index)
            }
        }
    }

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)

    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addBenchmark(title: "Array.sort") { input in
        return { measurer in
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

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to suite: BenchmarkSuite<[Value]>, maxCount: Int? = nil, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addBenchmark(title: title) { input in
            if let maxCount = maxCount, input.count > maxCount { return nil }
            var first = true
            return { measurer in
                var set = initializer()
                measurer.measure {
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
                    set.printInfo(size: input.count)
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

    add("SortedArray", for: SortedArray<Value>.self, to: suite, maxCount: 300_000)

    suite.addBenchmark(title: "NSOrderedSet") { input in
        guard input.count < 20_000 else { return nil }
        return { measurer in
            let set = NSMutableOrderedSet()
            let comparator: (Any, Any) -> ComparisonResult = {
                let a = $0 as! Value
                let b = $1 as! Value
                return (a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame)
            }
            measurer.measure {
                var copy = set.copy()
                for value in input {
                    let index = set.index(of: value, inSortedRange: NSRange(0 ..< set.count), options: .insertionIndex, usingComparator: comparator)
                    set.insert(value, at: index)
                    copy = set.copy()
                }
                _ = copy
            }
        }
    }

    add("AlgebraicTree", for: AlgebraicTree<Value>.self, to: suite)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("COWTree", for: COWTree<Value>.self, to: suite)

    for order in orders {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }
    for order in orders {
        add("BTree2/\(order)", to: suite) { BTree2<Value>(order: order) }
    }
    for order in orders {
        for internalOrder in internalOrders {
            add("BTree3/\(order)-\(internalOrder)", to: suite) { BTree3<Value>(leafOrder: order, internalOrder: internalOrder) }
        }
    }

    suite.addBenchmark(title: "Array.sort") { input in
        guard input.count < 300_000 else { return nil }
        return { measurer in
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

public func generateBenchmarks() -> [BenchmarkSuiteProtocol] {
    return [
        foreachBenchmark(),
        indexingBenchmark(),
        containsBenchmark(),
        insertionBenchmark(),
        cowBenchmark()
    ]
}
