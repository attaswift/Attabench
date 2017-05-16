//
//  UnoptimizedBTree.swift
//  Benchmark
//
//  Created by Károly Lőrentey on 2017-02-09.
//  Copyright © 2017 Károly Lőrentey.
//

struct BTree<Element: Comparable> {
    fileprivate var root: Node<Element>

    init(order: Int) {
        self.root = Node(order: order)
    }
}

fileprivate final class Node<Element: Comparable> {
    let order: Int
    var mutationCount: Int = 0
    var elements: [Element] = []
    var children: [Node] = []

    init(order: Int) {
        self.order = order
    }
}

import Darwin

let cacheSize: Int = {
    var result: Int = 0
    var size = MemoryLayout<Int>.size
    if sysctlbyname("hw.l1dcachesize", &result, &size, nil, 0) == -1 {
        return 32768
    }
    return result
}()

extension BTree {
    init() {
        let order = cacheSize / (4 * MemoryLayout<Element>.stride)
        self.init(order: Swift.max(16, order))
    }
}

extension BTree {
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try root.forEach(body)
    }
}

extension Node {
    func forEach(_ body: (Element) throws -> Void) rethrows {
        if children.count == 0 {
            try elements.forEach(body)
        }
        else {
            for i in 0 ..< elements.count {
                try children[i].forEach(body)
                try body(elements[i])
            }
            try children[elements.count].forEach(body)
        }
    }
}

extension Node {
    internal func slot(of element: Element) -> (match: Bool, index: Int) {
        var start = 0
        var end = elements.count
        while start < end {
            let mid = start + (end - start) / 2
            if elements[mid] < element {
                start = mid + 1
            }
            else {
                end = mid
            }
        }
        let match = start < elements.count && elements[start] == element
        return (match, start)
    }
}

extension BTree {
    public func contains(_ element: Element) -> Bool {
        return root.contains(element)
    }
}

extension Node {
    func contains(_ element: Element) -> Bool {
        let slot = self.slot(of: element)
        if slot.match { return true }
        guard !children.isEmpty else { return false }
        return children[slot.index].contains(element)
    }
}

extension BTree {
    fileprivate mutating func makeRootUnique() -> Node<Element> {
        if isKnownUniquelyReferenced(&root) { return root }
        root = root.clone()
        return root
    }
}

extension Node {
    func clone() -> Node {
        let clone = Node(order: order)
        clone.elements = self.elements
        clone.children = self.children
        return clone
    }
}

extension Node {
    func makeChildUnique(_ slot: Int) -> Node {
        guard !isKnownUniquelyReferenced(&children[slot]) else {
            return children[slot]
        }
        let clone = children[slot].clone()
        children[slot] = clone
        return clone
    }
}

extension Node {
    var isLeaf: Bool { return children.isEmpty }
    var isTooLarge: Bool { return elements.count >= order }
}

private struct Splinter<Element: Comparable> {
    let separator: Element
    let node: Node<Element>
}

extension Node {
    func split() -> Splinter<Element> {
        let count = elements.count
        let middle = count / 2

        let separator = elements[middle]

        let node = Node(order: order)
        node.elements.append(contentsOf: elements[middle + 1 ..< count])
        elements.removeSubrange(middle ..< count)
        if !isLeaf {
            node.children.append(contentsOf: children[middle + 1 ..< count + 1])
            children.removeSubrange(middle + 1 ..< count + 1)
        }
        return Splinter(separator: separator, node: node)
    }
}

extension Node {
    func insert(_ element: Element) -> (old: Element?, splinter: Splinter<Element>?) {

        let slot = self.slot(of: element)
        if slot.match {
            // The element is already in the tree.
            return (self.elements[slot.index], nil)
        }

        mutationCount += 1

        if self.isLeaf {
            elements.insert(element, at: slot.index)
            return (nil, self.isTooLarge ? self.split() : nil)
        }

        let (old, splinter) = makeChildUnique(slot.index).insert(element)
        guard let s = splinter else { return (old, nil) }
        elements.insert(s.separator, at: slot.index)
        children.insert(s.node, at: slot.index + 1)
        return (nil, self.isTooLarge ? self.split() : nil)
    }
}

extension BTree {
    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        let root = makeRootUnique()
        let (old, splinter) = root.insert(element)
        if let splinter = splinter {
            let r = Node<Element>(order: root.order)
            r.elements = [splinter.separator]
            r.children = [root, splinter.node]
            self.root = r
        }
        return (old == nil, old ?? element)
    }
}

private struct PathElement<Element: Comparable> {
    unowned(unsafe) let node: Node<Element>
    var slot: Int

    init(_ node: Node<Element>, _ slot: Int) {
        self.node = node
        self.slot = slot
    }
}

