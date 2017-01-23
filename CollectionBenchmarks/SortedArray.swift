//
//  SortedArray.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-18.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Foundation

public struct SortedArray<Element: Comparable>: RandomAccessCollection {
    public typealias Index = Int
    public typealias IndexDistance = Int.Stride
    public typealias Indices = CountableRange<Index>

    private var storage: ContiguousArray<Element>

    public init() {
        self.storage = []
    }

    public var startIndex: Int { return storage.startIndex }
    public var endIndex: Int { return storage.endIndex }
    public subscript(index: Int) -> Element { return storage[index] }

    public func index(after i: Int) -> Int { return i + 1 }
    public func formIndex(after i: inout Int) { i += 1 }

    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try storage.forEach(body)
    }

    public func validate() {
        if var last = first {
            for element in self.suffix(from: 1) {
                precondition(last < element)
                last = element
            }
        }
    }

    func slot(of element: Element) -> Int {
        var i = 0
        var j = storage.count
        while i < j {
            let middle = i + (j - i) / 2
            if element > storage[middle] {
                i = middle + 1
            }
            else {
                j = middle
            }
        }
        return i
    }

    public func contains(_ element: Element) -> Bool {
        return storage[slot(of: element)] == element
    }

    @discardableResult
    public mutating func insert(_ newElement: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        let slot = self.slot(of: newElement)
        if slot < storage.count && storage[slot] == newElement {
            return (false, storage[slot])
        }
        storage.insert(newElement, at: slot)
        return (true, newElement)
    }

    public mutating func append(_ newElement: Element) {
        precondition(isEmpty || storage.last! < newElement)
        storage.append(newElement)
    }

    @discardableResult
    public mutating func remove(_ element: Element) -> Element? {
        let slot = self.slot(of: element)
        guard slot < storage.count && storage[slot] == element else {
            return nil
        }
        return storage.remove(at: slot)
    }
}
