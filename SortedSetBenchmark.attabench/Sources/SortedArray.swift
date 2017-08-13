//
//  SortedArray.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-18.
//  Copyright © 2017 Károly Lőrentey.
//

public struct SortedArray<Element: Comparable>: SortedSet {
    fileprivate var storage: [Element] = []

    public init() {}
}

extension SortedArray {
    func index(for element: Element) -> Int {
        var start = 0
        var end = storage.count
        while start < end {
            let middle = start + (end - start) / 2
            if element > storage[middle] {
                start = middle + 1
            }
            else {
                end = middle
            }
        }
        return start
    }
}

extension SortedArray {
    public func index(of element: Element) -> Int? {
        let index = self.index(for: element)
        guard index < count, self[index] == element else { return nil }
        return index
    }
}

extension SortedArray {
    public func contains(_ element: Element) -> Bool {
        let index = self.index(for: element)
        return index < count && storage[index] == element
    }
}

extension SortedArray {
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try storage.forEach(body)
    }
}

extension SortedArray {
    public func sorted() -> [Element] {
        return storage
    }
}

extension SortedArray {
    @discardableResult
    public mutating func insert(_ newElement: Element) -> (inserted: Bool, memberAfterInsert: Element)
    {
        let index = self.index(for: newElement)
        if index < count && storage[index] == newElement {
            return (false, storage[index])
        }
        storage.insert(newElement, at: index)
        return (true, newElement)
    }
}

extension SortedArray: RandomAccessCollection {
    public typealias Indices = CountableRange<Int>

    public var startIndex: Int { return storage.startIndex }
    public var endIndex: Int { return storage.endIndex }

    public subscript(index: Int) -> Element { return storage[index] }
}

extension SortedArray {
    public func validate() {
        if var last = first {
            for element in self.suffix(from: 1) {
                precondition(last < element)
                last = element
            }
        }
    }
}

extension SortedArray {
    public init<S: Sequence>(unsortedElements elements: S) where S.Iterator.Element == Element {
        self.init()
        self.storage = elements.sorted()
    }

    public init<S: Sequence>(sortedElements elements: S) where S.Iterator.Element == Element {
        self.init()
        self.storage = Array(elements)
    }
}

extension SortedArray {
    func index2(for element: Element) -> Int {
        var start = 0
        var end = storage.count
        while start < end {
            let diff = end - start
            let middle = start + diff / 2 - (diff >> 6)
            if element > storage[middle] {
                start = middle + 1
            }
            else {
                end = middle
            }
        }
        return start
    }

    func index3(for element: Element) -> Int {
        var start = 0
        var end = storage.count
        while start < end {
            let diff = end - start
            if diff < 64 {
                let middle = start + diff / 2
                if element > storage[middle] {
                    start = middle + 1
                }
                else {
                    end = middle
                }
            }
            else {
                let third = diff / 3
                let m1 = start + third
                let m2 = end - third
                let v2 = storage[m2]
                let v1 = storage[m1]
                if element > v2 {
                    start = m2 + 1
                }
                else if element < v1 {
                    end = m1
                }
                else {
                    start = m1
                    end = m2 + 1
                }
            }
        }
        return start
    }

    public func contains2(_ element: Element) -> Bool {
        return storage[index2(for: element)] == element
    }

    public func contains3(_ element: Element) -> Bool {
        return storage[index3(for: element)] == element
    }
}