extension PathElement {
    var isLeaf: Bool { return node.isLeaf }
    var isAtEnd: Bool { return slot == node.elements.count }
    var value: Element? {
        guard slot < node.elements.count else { return nil }
        return node.elements[slot]
    }
    var child: Node<Element> {
        return node.children[slot]
    }
}

extension PathElement: Equatable {
    static func ==(left: PathElement, right: PathElement) -> Bool {
        return left.node === right.node && left.slot == right.slot
    }
}

public struct BTreeIndex<Element: Comparable> {
    fileprivate weak var root: Node<Element>?
    fileprivate let mutationCount: Int

    fileprivate var path: [PathElement<Element>]
    fileprivate var current: PathElement<Element>

    init(startOf tree: BTree<Element>) {
        self.root = tree.root
        self.mutationCount = tree.root.mutationCount
        self.path = []
        self.current = PathElement(tree.root, 0)
        while !current.isLeaf { push(0) }
    }

    init(endOf tree: BTree<Element>) {
        self.root = tree.root
        self.mutationCount = tree.root.mutationCount
        self.path = []
        self.current = PathElement(tree.root, tree.root.elements.count)
    }
}

extension BTreeIndex {
    fileprivate func validate(for root: Node<Element>) {
        precondition(self.root === root)
        precondition(self.mutationCount == root.mutationCount)
    }

    fileprivate static func validate(_ left: BTreeIndex, _ right: BTreeIndex) {
        precondition(left.root === right.root)
        precondition(left.mutationCount == right.mutationCount)
        precondition(left.root != nil)
        precondition(left.mutationCount == left.root!.mutationCount)
    }
}

extension BTreeIndex {
    fileprivate mutating func push(_ slot: Int) {
        path.append(current)
        current = PathElement(current.node.children[current.slot], slot)
    }

    fileprivate mutating func pop() {
        current = self.path.removeLast()
    }
}

extension BTreeIndex {
    fileprivate mutating func formSuccessor() {
        precondition(!current.isAtEnd, "Cannot advance beyond endIndex")
        current.slot += 1
        if current.isLeaf {
            while current.isAtEnd, current.node !== root {
                pop()
            }
        }
        else {
            while !current.isLeaf {
                push(0)
            }
        }
    }
}

extension BTreeIndex {
    fileprivate mutating func formPredecessor() {
        if current.isLeaf {
            while current.slot == 0, current.node !== root {
                pop()
            }
            precondition(current.slot > 0, "Cannot go below startIndex")
            current.slot -= 1
        }
        else {
            while !current.isLeaf {
                let c = current.child
                push(c.isLeaf ? c.elements.count - 1 : c.elements.count)
            }
        }
    }
}

extension BTreeIndex: Comparable {
    public static func ==(left: BTreeIndex, right: BTreeIndex) -> Bool {
        BTreeIndex.validate(left, right)
        return left.current == right.current
    }

    public static func <(left: BTreeIndex, right: BTreeIndex) -> Bool {
        BTreeIndex.validate(left, right)
        switch (left.current.value, right.current.value) {
        case let (.some(a), .some(b)): return a < b
        case (.none, _): return false
        default: return true
        }
    }
}

extension BTree: SortedSet {
    public typealias Index = BTreeIndex<Element>

    public var startIndex: Index { return Index(startOf: self) }
    public var endIndex: Index { return Index(endOf: self) }

    public subscript(index: Index) -> Element {
        get {
            index.validate(for: root)
            return index.current.value!
        }
    }

    public func formIndex(after i: inout Index) {
        i.validate(for: root)
        i.formSuccessor()
    }

    public func formIndex(before i: inout Index) {
        i.validate(for: root)
        i.formPredecessor()
    }

    public func index(after i: Index) -> Index {
        i.validate(for: root)
        var i = i
        i.formSuccessor()
        return i
    }

    public func index(before i: Index) -> Index {
        i.validate(for: root)
        var i = i
        i.formPredecessor()
        return i
    }
}

extension BTree {
    public var count: Int {
        return root.count
    }
}

extension Node {
    var count: Int {
        return children.reduce(elements.count) { $0 + $1.count }
    }
}

public struct BTreeIterator<Element: Comparable>: IteratorProtocol {
    let tree: BTree<Element>
    var index: BTreeIndex<Element>

    init(_ tree: BTree<Element>) {
        self.tree = tree
        self.index = tree.startIndex
    }

    public mutating func next() -> Element? {
        guard let result = index.current.value else { return nil }
        index.formSuccessor()
        return result
    }
}

extension BTree {
    public func makeIterator() -> BTreeIterator<Element> {
        return BTreeIterator(self)
    }
}
