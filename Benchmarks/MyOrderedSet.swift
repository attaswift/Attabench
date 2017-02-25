//
//  MyOrderedSet.swift
//  Benchmark
//
//  Created by Károly Lőrentey on 2017-02-09.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation

private class Canary {}

struct MyOrderedSet<Element: Comparable>: OrderedSet {
    fileprivate var storage = NSMutableOrderedSet()
    fileprivate var canary = Canary()

    init() {}
}

extension MyOrderedSet {
    func forEach(_ body: (Element) -> Void) {
        storage.forEach { body($0 as! Element) }
    }

    func contains(_ element: Element) -> Bool {
        return storage.contains(element)
    }
}

extension MyOrderedSet {
    private static func compare(_ a: Any, _ b: Any) -> ComparisonResult {
        let a = a as! Element, b = b as! Element
        return a < b ? .orderedAscending
            : a > b ? .orderedDescending
            : .orderedSame
    }

    private func index(for element: Element) -> Int {
        return storage.index(of: element, inSortedRange: NSRange(0 ..< storage.count),
                             options: .insertionIndex, usingComparator: MyOrderedSet.compare)
    }

    mutating func insert(_ newElement: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        if !isKnownUniquelyReferenced(&canary) {
            canary = Canary()
            storage = storage.mutableCopy() as! NSMutableOrderedSet
        }
        let index = self.index(for: newElement)
        if index < storage.count, storage[index] as! Element == newElement {
            return (false, storage[index] as! Element)
        }
        storage.insert(newElement, at: index)
        return (true, newElement)
    }
}

extension MyOrderedSet: RandomAccessCollection {
    typealias Index = Int
    typealias Indices = CountableRange<Int>

    var startIndex: Int { return 0 }
    var endIndex: Int { return storage.count }
    subscript(i: Int) -> Element { return storage[i] as! Element }
}
