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

    private var value: ContiguousArray<Element>

    public init() {
        self.value = []
    }

    public var startIndex: Int { return value.startIndex }
    public var endIndex: Int { return value.endIndex }
    public subscript(index: Int) -> Element { return value[index] }

    public func index(after i: Int) -> Int { return i + 1 }
    public func formIndex(after i: inout Int) { i += 1 }

    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try value.forEach(body)
    }

    public func validate() {
        if var last = first {
            for element in self.suffix(from: 1) {
                precondition(last < element)
                last = element
            }
        }
    }

    func slot(of element: Element) -> (found: Bool, index: Int) {
        var i = 0
        var j = value.count
        while i < j {
            let middle = (i + j) / 2
            if value[middle] < element {
                i = middle + 1
            }
            else if value[middle] > element {
                j = middle
            }
            else {
                return (found: true, index: middle)
            }
        }
        return (found: false, index: i)
    }

    public func contains(_ element: Element) -> Bool {
        return self.slot(of: element).found
    }

    @discardableResult
    public mutating func insert(_ newElement: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        let slot = self.slot(of: newElement)
        if slot.found {
            return (false, value[slot.index])
        }
        value.insert(newElement, at: slot.index)
        return (true, newElement)
    }

    public mutating func append(_ newElement: Element) {
        precondition(isEmpty || value.last! < newElement)
        value.append(newElement)
    }

    @discardableResult
    public mutating func remove(_ element: Element) -> Element? {
        let slot = self.slot(of: element)
        guard slot.found else { return nil }
        return value.remove(at: slot.index)
    }
}
