//
//  Benchmarks.swift
//  dotSwift
//
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import BenchmarkingTools

typealias Value = Int

private protocol TestableSet: Collection {
    init()
    func validate()
    func forEach(_ body: (Iterator.Element) throws -> Void) rethrows
    @discardableResult
    mutating func insert(_ element: Iterator.Element) -> (inserted: Bool, memberAfterInsert: Iterator.Element)
}

extension SortedArray: TestableSet {}
extension BinaryTree: TestableSet {}
extension RedBlackTree: TestableSet {}
extension BTree: TestableSet {}

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

    for order in [1023] { // [7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383] {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }

    add("RedBlackTree", for: RedBlackTree<Value>.self, to: suite)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)

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
        for value in 0 ..< input.count { // Cheating!
//            let index = set.index(of: value, inSortedRange: NSRange(0 ..< set.count), options: .insertionIndex, usingComparator: comparator)
            set.insert(value, at: set.count)
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

    return suite
}

func insertionBenchmark() -> BenchmarkSuite<[Value]> {
    let suite = BenchmarkSuite<[Value]>(title: "Insertion", inputGenerator: inputGenerator)

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to suite: BenchmarkSuite<[Value]>, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addBenchmark(title: title) { input in
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
    for order in [1023] { //[7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383] {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }
    add("RedBlackTree", for: RedBlackTree<Value>.self, to: suite)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
    add("SortedArray", for: SortedArray<Value>.self, to: suite)

    suite.addBenchmark(title: "NSOrderedSet") { input in
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

    return suite
}

func cowBenchmark(iterations: Int = 10, maxScale: Int = 15, random: Bool = true) -> BenchmarkSuite<[Value]> {
    let suite = BenchmarkSuite<[Value]>(title: "SharedInsertion", inputGenerator: inputGenerator)

    func add<T: TestableSet>(_ title: String, for type: T.Type = T.self, to suite: BenchmarkSuite<[Value]>, maxCount: Int? = nil, _ initializer: @escaping () -> T = T.init) where T.Iterator.Element == Value {
        suite.addBenchmark(title: title) { input in
            if let maxCount = maxCount, input.count > maxCount { return nil }
            var first = true
            return { measurer in
                var set = initializer()
                measurer.measure {
                    var copy = set
                    for value in input {
                        set.insert(value)
                        copy = set
                    }
                    _ = copy
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
    //let orders = [7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383]
    let orders = [1023]
    for order in orders {
        add("BTree/\(order)", to: suite) { BTree<Value>(order: order) }
    }
    add("RedBlackTree", for: RedBlackTree<Value>.self, to: suite)
    //add("BinaryTree", for: BinaryTree<Value>.self, to: suite)
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

    return suite
}

public func generateBenchmarks() -> [BenchmarkSuiteProtocol] {
    return [
        foreachBenchmark(),
        insertionBenchmark(),
        cowBenchmark()
    ]
}
