//
//  IntBTree.swift
//  Benchmark
//
//  Created by Károly Lőrentey on 2017-02-09.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

public struct IntBTree: OrderedSet {
    fileprivate var root: Node
    fileprivate var mutationCount = 0

    init(order: Int) {
        self.root = Node(order: order)
    }

    public init() {
        self.init(order: Swift.max(16, cacheSize / (MemoryLayout<Int>.stride << 2)))
    }
}

private final class Node {
    let order: Int
    var elements: [Int]
    var children: [Node]

    init(order: Int) {
        self.order = order
        self.elements = []
        self.children = []
    }
}

//: ## Iteration

extension IntBTree {
    public func forEach(_ body: (Int) throws -> Void) rethrows {
        try root.forEach(body)
    }
}

extension Node {
    func forEach(_ body: (Int) throws -> Void) rethrows {
        if children.count == 0 {
            for i in 0 ..< elements.count {
                try body(elements[i])
            }
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

//: ## Basic properties

extension Node {
    var isLeaf: Bool { return children.isEmpty }
    var maxInts: Int { return order - 1 }
    var isTooLarge: Bool { return elements.count > maxInts }
}

//: MakeUnique

extension IntBTree {
    fileprivate mutating func makeRootUnique() -> Node {
        mutationCount += 1
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

    func makeChildUnique(_ slot: Int) -> Node {
        guard !isKnownUniquelyReferenced(&children[slot]) else {
            return children[slot]
        }
        let clone = children[slot].clone()
        children[slot] = clone
        return clone
    }
}

//: ## Lookup

extension Node {
    internal func slot(of element: Int) -> (match: Bool, index: Int) {
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

extension IntBTree {
    public func contains(_ element: Int) -> Bool {
        return root.contains(element)
    }
}

extension Node {
    func contains(_ element: Int) -> Bool {
        let slot = self.slot(of: element)
        if slot.match { return true }
        guard !children.isEmpty else { return false }
        return children[slot.index].contains(element)
    }
}

//: ## Insertion

private struct Splinter {
    let separator: Int
    let node: Node
}

extension Node {
    func split() -> Splinter {
        let count = elements.count
        let median = count / 2
        let node = Node(order: order)
        let separator = elements[median]
        node.elements.append(contentsOf: elements[median + 1 ..< count])
        elements.removeSubrange(median ..< count)

        if !children.isEmpty {
            node.children.append(contentsOf: children[median + 1 ..< count + 1])
            children.removeSubrange(median + 1 ..< count + 1)
        }
        return Splinter(separator: separator, node: node)
    }
}

extension Node {
    func insert(_ element: Int) -> (old: Int?, splinter: Splinter?) {
        let slot = self.slot(of: element)
        if slot.match {
            // The element is already in the tree.
            return (self.elements[slot.index], nil)
        }
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

extension IntBTree {
    @discardableResult
    public mutating func insert(_ element: Int) -> (inserted: Bool, memberAfterInsert: Int) {
        let root = makeRootUnique()
        let (old, splinter) = root.insert(element)
        if let splinter = splinter {
            let r = Node(order: root.order)
            r.elements = [splinter.separator]
            r.children = [root, splinter.node]
            self.root = r
        }
        return (old == nil, old ?? element)
    }
}

//: ## Collection

private struct Unowned {
    unowned(unsafe) let value: Node

    init(_ value: Node) {
        self.value = value
    }
}

public struct IntBTreeIndex: Comparable {
    fileprivate weak var root: Node?
    fileprivate let mutationCount: Int

    fileprivate var path: [(ref: Unowned, slot: Int)]
    fileprivate unowned var node: Node
    fileprivate var slot: Int

    init(startOf tree: IntBTree) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.node = tree.root
        self.slot = 0
        _descend()
    }

    init(endOf tree: IntBTree) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.node = tree.root
        self.slot = tree.root.elements.count
    }

    private mutating func _push(_ slot: Int) {
        let n = self.node
        path.append((Unowned(n), self.slot))
        self.node = n.children[self.slot]
        self.slot = slot
    }

    private mutating func _pop() {
        let last = self.path.removeLast()
        self.node = last.ref.value
        self.slot = last.slot
    }

    private mutating func _descend() {
        if self.node.isLeaf { return }
        _push(0)
        while !self.node.isLeaf {
            _push(0)
        }
    }

    fileprivate mutating func _advance() {
        slot += 1
        if _fastPath(node.isLeaf && slot < node.elements.count) {
            return
        }
        if !node.isLeaf, slot <= node.elements.count {
            _descend()
            return
        }
        if node === root {
            precondition(slot <= node.elements.count, "Cannot advance beyond endIndex")
        }
        else {
            _pop()
            while node !== root, slot == node.elements.count {
                _pop()
            }
        }
    }

    var current: Int? {
        guard let n = path.last else { return nil }
        return n.ref.value.elements[n.slot]
    }

    public static func ==(left: IntBTreeIndex, right: IntBTreeIndex) -> Bool {
        precondition(left.root != nil && left.root === right.root && left.mutationCount == right.mutationCount)
        return left.node === right.node && left.slot == right.slot
    }

    public static func <(left: IntBTreeIndex, right: IntBTreeIndex) -> Bool {
        precondition(left.root != nil && left.root === right.root && left.mutationCount == right.mutationCount)
        switch (left.current, right.current) {
        case let (.some(a), .some(b)):
            return a < b
        case (.none, _):
            return false
        default:
            return true
        }
    }
}

extension IntBTree: Collection {
    public typealias Index = IntBTreeIndex

    public var startIndex: Index { return Index(startOf: self) }
    public var endIndex: Index { return Index(endOf: self) }

    func _validate(_ index: Index) {
        precondition(index.root === self.root && index.mutationCount == self.mutationCount)
    }

    public subscript(index: Index) -> Int {
        get {
            _validate(index)
            return index.node.elements[index.slot]
        }
    }

    public func formIndex(after i: inout Index) {
        _validate(i)
        i._advance()
    }

    public func index(after i: Index) -> Index {
        _validate(i)
        var i = i
        i._advance()
        return i
    }
}


