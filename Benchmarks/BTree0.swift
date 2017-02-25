//
//  UnoptimizedBTree.swift
//  Benchmark
//
//  Created by Károly Lőrentey on 2017-02-09.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

public struct BTree0<Element: Comparable>: OrderedSet {
    fileprivate typealias Node = BTreeNode<Element>
    fileprivate var root: Node
    fileprivate var mutationCount = 0

    init(order: Int) {
        self.root = Node(order: order)
    }

    public init() {
        self.init(order: Swift.max(16, cacheSize / (MemoryLayout<Element>.stride << 2)))
    }
}

private final class BTreeNode<Element: Comparable> {
    let order: Int
    var elements: [Element]
    var children: [BTreeNode]

    init(order: Int) {
        self.order = order
        self.elements = []
        self.children = []
    }
}

//: ## Iteration

extension BTree0 {
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try root.forEach(body)
    }
}

extension BTreeNode {
    func forEach(_ body: (Element) throws -> Void) rethrows {
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

extension BTreeNode {
    var isLeaf: Bool { return children.isEmpty }
    var maxElements: Int { return order - 1 }
    var isTooLarge: Bool { return elements.count > maxElements }
}

//: MakeUnique

extension BTree0 {
    fileprivate mutating func makeRootUnique() -> Node {
        mutationCount += 1
        if isKnownUniquelyReferenced(&root) { return root }
        root = root.clone()
        return root
    }
}

extension BTreeNode {
    func clone() -> BTreeNode {
        let clone = BTreeNode(order: order)
        clone.elements = self.elements
        clone.children = self.children
        return clone
    }

    func makeChildUnique(_ slot: Int) -> BTreeNode {
        guard !isKnownUniquelyReferenced(&children[slot]) else {
            return children[slot]
        }
        let clone = children[slot].clone()
        children[slot] = clone
        return clone
    }
}

//: ## Lookup

extension BTreeNode {
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

extension BTree0 {
    public func contains(_ element: Element) -> Bool {
        return root.contains(element)
    }
}

extension BTreeNode {
    func contains(_ element: Element) -> Bool {
        let slot = self.slot(of: element)
        if slot.match { return true }
        guard !children.isEmpty else { return false }
        return children[slot.index].contains(element)
    }
}

//: ## Insertion

private struct Splinter<Element: Comparable> {
    let separator: Element
    let node: BTreeNode<Element>
}

extension BTreeNode {
    func split() -> Splinter<Element> {
        let count = elements.count
        let median = count / 2
        let node = BTreeNode(order: order)
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

extension BTreeNode {
    func insert(_ element: Element) -> (old: Element?, splinter: Splinter<Element>?) {
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

extension BTree0 {
    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
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

private struct Unowned<Wrapped: AnyObject> {
    unowned(unsafe) let value: Wrapped

    init(_ value: Wrapped) {
        self.value = value
    }
}

public struct BTreeIndex0<Element: Comparable>: Comparable {
    fileprivate typealias Node = BTreeNode<Element>

    fileprivate weak var root: Node?
    fileprivate let mutationCount: Int

    fileprivate var path: [(ref: Unowned<Node>, slot: Int)]
    fileprivate unowned var node: Node
    fileprivate var slot: Int

    init(startOf tree: BTree0<Element>) {
        self.root = tree.root
        self.mutationCount = tree.mutationCount
        self.path = []
        self.node = tree.root
        self.slot = 0
        _descend()
    }

    init(endOf tree: BTree0<Element>) {
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

    var current: Element? {
        guard let n = path.last else { return nil }
        return n.ref.value.elements[n.slot]
    }

    public static func ==(left: BTreeIndex0, right: BTreeIndex0) -> Bool {
        precondition(left.root != nil && left.root === right.root && left.mutationCount == right.mutationCount)
        return left.node === right.node && left.slot == right.slot
    }

    public static func <(left: BTreeIndex0, right: BTreeIndex0) -> Bool {
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

extension BTree0: Collection {
    public typealias Index = BTreeIndex0<Element>

    public var startIndex: Index { return Index(startOf: self) }
    public var endIndex: Index { return Index(endOf: self) }

    func _validate(_ index: Index) {
        precondition(index.root === self.root && index.mutationCount == self.mutationCount)
    }

    public subscript(index: Index) -> Element {
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


