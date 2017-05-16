//
//  OrderedSet.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-02-09.
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation

private class Canary {}

public struct OrderedSet<Element: Comparable>: SortedSet {
    fileprivate var storage = NSMutableOrderedSet()
    fileprivate var canary = Canary()
    public init() {}
}

extension OrderedSet {
    public func forEach(_ body: (Element) -> Void) {
        storage.forEach { body($0 as! Element) }
    }
}

extension OrderedSet {
    fileprivate static func compare(_ a: Any, _ b: Any) -> ComparisonResult
    {
        let a = a as! Element, b = b as! Element
        return a < b ? .orderedAscending
            : a > b ? .orderedDescending
            : .orderedSame
    }
}

extension OrderedSet {
    public func index(of element: Element) -> Int? {
        let index = storage.index(
            of: element,
            inSortedRange: NSRange(0 ..< storage.count),
            usingComparator: OrderedSet.compare)
        return index == NSNotFound ? nil : index
    }
}

extension OrderedSet {
    public func contains(_ element: Element) -> Bool {
        return index(of: element) != nil
    }
}

extension OrderedSet {
    public func contains2(_ element: Element) -> Bool {
        return storage.contains(element) || index(of: element) != nil
    }
}

extension OrderedSet: RandomAccessCollection {
    public typealias Index = Int
    public typealias Indices = CountableRange<Int>

    public var startIndex: Int { return 0 }
    public var endIndex: Int { return storage.count }
    public subscript(i: Int) -> Element { return storage[i] as! Element }
}

extension OrderedSet {
    fileprivate mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&canary) {
            storage = storage.mutableCopy() as! NSMutableOrderedSet
            canary = Canary()
        }
    }
}

extension OrderedSet {
    fileprivate func slot(of value: Element) -> Int {
        return storage.index(
            of: value,
            inSortedRange: NSRange(0 ..< storage.count),
            options: .insertionIndex,
            usingComparator: OrderedSet.compare)
    }
}

extension OrderedSet {
    @discardableResult
    public mutating func insert(_ newElement: Element) -> (inserted: Bool, memberAfterInsert: Element)
    {
        let index = self.slot(of: newElement)
        if index < storage.count, storage[index] as! Element == newElement {
            return (false, storage[index] as! Element)
        }
        makeUnique()
        storage.insert(newElement, at: index)
        return (true, newElement)
    }
}
